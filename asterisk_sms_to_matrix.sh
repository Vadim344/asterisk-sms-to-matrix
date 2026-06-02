#!/bin/bash

# ============================================================
# Asterisk GSM SMS -> Matrix (Element) Forwarder
# Asterisk 16.30 + FreePBX + chan_dongle + CentOS
# ============================================================
# Вызов из extensions_custom.conf (AGI — рекомендуется):
#   AGI(/var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.agi,${DONGLECID},${SMS_DATE},${DONGLETEXT})
#
# Вызов из extensions_custom.conf (System() — только для
# сообщений без кавычек и спецсимволов):
#   System(/var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.sh "${DONGLECID}" "${SMS_DATE}" "${DONGLETEXT}")
#
# Вызов с передачей текста через файл (System() — безопасно):
#   System(/var/lib/asterisk/sms_gateway/asterisk_sms_to_matrix.sh "${DONGLECID}" "${SMS_DATE}" /tmp/sms_${UNIQUEID}.txt)
# ============================================================

set -euo pipefail

# --- НАСТРОЙКИ (заполните свои) ---
MATRIX_HOMESERVER="https://matrix.example.com"
MATRIX_ACCESS_TOKEN="syt_xxxxxxxxxxxxxxxxxxxxxxxxxx"
MATRIX_ROOM_ID="!roomid:example.com"
# ----------------------------------

MATRIX_TXN_ID="$(date +%s%N)-$$"

SENDER="${1:-}"
DATETIME="${2:-}"
MESSAGE="${3:-}"

if [[ -z "$SENDER" || -z "$MESSAGE" ]]; then
    printf 'Usage: %s <sender> <datetime> <message>\n' "$0" >&2
    exit 1
fi

# Если третий аргумент — существующий файл, читаем текст из него
# (workaround для System(), когда кавычки в SMS ломают аргументы)
if [[ -f "$MESSAGE" ]]; then
    MESSAGE=$(cat "$MESSAGE")
fi

# --- Проверка зависимостей ---
if ! command -v jq &>/dev/null; then
    printf 'ERROR: jq is required but not installed\n' >&2
    exit 1
fi

if ! command -v curl &>/dev/null; then
    printf 'ERROR: curl is required but not installed\n' >&2
    exit 1
fi

# --- Построение JSON через jq ---
JSON_BODY=$(jq -n \
    --arg sender "$SENDER" \
    --arg dt "$DATETIME" \
    --arg text "$MESSAGE" \
    '{
        "msgtype": "m.text",
        "format": "org.matrix.custom.html",
        "body": ("Новое SMS!\nОт: " + $sender + "\nДата: " + $dt + "\nТекст: " + $text),
        "formatted_body": (
            "<b>Новое SMS!</b><br>" +
            "<b>От:</b> " + ($sender | @html) + "<br>" +
            "<b>Дата:</b> " + ($dt | @html) + "<br>" +
            "<b>Текст:</b> " + ($text | @html)
        )
    }')

# --- Отправка в Matrix с обработкой ошибок ---
HTTP_CODE=$(curl -s -o /tmp/matrix_sms_response.txt -w '%{http_code}' \
    -X PUT \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${MATRIX_TXN_ID}" \
    -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --connect-timeout 10 \
    --max-time 30 \
    -d "$JSON_BODY" \
    2>/tmp/matrix_sms_curl_err.txt) || true

# --- Обработка результата ---
LOG_FILE="/var/log/asterisk/sms_to_matrix.log"
LOG_DIR=$(dirname "$LOG_FILE")

if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
fi

if [[ "$HTTP_CODE" =~ ^2 ]]; then
    printf '%s | OK | %s | %s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$SENDER" "$DATETIME" "$MESSAGE" \
        >> "$LOG_FILE" 2>/dev/null || true
else
    CURL_ERR=$(cat /tmp/matrix_sms_curl_err.txt 2>/dev/null || echo "unknown")
    API_RESP=$(cat /tmp/matrix_sms_response.txt 2>/dev/null || echo "no response")
    printf '%s | FAIL HTTP %s | %s | %s | %s | curl: %s | api: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$HTTP_CODE" "$SENDER" "$DATETIME" "$MESSAGE" \
        "$CURL_ERR" "$API_RESP" \
        >> "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

# --- Очистка ---
rm -f /tmp/matrix_sms_response.txt /tmp/matrix_sms_curl_err.txt

exit 0
