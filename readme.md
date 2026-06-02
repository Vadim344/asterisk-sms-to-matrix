# asterisk-sms-to-matrix

Пересылка входящих SMS с GSM-донгла (chan_dongle) в комнату Matrix (Element) через Asterisk.

**Целевая платформа:** Asterisk 16.30 + FreePBX + CentOS 7/8

## Требования

- **Asterisk 16.30**
- **FreePBX 15/16**
- **chan_dongle** — драйвер для GSM-модемов/донглов
- **jq** — парсинг JSON
- **curl** — HTTP-запросы к Matrix API
- **bash** (по умолчанию на CentOS)

## Быстрая установка (CentOS)

```bash
git clone https://github.com/Vadim344/asterisk-sms-to-matrix.git
cd asterisk-sms-to-matrix
sudo bash setup_centos.sh
```

Скрипт установит зависимости, скопирует файлы, настроит SELinux и права доступа.

## Ручная установка

### 1. Установка зависимостей

```bash
# CentOS 7
yum install -y epel-release
yum install -y jq curl

# CentOS 8 / Rocky
dnf install -y epel-release
dnf install -y jq curl
```

### 2. Установка скрипта

```bash
mkdir -p /var/lib/asterisk/sms_gateway
install -m 755 asterisk_sms_to_matrix.sh /var/lib/asterisk/sms_gateway/
install -m 755 asterisk_sms_to_matrix.agi /var/lib/asterisk/sms_gateway/
chown -R asterisk:asterisk /var/lib/asterisk/sms_gateway
```

### 3. Создание лог-файла

```bash
touch /var/log/asterisk/sms_to_matrix.log
chown asterisk:asterisk /var/log/asterisk/sms_to_matrix.log
chmod 664 /var/log/asterisk/sms_to_matrix.log
```

### 4. Настройка SELinux (CentOS 7)

```bash
# Устанавливаем контекст для скриптов (разрешает curl внутри скриптов)
semanage fcontext -a -t asterisk_unconfd_exec_t '/var/lib/asterisk/sms_gateway/.*\.sh'
semanage fcontext -a -t asterisk_unconfd_exec_t '/var/lib/asterisk/sms_gateway/.*\.agi'
restorecon -Rv /var/lib/asterisk/sms_gateway

# Если semanage не найден: yum install -y policycoreutils-python
# Альтернатива:
#   chcon -t asterisk_unconfd_exec_t /var/lib/asterisk/sms_gateway/*
```

## Настройка Matrix

1. Создайте комнату в Matrix (или используйте существующую)
2. Получите **Access Token**:
   - Element Web → Настройки → Расширенные → Разработчик → доступ к API
   - Или через API: `POST /_matrix/client/v3/login`
3. Получите **Room ID**:
   - Element Web → Настройки комнаты → Advanced → скопируйте идентификатор
   - Формат: `!abc123:example.com`

Отредактируйте переменные в начале скрипта:

```bash
vi /var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.sh
```

```bash
MATRIX_HOMESERVER="https://matrix.example.com"
MATRIX_ACCESS_TOKEN="syt_xxxxxxxxxxxxxxxxxxxxxxxxxx"
MATRIX_ROOM_ID="!roomid:example.com"
```

## Настройка FreePBX

### extensions_custom.conf

Добавьте содержимое `extensions_custom.conf` в файл:

```bash
vi /etc/asterisk/extensions_custom.conf
```

```ini
[sms-incoming]

; === AGI() — рекомендуется (безопасная передача спецсимволов) ===
exten => sms,1,NoOp(--- SMS от ${DONGLECID} ---)
 same => n,Set(SMS_DATE=${STRFTIME(${EPOCH},,%Y-%m-%d %H:%M:%S)})
 same => n,AGI(/var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.agi,${DONGLECID},${SMS_DATE},${DONGLETEXT})
 same => n,Hangup()
```

> **AGI vs System():** AGI передаёт аргументы через stdin (agi_arg_N), поэтому кавычки и спецсимволы в SMS не ломают вызов. System() передаёт через командную строку — текст с `"` или `$` разобьёт аргументы. AGI — безопасный выбор.

