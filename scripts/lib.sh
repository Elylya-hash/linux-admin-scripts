#!/usr/bin/env bash
# lib.sh — общие функции для скриптов набора.
# Подключается через: source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"

# Защита от повторного подключения
[[ -n "${_LIB_SH_LOADED:-}" ]] && return 0
readonly _LIB_SH_LOADED=1

# Цвета включаем только если вывод идёт в терминал
if [[ -t 2 ]]; then
    readonly C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_GREEN=$'\e[32m' C_RESET=$'\e[0m'
else
    readonly C_RED='' C_YELLOW='' C_GREEN='' C_RESET=''
fi

_log() {
    local level=$1 color=$2
    shift 2
    printf '%s %s[%s]%s %s\n' "$(date '+%F %T')" "$color" "$level" "$C_RESET" "$*" >&2
}

log_info() { _log INFO "$C_GREEN" "$@"; }
log_warn() { _log WARN "$C_YELLOW" "$@"; }
log_error() { _log ERROR "$C_RED" "$@"; }

# die <сообщение> [код возврата]
die() {
    log_error "$1"
    exit "${2:-1}"
}

# require_cmd <команда>... — проверка наличия зависимостей
require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Не найдена команда: $cmd" 127
    done
}

# require_root — завершает работу, если скрипт запущен не от root
require_root() {
    [[ ${EUID} -eq 0 ]] || die "Скрипт нужно запускать от root (sudo)" 77
}

# is_uint <значение> — истина, если это целое неотрицательное число
is_uint() {
    [[ ${1:-} =~ ^[0-9]+$ ]]
}

# notify <тема> <текст> — отправка уведомления.
# Если задан NOTIFY_CMD, текст передаётся ему на stdin, а тема — первым аргументом.
# Пример: NOTIFY_CMD='mail -s' или собственный скрипт для Telegram/Slack.
notify() {
    local subject=$1 body=$2
    if [[ -n "${NOTIFY_CMD:-}" ]]; then
        # shellcheck disable=SC2086 # NOTIFY_CMD намеренно разбивается на слова
        printf '%s\n' "$body" | ${NOTIFY_CMD} "$subject" ||
            log_warn "Не удалось отправить уведомление"
    fi
}
