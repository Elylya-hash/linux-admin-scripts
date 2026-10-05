#!/usr/bin/env bash
# user-audit.sh — быстрый аудит учётных записей на сервере.
#
# Проверяет:
#   1) учётные записи с UID 0, кроме root;
#   2) учётные записи с пустым паролем;
#   3) пользователей с правами sudo (группы sudo/wheel);
#   4) пользователей с интерактивной оболочкой;
#   5) файлы authorized_keys с небезопасными правами;
#   6) учётные записи без входов дольше N дней.
#
# Код возврата: 0 — замечаний нет, 1 — найдены проблемы (пункты 1, 2, 5).

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

inactive_days=90
passwd_file=${PASSWD_FILE:-/etc/passwd}
shadow_file=${SHADOW_FILE:-/etc/shadow}

usage() {
    cat <<'EOF'
Использование: user-audit.sh [-i <дней>]

Опции:
  -i N   считать учётную запись неактивной после N дней без входа (по умолчанию: 90)
  -h     эта справка

Для полной проверки (чтение /etc/shadow) нужен root.
EOF
}

while getopts ':i:h' opt; do
    case $opt in
        i) inactive_days=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
is_uint "$inactive_days" || die "-i должно быть целым числом" 2

problems=0
section() { printf '\n== %s ==\n' "$1"; }

section "Учётные записи с UID 0 (кроме root)"
uid0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' "$passwd_file")
if [[ -n $uid0 ]]; then
    printf '%s\n' "$uid0"
    problems=1
else
    echo "нет"
fi

section "Учётные записи с пустым паролем"
if [[ -r $shadow_file ]]; then
    empty=$(awk -F: '$2 == "" {print $1}' "$shadow_file")
    if [[ -n $empty ]]; then
        printf '%s\n' "$empty"
        problems=1
    else
        echo "нет"
    fi
else
    echo "пропущено: нет доступа к $shadow_file (нужен root)"
fi

section "Пользователи с правами sudo"
found=0
for group in sudo wheel; do
    # getent возвращает 2, если группы нет, — при pipefail это нужно погасить
    members=$(getent group "$group" 2>/dev/null | cut -d: -f4 || true)
    if [[ -n $members ]]; then
        echo "$group: ${members//,/, }"
        found=1
    fi
done
((found)) || echo "нет"

section "Пользователи с интерактивной оболочкой"
awk -F: '$7 !~ /(nologin|false|sync|shutdown|halt)$/ {printf "%-20s uid=%-6s %s\n", $1, $3, $7}' "$passwd_file"

section "authorized_keys с небезопасными правами"
bad_keys=0
while IFS=: read -r _ _ _ _ _ home _; do
    keys="$home/.ssh/authorized_keys"
    [[ -f $keys ]] || continue
    perms=$(stat -c '%a' "$keys")
    # Допустимы только права владельца: 600 или 400
    if [[ $perms != 600 && $perms != 400 ]]; then
        echo "$keys (права: $perms)"
        bad_keys=1
    fi
done <"$passwd_file"
if ((bad_keys)); then problems=1; else echo "нет"; fi

section "Нет входов дольше ${inactive_days} дн."
if command -v lastlog >/dev/null 2>&1; then
    lastlog -b "$inactive_days" 2>/dev/null |
        awk 'NR > 1 && !/\*\*/ {print $1}' | grep . || echo "нет"
else
    echo "пропущено: команда lastlog недоступна"
fi

echo
if ((problems)); then
    log_warn "Найдены проблемы, требующие внимания"
    exit 1
fi
log_info "Критичных замечаний нет"
