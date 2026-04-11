#!/bin/bash
# ============================================================
#   ZIVPN UDP PANEL - MASTER INSTALLER
#   Support: Debian 9/10/11/12 | Ubuntu 18/20/22/24
#   Usage  : bash <(curl -s https://raw.githubusercontent.com/chanelog/cek/main/master-install.sh)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

PANEL_DIR="/etc/zivpn-panel"
BIN_DIR="/usr/local/bin"
BOT_DIR="$PANEL_DIR/bot"
DB_FILE="$PANEL_DIR/database.json"
REPO_RAW="https://raw.githubusercontent.com/chanelog/cek/main"
TMP_DIR="/tmp/zivpn_install"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1; }
}

detect_os() {
    . /etc/os-release
    OS=$ID; VER=$VERSION_ID
    echo -e "${GREEN}OS: $OS $VER${NC}"
    case $OS in
        debian|ubuntu) ;;
        *) echo -e "${RED}OS tidak didukung! Gunakan Debian/Ubuntu.${NC}"; exit 1 ;;
    esac
}

install_deps() {
    echo -e "${CYAN}[1/6] Installing dependencies...${NC}"
    apt-get update -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget jq openssl iptables \
        python3 python3-pip net-tools cron \
        bc uuid-runtime ufw lsb-release >/dev/null 2>&1

    # Install python-telegram-bot
    pip3 install "python-telegram-bot>=20.0" requests --quiet 2>/dev/null || \
    pip3 install "python-telegram-bot" requests --quiet 2>/dev/null
    echo -e "${GREEN}  ✓ Dependencies OK${NC}"
}

setup_dirs() {
    echo -e "${CYAN}[2/6] Setting up directories...${NC}"
    mkdir -p "$PANEL_DIR" "$BOT_DIR" "$PANEL_DIR/backup" "$PANEL_DIR/logs" "$TMP_DIR"
    echo -e "${GREEN}  ✓ Directories OK${NC}"
}

install_zivpn() {
    echo -e "${CYAN}[3/6] Installing ZIVPN binary...${NC}"

    if [ ! -f "$BIN_DIR/zivpn" ]; then
        wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" \
            -O "$BIN_DIR/zivpn"
        chmod +x "$BIN_DIR/zivpn"
    fi

    mkdir -p /etc/zivpn

    if [ ! -f /etc/zivpn/config.json ]; then
        wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" \
            -O /etc/zivpn/config.json
    fi

    if [ ! -f /etc/zivpn/zivpn.crt ]; then
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/C=US/ST=CA/L=LA/O=ZiVPN/CN=zivpn" \
            -keyout /etc/zivpn/zivpn.key \
            -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
    fi

    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

    cat > /etc/systemd/system/zivpn.service <<'SVCEOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVCEOF

    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 \
        -j DNAT --to-destination :5667 2>/dev/null
    ufw allow 6000:19999/udp >/dev/null 2>&1
    ufw allow 5667/udp >/dev/null 2>&1

    systemctl daemon-reload
    systemctl enable zivpn.service >/dev/null 2>&1
    systemctl start zivpn.service >/dev/null 2>&1
    echo -e "${GREEN}  ✓ ZIVPN binary OK${NC}"
}

init_db() {
    if [ ! -f "$DB_FILE" ]; then
        IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
        HOSTNAME=$(hostname)
        OS_INFO=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        cat > "$DB_FILE" <<DBEOF
{
  "accounts": [],
  "resellers": [],
  "servers": [
    {
      "id": "local001",
      "name": "VPS-1 Local",
      "ip": "$IP",
      "port": "6000-19999",
      "active": true
    }
  ],
  "settings": {
    "bot_token": "",
    "admin_ids": [],
    "qris_photo": "",
    "price_15days": 6000,
    "price_30days": 10000,
    "vps_info": {
      "hostname": "$HOSTNAME",
      "ip": "$IP",
      "os": "$OS_INFO"
    }
  }
}
DBEOF
    fi
}