> **Важно:** Не редактируйте `extensions.conf` напрямую — FreePBX перезаписывает его при каждом изменении через GUI.

### chan_dongle.conf

```ini
[dongle0]
context=sms-incoming
sms_extension=sms
group=0
imsi=xxxxxxxxxxxxxxx
imei=xxxxxxxxxxxxxxx
pin=1234
apn=internet
```

### Подключение контекста в FreePBX

Чтобы входящие SMS обрабатывались через `sms-incoming`:

**Вариант A** — через FreePBX GUI:
1. Connectivity → Inbound Routes
2. Добавьте маршрут для chan_dongle
3. Set Destination: Custom Context → `sms-incoming`

**Вариант B** — через extensions_custom.conf:
```ini
[from-external]
include => sms-incoming
```

## Перезапуск Asterisk

```bash
# Через FreePBX
fwconsole reload

# Или напрямую
systemctl restart asterisk
```

## Переменные chan_dongle для SMS

| Переменная | Описание | Пример |
|------------|----------|--------|
| `${DONGLECID}` | Номер отправителя SMS | `+79161234567` |
| `${DONGLETEXT}` | Текст сообщения | `Ваш код: 1234` |
| `${DONGLEPROVIDER}` | Имя устройства (не номер!) | `dongle0` |

## Формат уведомления в Matrix

> **Новое SMS!**
> **От:** +79161234567
> **Дата:** 2026-05-30 19:15
> **Текст:** Ваш код: 1234

## Логирование

```
/var/log/asterisk/sms_to_matrix.log
```

```
2026-05-30 19:15:23 | OK | +79161234567 | 2026-05-30 19:15:00 | Ваш код: 1234
2026-05-30 19:16:01 | FAIL HTTP 403 | +79169999999 | 2026-05-30 19:15:50 | Тест | curl: ... | api: ...
```

## Диагностика

### Проверка скрипта вручную

```bash
sudo -u asterisk /var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.sh \
    "+79161234567" "2026-05-30 19:15" "Тестовое сообщение"
```

### Проверка curl до Matrix

```bash
sudo -u asterisk curl -s -o /dev/null -w '%{http_code}' \
  -X PUT "https://matrix.example.com/_matrix/client/v3/rooms/!roomid:example.com/send/m.room.message/test123" \
  -H "Authorization: Bearer syt_xxxx" \
  -H "Content-Type: application/json" \
  -d '{"msgtype":"m.text","body":"test"}'
```

### Проверка chan_dongle

```bash
asterisk -rx "dongle show devices"
asterisk -rx "dongle show stats"
```

### Проверка SELinux

```bash
getenforce                          # Должен вернуть Enforcing или Permissive
ausearch -m avc --recent            # Последние отказы SELinux
audit2why < /var/log/audit/audit.log  # Причины отказов
```

### Проверка FreePBX диаплана

```bash
asterisk -rx "dialplan show sms@sms-incoming"
```

## Частые ошибки

| Симптом | Причина | Решение |
|---------|---------|---------|
| SMS не доходит в Matrix | Неверный токен | Проверьте Access Token |
| `HTTP 403` | Токен истёк / бот не в комнате | Пересоздайте токен, пригласите бота |
| `HTTP 404` | Неверный Room ID | Формат `!xxx:domain` |
| `jq: command not found` | jq не установлен | `yum install jq` |
| SMS не приходит в Asterisk | chan_dongle не подключён | `dongle show devices` |
| `Permission denied` (SELinux) | SELinux блокирует curl | Настройте контекст (см. раздел SELinux) |
| `Permission denied` (Unix) | Неверные права на скрипт | `chmod 755`, `chown asterisk:asterisk` |
| Пустой текст в логе | `DONGLETEXT` не передан | Проверьте `sms_extension` в chan_dongle.conf |
| FreePBX не видит диаплан | Не включён в [from-external] | `include => sms-incoming` |
| `Can't create thread` | AGI вызывается слишком часто | Используйте System() вместо AGI() |
| Сломанные аргументы в логе | SMS содержит `"`, `$` или `` ` `` | Используйте AGI() вместо System() |

## Лицензия

MIT
