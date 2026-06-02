#!/bin/bash

# ============================================================
# Установка asterisk-sms-to-matrix на CentOS 7/8 + FreePBX + Asterisk 16
# Запуск от root: sudo bash setup_centos.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
    err "Скрипт нужно запускать от root: sudo bash $0"
    exit 1
fi

# --- Проверка ОС ---
if ! grep -qiE '(centos|rhel|rocky)' /etc/os-release 2>/dev/null; then
    warn "Скрипт предназначен для CentOS/RHEL. Продолжайте на свой страх и риск."
fi

ASTERISK_USER="asterisk"
INSTALL_DIR="/var/lib/asterisk/sms_gateway"
LOG_DIR="/var/log/asterisk"

echo "========================================="
echo "  asterisk-sms-to-matrix — установка на CentOS"
echo "========================================="
echo ""

# --- 1. EPEL Repository (для jq) ---
echo "[1/7] EPEL Repository..."
if ! rpm -q epel-release &>/dev/null; then
    yum install -y epel-release
    log "EPEL установлен"
else
    log "EPEL уже установлен"
fi

# --- 2. Зависимости ---
echo "[2/7] Зависимости (jq, curl)..."
yum install -y jq curl
log "jq: $(jq --version 2>&1 || echo 'установите вручную')"
log "curl: $(curl --version 2>&1 | head -1 || echo 'установите вручную')"

# --- 3. Директория для скриптов ---
echo "[3/7] Директория ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
log "Директория создана"

# --- 4. Копирование скриптов ---
echo "[4/7] Установка скриптов..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cp -v "${SCRIPT_DIR}/asterisk_sms_to_matrix.sh" "${INSTALL_DIR}/"
cp -v "${SCRIPT_DIR}/asterisk_sms_to_matrix.agi" "${INSTALL_DIR}/"
chmod 755 "${INSTALL_DIR}/asterisk_sms_to_matrix.sh"
chmod 755 "${INSTALL_DIR}/asterisk_sms_to_matrix.agi"
chown -R ${ASTERISK_USER}:${ASTERISK_USER} "${INSTALL_DIR}"
log "Скрипты установлены в ${INSTALL_DIR}"

# --- 5. Директория для логов ---
echo "[5/7] Директория логов ${LOG_DIR}..."
mkdir -p "$LOG_DIR"
touch "${LOG_DIR}/sms_to_matrix.log"
chown ${ASTERISK_USER}:${ASTERISK_USER} "${LOG_DIR}/sms_to_matrix.log"
chmod 664 "${LOG_DIR}/sms_to_matrix.log"
log "Лог-файл создан"

# --- 6. SELinux ---
echo "[6/7] Настройка SELinux..."
if command -v getenforce &>/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    warn "SELinux активен. Настраиваю контекст для curl..."

    # Устанавливаем контекст для скриптов в /var/lib/asterisk
    # asterisk_unconfd_exec_t — разрешает asterisk выполнять скрипты
    # с полным доступом к сети (curl и т.д.)
    if command -v semanage &>/dev/null; then
        semanage fcontext -a -t asterisk_unconfd_exec_t "${INSTALL_DIR}/[^/]*\.sh" 2>/dev/null || true
        semanage fcontext -a -t asterisk_unconfd_exec_t "${INSTALL_DIR}/[^/]*\.agi" 2>/dev/null || true
        restorecon -Rv "${INSTALL_DIR}" 2>/dev/null || true
    else
        warn "semanage не найден — попробуйте: yum install -y policycoreutils-python"
        warn "Без него SELinux может блокировать curl в скриптах. Используйте:"
        warn "  chcon -t asterisk_unconfd_exec_t ${INSTALL_DIR}/asterisk_sms_to_matrix.sh"
        warn "  chcon -t asterisk_unconfd_exec_t ${INSTALL_DIR}/asterisk_sms_to_matrix.agi"
    fi
    log "SELinux настроен"
else
    log "SELinux отключен, пропускаю"
fi

# --- 7. Firewall ---
echo "[7/7] Firewall..."
if command -v firewall-cmd &>/dev/null; then
    # Asterisk нужен доступ к Matrix (обычно порт 443)
    # Если Matrix self-hosted на другом порту — добавьте правило
    warn "Убедитесь, что порт 443 (HTTPS) доступен для Asterisk"
    warn "firewall-cmd --add-port=443/tcp --permanent && firewall-cmd --reload"
fi

# --- Инструкция ---
echo ""
echo "========================================="
echo "  Установка завершена!"
echo "========================================="
echo ""
echo "1. Отредактируйте настройки Matrix в скрипте:"
echo "   vi ${INSTALL_DIR}/asterisk_sms_to_matrix.sh"
echo ""
echo "2. Скопируйте диаплан в FreePBX:"
echo "   Добавьте содержимое extensions_custom.conf"
echo "   в /etc/asterisk/extensions_custom.conf"
echo ""
echo "3. Настройте chan_dongle:"
echo "   /etc/asterisk/chan_dongle.conf"
echo ""
echo "4. Перезапустите Asterisk:"
echo "   systemctl restart asterisk"
echo ""
echo "5. Проверьте SMS вручную:"
echo "   sudo -u asterisk ${INSTALL_DIR}/asterisk_sms_to_matrix.sh \"+79161234567\" \"2026-05-30 19:15\" \"Тест\""
echo ""
echo "6. Проверьте логи:"
echo "   tail -f ${LOG_DIR}/sms_to_matrix.log"
echo ""
