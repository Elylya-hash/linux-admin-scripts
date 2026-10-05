#!/usr/bin/env bash
# Дымовые тесты без внешних зависимостей: запускают скрипты во временном каталоге
# и проверяют коды возврата и побочные эффекты. root не требуется.

set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$root/scripts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

ok() {
    passed=$((passed + 1))
    echo "  ok   $1"
}

fail() {
    failed=$((failed + 1))
    echo "  FAIL $1"
}

# expect_rc <ожидаемый код> <описание> <команда...>
expect_rc() {
    local want=$1 desc=$2 rc=0
    shift 2
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq $want ]]; then ok "$desc"; else fail "$desc (код $rc, ожидался $want)"; fi
}

check() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

echo "backup.sh"
mkdir -p "$work/src" "$work/dst"
echo "data" >"$work/src/file.txt"
echo "noise" >"$work/src/debug.log"
expect_rc 2 "без параметров — ошибка использования" bash "$scripts/backup.sh"
expect_rc 1 "несуществующий источник" bash "$scripts/backup.sh" -s "$work/nope" -d "$work/dst"
expect_rc 0 "dry-run ничего не создаёт" bash "$scripts/backup.sh" -s "$work/src" -d "$work/dst" --dry-run
check "после dry-run архивов нет" bash -c "! ls '$work'/dst/*.tar.gz"
expect_rc 0 "создание архива" bash "$scripts/backup.sh" -s "$work/src" -d "$work/dst" -n test -e '*.log'
archive=$(find "$work/dst" -name 'test-*.tar.gz' | head -n 1)
check "архив существует" test -s "$archive"
check "контрольная сумма сходится" bash -c "cd '$work/dst' && sha256sum -c ./*.sha256"
check "файл попал в архив" bash -c "tar -tzf '$archive' | grep -q 'file.txt'"
check "исключение сработало" bash -c "! tar -tzf '$archive' | grep -q 'debug.log'"
check "временных файлов не осталось" bash -c "! ls -A '$work/dst' | grep -q '\.tmp$'"
touch -d '10 days ago' "$work/dst/test-20000101-000000.tar.gz"
bash "$scripts/backup.sh" -s "$work/src" -d "$work/dst" -n test -k 5 >/dev/null 2>&1
check "ротация удалила старый архив" test ! -e "$work/dst/test-20000101-000000.tar.gz"

echo "disk-alert.sh"
expect_rc 3 "порог -w больше -c" bash "$scripts/disk-alert.sh" -w 95 -c 90
expect_rc 3 "нечисловой порог" bash "$scripts/disk-alert.sh" -w abc
expect_rc 2 "нулевые пороги дают CRITICAL" bash "$scripts/disk-alert.sh" -w 0 -c 1

echo "log-cleanup.sh"
mkdir -p "$work/logs"
touch -d '40 days ago' "$work/logs/old.log"
touch -d '5 days ago' "$work/logs/mid.log"
touch "$work/logs/new.log"
expect_rc 2 "без каталога — ошибка использования" bash "$scripts/log-cleanup.sh"
expect_rc 1 "отказ чистить системный каталог" bash "$scripts/log-cleanup.sh" -d /etc
expect_rc 0 "dry-run" bash "$scripts/log-cleanup.sh" -d "$work/logs" -n
check "dry-run ничего не удалил" test -e "$work/logs/old.log"
expect_rc 0 "очистка" bash "$scripts/log-cleanup.sh" -d "$work/logs" -z 1 -r 30
check "старый файл удалён" test ! -e "$work/logs/old.log"
check "файл среднего возраста сжат" test -e "$work/logs/mid.log.gz"
check "свежий файл не тронут" test -e "$work/logs/new.log"

echo "user-audit.sh"
cat >"$work/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
alice:x:1000:1000::/nonexistent/alice:/bin/bash
EOF
cat >"$work/shadow" <<'EOF'
root:!:19000::::::
alice:$6$hash:19000::::::
EOF
expect_rc 0 "чистая система" env PASSWD_FILE="$work/passwd" SHADOW_FILE="$work/shadow" bash "$scripts/user-audit.sh"
echo 'toor:x:0:0::/root:/bin/bash' >>"$work/passwd"
expect_rc 1 "лишний UID 0 обнаружен" env PASSWD_FILE="$work/passwd" SHADOW_FILE="$work/shadow" bash "$scripts/user-audit.sh"
sed -i '/^toor/d' "$work/passwd"
echo 'bob::19000::::::' >>"$work/shadow"
expect_rc 1 "пустой пароль обнаружен" env PASSWD_FILE="$work/passwd" SHADOW_FILE="$work/shadow" bash "$scripts/user-audit.sh"

echo "service-watchdog.sh"
expect_rc 2 "без сервисов — ошибка использования" bash "$scripts/service-watchdog.sh"

echo "sysinfo.sh"
expect_rc 0 "отрабатывает без ошибок" bash "$scripts/sysinfo.sh"

echo
echo "Пройдено: $passed, провалено: $failed"
[[ $failed -eq 0 ]]
