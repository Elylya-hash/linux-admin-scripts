#!/usr/bin/env bash
# sysinfo.sh — краткая сводка о состоянии сервера «на одном экране».
# Удобно запускать первым делом при входе на незнакомую машину.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

section() { printf '\n%s== %s ==%s\n' "$C_GREEN" "$1" "$C_RESET"; }

section "Система"
# Подписи полей — латиницей: printf выравнивает по байтам, и в локали C
# (например, под cron) кириллица ломает колонки.
os=''
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091 # файл существует не на всех системах
    os=$(. /etc/os-release && echo "${PRETTY_NAME:-}")
fi
printf '%-14s %s\n' "Host:" "$(hostname -f 2>/dev/null || hostname)"
printf '%-14s %s\n' "OS:" "${os:-неизвестно}"
printf '%-14s %s\n' "Kernel:" "$(uname -r)"
printf '%-14s %s\n' "Uptime:" "$(uptime -p 2>/dev/null || uptime)"

section "Нагрузка"
read -r load1 load5 load15 _ </proc/loadavg
cores=$(nproc)
printf '%-14s %s %s %s (ядер: %s)\n' "Load average:" "$load1" "$load5" "$load15" "$cores"
# Сравниваем целую часть load1 с числом ядер
if ((${load1%%.*} >= cores)); then
    log_warn "Load average превышает число ядер"
fi

section "Память"
awk '
    /^MemTotal:/     {total = $2}
    /^MemAvailable:/ {avail = $2}
    /^SwapTotal:/    {stotal = $2}
    /^SwapFree:/     {sfree = $2}
    END {
        printf "%-14s %.1f ГБ из %.1f ГБ (%.0f%%)\n", "RAM used:",
            (total - avail) / 1048576, total / 1048576, (total - avail) * 100 / total
        if (stotal > 0)
            printf "%-14s %.1f ГБ из %.1f ГБ\n", "Swap used:",
                (stotal - sfree) / 1048576, stotal / 1048576
        else
            printf "%-14s %s\n", "Swap:", "не настроен"
    }' /proc/meminfo

section "Диски"
df -h --local --output=target,size,used,avail,pcent \
    -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null || df -h

section "Топ-5 процессов по памяти"
# awk вместо head: head закрывает канал раньше времени, и при pipefail это даёт SIGPIPE
ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | awk 'NR <= 6'

section "Слушающие порты"
if command -v ss >/dev/null 2>&1; then
    ss -tulnH 2>/dev/null | awk '{print $1, $5}' | sort -u | column -t
else
    echo "команда ss недоступна"
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    section "Упавшие юниты systemd"
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    echo "${failed:-нет}"
fi
