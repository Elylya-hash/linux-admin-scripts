#!/usr/bin/env bash
# log-cleanup.sh — сжатие и удаление старых логов приложений.
#
# Для системных логов правильнее использовать logrotate. Этот скрипт нужен для
# приложений, которые сами создают файлы вида app-2024-01-31.log и никогда их
# не удаляют.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    cat <<'EOF'
Использование: log-cleanup.sh -d <каталог> [опции]

Опции:
  -d DIR    каталог с логами
  -p GLOB   шаблон имён файлов (по умолчанию: *.log)
  -z N      сжимать файлы старше N дней (по умолчанию: 1)
  -r N      удалять файлы старше N дней (по умолчанию: 30)
  -n        dry-run: только показать, что будет сделано
  -h        эта справка
EOF
}

dir=''
pattern='*.log'
compress_days=1
remove_days=30
dry_run=0

while getopts ':d:p:z:r:nh' opt; do
    case $opt in
        d) dir=$OPTARG ;;
        p) pattern=$OPTARG ;;
        z) compress_days=$OPTARG ;;
        r) remove_days=$OPTARG ;;
        n) dry_run=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -n $dir ]] || { usage >&2; die "Не указан каталог (-d)" 2; }
[[ -d $dir ]] || die "Каталог не существует: $dir"
if ! is_uint "$compress_days" || ! is_uint "$remove_days"; then
    die "-z и -r должны быть целыми числами" 2
fi
((compress_days < remove_days)) || die "-z должно быть меньше -r" 2
require_cmd find gzip

# Защита от запуска по системным каталогам из-за опечатки в параметре
case $(realpath "$dir") in
    / | /etc | /usr | /bin | /sbin | /lib | /boot | /home | /root | /var)
        die "Отказ: слишком опасный каталог для очистки: $dir"
        ;;
esac

before=$(du -sk "$dir" | cut -f1)

if ((dry_run)); then
    log_info "[dry-run] Будут удалены:"
    find "$dir" -type f \( -name "$pattern" -o -name "${pattern}.gz" \) -mtime "+${remove_days}" -print
    log_info "[dry-run] Будут сжаты:"
    find "$dir" -type f -name "$pattern" -mtime "+${compress_days}" ! -mtime "+${remove_days}" -print
    exit 0
fi

# Сначала удаляем, чтобы не тратить CPU на сжатие того, что всё равно удалится
removed=$(find "$dir" -type f \( -name "$pattern" -o -name "${pattern}.gz" \) \
    -mtime "+${remove_days}" -print -delete | wc -l)

compressed=0
while IFS= read -r -d '' file; do
    # Файл может быть открыт приложением — пропускаем, если он ещё пишется
    if command -v fuser >/dev/null 2>&1 && fuser -s "$file" 2>/dev/null; then
        log_warn "Пропускаю открытый файл: $file"
        continue
    fi
    gzip -- "$file"
    compressed=$((compressed + 1))
done < <(find "$dir" -type f -name "$pattern" -mtime "+${compress_days}" -print0)

after=$(du -sk "$dir" | cut -f1)
log_info "Удалено: ${removed}, сжато: ${compressed}, освобождено: $(((before - after) / 1024)) МБ"
