#!/usr/bin/env bash
# disk-alert.sh — контроль заполнения файловых систем (место и inodes).
#
# Коды возврата совместимы с Nagios/Icinga:
#   0 — OK, 1 — WARNING, 2 — CRITICAL, 3 — ошибка запуска.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    cat <<'EOF'
Использование: disk-alert.sh [-w <процент>] [-c <процент>] [-x <тип ФС>]...

Опции:
  -w N   порог предупреждения, % (по умолчанию: 80)
  -c N   критический порог, % (по умолчанию: 90)
  -x FS  исключить тип ФС (можно несколько раз; tmpfs, devtmpfs, squashfs,
         overlay исключены всегда)
  -h     эта справка

Уведомления: переменная NOTIFY_CMD (см. README).
EOF
}

warn=80
crit=90
exclude_types=(tmpfs devtmpfs squashfs overlay)

while getopts ':w:c:x:h' opt; do
    case $opt in
        w) warn=$OPTARG ;;
        c) crit=$OPTARG ;;
        x) exclude_types+=("$OPTARG") ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 3 ;;
    esac
done

if ! is_uint "$warn" || ! is_uint "$crit"; then
    die "Пороги должны быть целыми числами" 3
fi
((warn < crit)) || die "Порог -w должен быть меньше порога -c" 3
require_cmd df awk

# shellcheck disable=SC2054 # запятые — часть значения опции --output
df_args=(--local --output=target,pcent,ipcent)
for t in "${exclude_types[@]}"; do
    df_args+=("--exclude-type=$t")
done

status=0
report=''

# Читаем вывод df построчно, пропуская заголовок
while read -r mount pcent ipcent; do
    for pair in "место:${pcent}" "inodes:${ipcent}"; do
        kind=${pair%%:*}
        value=${pair##*:}
        value=${value%\%}
        # У некоторых ФС (например, btrfs) вместо процента inodes стоит «-»
        is_uint "$value" || continue

        if ((value >= crit)); then
            level=CRITICAL
            status=2
        elif ((value >= warn)); then
            level=WARNING
            ((status < 1)) && status=1
        else
            continue
        fi
        report+="${level}: ${mount} — ${kind} ${value}%"$'\n'
    done
done < <(df "${df_args[@]}" | awk 'NR > 1')

if ((status == 0)); then
    log_info "OK: все файловые системы ниже ${warn}%"
    exit 0
fi

printf '%s' "$report"
notify "[$(hostname -s)] Заканчивается место на диске" "$report"
exit "$status"