download_scripts() {
    echo -e "${CYAN}[4/6] Downloading panel scripts dari GitHub...${NC}"

    # Download account.sh
    wget -q "$REPO_RAW/account.sh" -O "$TMP_DIR/account.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Gagal download account.sh!${NC}"; exit 1
    fi

    # Download panel.sh
    wget -q "$REPO_RAW/panel.sh" -O "$TMP_DIR/panel.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Gagal download panel.sh!${NC}"; exit 1
    fi

    # Download bot.py
    wget -q "$REPO_RAW/bot.py" -O "$TMP_DIR/bot.py"
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Gagal download bot.py!${NC}"; exit 1
    fi

    # Install ke lokasi yang benar
    cp "$TMP_DIR/account.sh" "$BIN_DIR/zivpn-account"
    cp "$TMP_DIR/panel.sh"   "$BIN_DIR/zivpn-panel"
    cp "$TMP_DIR/bot.py"     "$BOT_DIR/bot.py"

    chmod +x "$BIN_DIR/zivpn-account"
    chmod +x "$BIN_DIR/zivpn-panel"
    chmod +x "$BOT_DIR/bot.py"

    # Bersihkan tmp
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}  ✓ Scripts OK${NC}"
}

setup_cron() {
    echo -e "${CYAN}[5/6] Setting up cron jobs...${NC}"
    (crontab -l 2>/dev/null | grep -v zivpn-account
     echo "0 * * * * $BIN_DIR/zivpn-account delete-expired >/dev/null 2>&1"
     echo "*/5 * * * * $BIN_DIR/zivpn-account check-maxlogin >/dev/null 2>&1"
    ) | crontab -
    echo -e "${GREEN}  ✓ Cron OK${NC}"
}

configure_bot() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════${NC}"
    echo -e "${YELLOW}    KONFIGURASI BOT TELEGRAM         ${NC}"
    echo -e "${YELLOW}════════════════════════════════════${NC}"
    echo -e "${WHITE}1. Buka Telegram, cari @BotFather${NC}"
    echo -e "${WHITE}2. Ketik /newbot dan ikuti instruksi${NC}"
    echo -e "${WHITE}3. Copy TOKEN yang diberikan${NC}"
    echo ""
    read -p "  Bot TOKEN   : " BOT_TOKEN
    echo ""
    echo -e "${WHITE}Cari Telegram ID kamu di @userinfobot${NC}"
    echo -e "${WHITE}Jika lebih dari 1 admin, pisah dengan koma (contoh: 123456,789012)${NC}"
    read -p "  Admin ID(s) : " ADMIN_IDS

    python3 - <<PYEOF
import json

with open('$DB_FILE') as f:
    db = json.load(f)

db['settings']['bot_token'] = '$BOT_TOKEN'
admin_list = [int(x.strip()) for x in '$ADMIN_IDS'.split(',') if x.strip().isdigit()]
db['settings']['admin_ids'] = admin_list

with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)

print("  Config disimpan!")
PYEOF

    echo ""
    echo -e "${CYAN}[6/6] Starting bot service...${NC}"

    cat > /etc/systemd/system/zivpn-bot.service <<BOTEOF
[Unit]
Description=ZIVPN Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/bot.py
Restart=always
RestartSec=5
Environment=BOT_TOKEN=$BOT_TOKEN
Environment=DB_FILE=$DB_FILE

[Install]
WantedBy=multi-user.target
BOTEOF

    systemctl daemon-reload
    systemctl enable zivpn-bot.service >/dev/null 2>&1
    systemctl start zivpn-bot.service >/dev/null 2>&1

    sleep 2
    if systemctl is-active --quiet zivpn-bot.service; then
        echo -e "${GREEN}  ✓ Bot service OK${NC}"
    else
        echo -e "${YELLOW}  ⚠ Bot service gagal start, cek log: journalctl -u zivpn-bot.service${NC}"
    fi
}

print_done() {
    IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    ZIVPN_STATUS=$(systemctl is-active zivpn.service 2>/dev/null)
    BOT_STATUS=$(systemctl is-active zivpn-bot.service 2>/dev/null)
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅  ZIVPN PANEL TERPASANG SEMPURNA!   ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  IP VPS     : ${CYAN}$IP${NC}"
    echo -e "${GREEN}║${NC}  Panel CMD  : ${YELLOW}zivpn-panel${NC}"
    echo -e "${GREEN}║${NC}  Akun CMD   : ${YELLOW}zivpn-account${NC}"
    echo -e "${GREEN}║${NC}  ZIVPN      : ${GREEN}$ZIVPN_STATUS${NC}"
    echo -e "${GREEN}║${NC}  Bot TG     : ${GREEN}$BOT_STATUS${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Jalankan panel: ${YELLOW}zivpn-panel${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    ZIVPN UDP PANEL - MASTER INSTALLER   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    check_root
    detect_os
    setup_dirs
    install_deps
    install_zivpn
    init_db
    download_scripts
    setup_cron
    configure_bot
    print_done
}

main
