# linux-admin-scripts

[![CI](https://github.com/Elylya-hash/linux-admin-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/Elylya-hash/linux-admin-scripts/actions/workflows/ci.yml)

Набор Bash-скриптов для повседневных задач администрирования Linux-серверов:
резервное копирование, контроль дисков и сервисов, аудит учётных записей,
очистка логов.

Скрипты написаны так, чтобы их было не страшно запускать из cron на боевом
сервере: строгий режим (`set -euo pipefail`), проверка входных параметров,
`--dry-run` для разрушающих операций, осмысленные коды возврата и проверка
ShellCheck в CI.

## Состав

| Скрипт | Назначение | Нужен root |
|---|---|---|
| [`backup.sh`](scripts/backup.sh) | Архивирование каталогов с проверкой целостности, SHA-256 и ротацией | зависит от источников |
| [`disk-alert.sh`](scripts/disk-alert.sh) | Контроль места и inodes, коды возврата в стиле Nagios | нет |
| [`service-watchdog.sh`](scripts/service-watchdog.sh) | Проверка systemd-сервисов, перезапуск, выдержка из журнала в уведомлении | только для `-r` |
| [`user-audit.sh`](scripts/user-audit.sh) | Аудит учётных записей: UID 0, пустые пароли, sudo, права на `authorized_keys` | для полной проверки |
| [`log-cleanup.sh`](scripts/log-cleanup.sh) | Сжатие и удаление старых логов приложений | зависит от каталога |
| [`sysinfo.sh`](scripts/sysinfo.sh) | Сводка о сервере на одном экране | нет |
| [`lib.sh`](scripts/lib.sh) | Общие функции: логирование, проверки, уведомления | — |

## Быстрый старт

```bash
git clone https://github.com/Elylya-hash/linux-admin-scripts.git
cd linux-admin-scripts

bash scripts/sysinfo.sh
bash scripts/disk-alert.sh -w 75 -c 90
sudo bash scripts/user-audit.sh
```

Установка в систему (`/usr/local/bin`):

```bash
sudo make install
```

## Примеры

Резервная копия `/etc` и `/var/www`, хранить 14 дней, логи не включать:

```bash
sudo backup.sh -s /etc -s /var/www -d /backup -k 14 -e '*.log'
```

Сначала посмотреть, что будет сделано:

```bash
sudo backup.sh -s /etc -d /backup --dry-run
```

Следить за сервисами и перезапускать упавшие:

```bash
sudo service-watchdog.sh -r nginx ssh cron
```

Сжимать логи приложения старше 2 дней, удалять старше 60:

```bash
log-cleanup.sh -d /opt/app/logs -p 'app-*.log' -z 2 -r 60
```

### Запуск по расписанию

```cron
# /etc/cron.d/admin-scripts
NOTIFY_CMD="mail -s"
0  2 * * *  root  /usr/local/bin/backup.sh -s /etc -s /var/www -d /backup -k 14
*/10 * * * * root  /usr/local/bin/disk-alert.sh -w 80 -c 90 >/dev/null
*/5 * * * *  root  /usr/local/bin/service-watchdog.sh -r nginx ssh >/dev/null
30 3 * * *  root  /usr/local/bin/log-cleanup.sh -d /opt/app/logs
```

### Уведомления

Скрипты ничего не знают о конкретном канале доставки. Если задана переменная
`NOTIFY_CMD`, ей на stdin передаётся текст, а первым аргументом — тема:

```bash
NOTIFY_CMD='mail -s' disk-alert.sh              # почта
NOTIFY_CMD='/usr/local/bin/tg-send' disk-alert.sh  # свой скрипт для мессенджера
```

## Коды возврата

| Скрипт | 0 | 1 | 2 | Другое |
|---|---|---|---|---|
| `disk-alert.sh` | OK | WARNING | CRITICAL | 3 — ошибка запуска |
| `service-watchdog.sh` | все работают | есть упавшие | ошибка параметров | 77 — нужен root |
| `user-audit.sh` | замечаний нет | найдены проблемы | ошибка параметров | |
| `backup.sh`, `log-cleanup.sh` | успех | ошибка выполнения | ошибка параметров | 75 — уже запущен |

## Принятые решения

- **Атомарность бэкапа.** Архив пишется во временный файл в каталоге назначения
  и переименовывается только после проверки `tar -t`. Упавший посреди работы
  скрипт не оставляет файла, похожего на годный бэкап.
- **Блокировка.** `flock -n` вместо pid-файла: блокировка снимается ядром при
  любом завершении процесса, «зависших» lock-файлов не бывает.
- **Защита от опечаток.** `log-cleanup.sh` отказывается работать с `/`, `/etc`,
  `/var` и другими системными каталогами.
- **Тестируемость.** `user-audit.sh` принимает пути к `passwd`/`shadow` через
  переменные окружения, поэтому проверяется в CI без root и без изменения системы.

## Разработка

```bash
make lint   # shellcheck
make test   # дымовые тесты, root не нужен
```

Требования: Bash 4.4+, coreutils, util-linux (`flock`), для части скриптов — systemd.
Проверено на Ubuntu 24.04 (Bash 5.2); CI запускается на Ubuntu 24.04.

## Лицензия

[MIT](LICENSE)
