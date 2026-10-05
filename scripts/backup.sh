#!/usr/bin/env bash
# backup.sh — архивирование каталогов с ротацией старых копий.
#
# Особенности:
#   * архив сначала пишется во временный файл и только потом переименовывается,
#     поэтому «битых» архивов в каталоге назначения не остаётся;
#   * блокировка через flock не даёт запустить две копии одновременно;
#   * после создания архив проверяется (tar -t) и получает файл с SHA-256;
#   * ротация по возрасту (--keep-days).

set -euo pipefail

# shellcheck source=scripts/lib.sh
# readlink -f: скрипт может быть запущен через симлинк из /usr/local/bin
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"

usage() {
    cat <<'EOF'
Использование: backup.sh -s <каталог> [-s <каталог>...] -d <куда> [опции]

Опции:
  -s, --source DIR      что архивировать (можно указать несколько раз)
  -d, --dest DIR        каталог для архивов
  -n, --name NAME       префикс имени архива (по умолчанию: имя хоста)
  -k, --keep-days N     хранить архивы N дней (по умолчанию: 7)
  -e, --exclude PATTERN шаблон исключения для tar (можно несколько раз)
      --dry-run         показать, что будет сделано, ничего не меняя
  -h, --help            эта справка

Пример:
  backup.sh -s /etc -s /var/www -d /backup -k 14 -e '*.log'
EOF
}

sources=()
excludes=()
dest=''
name=$(hostname -s)
keep_days=7
dry_run=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -s | --source) sources+=("${2:?не указан каталог}"); shift 2 ;;
        -d | --dest) dest=${2:?не указан каталог}; shift 2 ;;
        -n | --name) name=${2:?не указано имя}; shift 2 ;;
        -k | --keep-days) keep_days=${2:?не указано число}; shift 2 ;;
        -e | --exclude) excludes+=("--exclude=${2:?не указан шаблон}"); shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "Неизвестный параметр: $1" 2 ;;
    esac
done

[[ ${#sources[@]} -gt 0 ]] || { usage >&2; die "Не указан ни один источник (-s)" 2; }
[[ -n $dest ]] || { usage >&2; die "Не указан каталог назначения (-d)" 2; }
is_uint "$keep_days" || die "--keep-days должно быть целым числом" 2
require_cmd tar gzip sha256sum flock find

for src in "${sources[@]}"; do
    [[ -d $src ]] || die "Источник не существует или не каталог: $src"
done

archive="${dest%/}/${name}-$(date '+%Y%m%d-%H%M%S').tar.gz"

if ((dry_run)); then
    log_info "[dry-run] Будет создан архив: $archive"
    log_info "[dry-run] Источники: ${sources[*]}"
    log_info "[dry-run] Будут удалены архивы старше ${keep_days} дн.:"
    [[ -d $dest ]] && find "$dest" -maxdepth 1 -type f -name "${name}-*.tar.gz*" -mtime "+${keep_days}" -print
    exit 0
fi

mkdir -p "$dest"

# Блокировка: второй экземпляр завершится сразу, а не будет ждать
exec 9>"${dest%/}/.${name}.lock"
flock -n 9 || die "Резервное копирование уже выполняется (lock занят)" 75

tmp=$(mktemp "${dest%/}/.${name}.XXXXXX.tmp")
trap 'rm -f "$tmp"' EXIT

log_info "Создаю архив: $archive"
# tar возвращает 1, если файлы менялись во время чтения, — это не ошибка для бэкапа
rc=0
tar --create --gzip --file "$tmp" --warning=no-file-changed "${excludes[@]}" "${sources[@]}" 2>/dev/null || rc=$?
((rc <= 1)) || die "tar завершился с ошибкой (код $rc)"

log_info "Проверяю целостность архива"
tar --list --gzip --file "$tmp" >/dev/null || die "Архив повреждён"

mv "$tmp" "$archive"
chmod 600 "$archive"
(cd "$dest" && sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256")

size=$(du -h "$archive" | cut -f1)
log_info "Готово: $archive ($size)"

log_info "Удаляю архивы старше ${keep_days} дн."
find "$dest" -maxdepth 1 -type f -name "${name}-*.tar.gz*" -mtime "+${keep_days}" -print -delete
