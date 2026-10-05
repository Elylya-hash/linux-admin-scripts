#!/usr/bin/env bash
# service-watchdog.sh — проверка systemd-сервисов и (опционально) их перезапуск.
#
# Скрипт не заменяет Restart= в unit-файле: он нужен там, где сервис формально
# «active», но нужно дополнительное оповещение, либо юнит менять нельзя.
#
# Код возврата: 0 — все сервисы работают, 1 — есть неработающие.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    cat <<'EOF'
Использование: service-watchdog.sh [-r] [-f <файл>] [сервис...]

Опции:
  -r        пытаться перезапустить упавшие сервисы (нужен root)
  -f FILE   файл со списком сервисов (по одному в строке, # — комментарий)
  -h        эта справка

Пример:
  service-watchdog.sh -r nginx sshd cron
EOF
}

restart=0
list_file=''

while getopts ':rf:h' opt; do
    case $opt in
        r) restart=1 ;;
        f) list_file=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

services=("$@")
if [[ -n $list_file ]]; then
    [[ -r $list_file ]] || die "Не могу прочитать файл: $list_file" 2
    while IFS= read -r line; do
        line=${line%%#*}
        line=${line//[[:space:]]/}
        [[ -n $line ]] && services+=("$line")
    done <"$list_file"
fi

[[ ${#services[@]} -gt 0 ]] || { usage >&2; die "Не указан ни один сервис" 2; }
require_cmd systemctl
((restart)) && require_root

failed=()

for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        log_info "$svc: работает"
        continue
    fi

    state=$(systemctl is-active "$svc" 2>/dev/null || true)
    log_warn "$svc: не работает (состояние: ${state:-unknown})"

    if ((restart)); then
        log_info "$svc: перезапускаю"
        if systemctl restart "$svc" && sleep 2 && systemctl is-active --quiet "$svc"; then
            log_info "$svc: успешно перезапущен"
            notify "[$(hostname -s)] Сервис $svc был перезапущен" \
                "Сервис $svc находился в состоянии '${state}' и был перезапущен."
            continue
        fi
        log_error "$svc: перезапуск не помог"
    fi

    failed+=("$svc")
done

if [[ ${#failed[@]} -gt 0 ]]; then
    body="Не работают сервисы: ${failed[*]}"$'\n\n'
    for svc in "${failed[@]}"; do
        # Последние строки журнала сильно ускоряют разбор инцидента
        body+="--- $svc ---"$'\n'
        body+=$(journalctl -u "$svc" -n 10 --no-pager 2>/dev/null || true)$'\n'
    done
    notify "[$(hostname -s)] Не работают сервисы: ${failed[*]}" "$body"
    exit 1
fi
