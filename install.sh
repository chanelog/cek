#!/bin/bash
# ============================================================
#   ZIVPN UDP PANEL - FULL INSTALLER
#   Support: Debian 9/10/11/12 | Ubuntu 18/20/22/24
#   Creator: Auto-generated Panel
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

PANEL_DIR="/etc/zivpn-panel"
BIN_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
DB_FILE="$PANEL_DIR/database.json"
CONFIG_FILE="$PANEL_DIR/panel.conf"
BOT_DIR="$PANEL_DIR/bot"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo -e "${RED}OS tidak dikenali!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Terdeteksi OS: $OS $VER${NC}"
}

install_dependencies() {
    echo -e "${CYAN}Installing dependencies...${NC}"
    apt-get update -y >/dev/null 2>&1
    apt-get install -y \
        curl wget jq openssl iptables ufw \
        python3 python3-pip net-tools \
        cron bc uuid-runtime >/dev/null 2>&1

    pip3 install python-telegram-bot requests >/dev/null 2>&1
    echo -e "${GREEN}Dependencies installed!${NC}"
}

install_zivpn_bin() {
    echo -e "${CYAN}Installing ZIVPN binary...${NC}"
    if [ -f "$BIN_DIR/zivpn" ]; then
        echo -e "${YELLOW}Binary sudah ada, skip...${NC}"
        return
    fi
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
        -O "$BIN_DIR/zivpn"
    chmod +x "$BIN_DIR/zivpn"

    mkdir -p /etc/zivpn
    wget -q https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json \
        -O /etc/zivpn/config.json

    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=ZiVPN/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

    cat <<EOF > /etc/systemd/system/zivpn.service
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
EOF

    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
    ufw allow 6000:19999/udp >/dev/null 2>&1
    ufw allow 5667/udp >/dev/null 2>&1

    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    echo -e "${GREEN}ZIVPN binary installed!${NC}"
}

setup_panel_dirs() {
    mkdir -p "$PANEL_DIR"
    mkdir -p "$BOT_DIR"
    mkdir -p "$PANEL_DIR/backup"
    mkdir -p "$PANEL_DIR/logs"
}

init_database() {
    if [ ! -f "$DB_FILE" ]; then
        cat <<EOF > "$DB_FILE"
{
  "accounts": [],
  "resellers": [],
  "servers": [],
  "settings": {
    "bot_token": "",
    "admin_ids": [],
    "qris_photo": "",
    "price_15days": 6000,
    "price_30days": 10000,
    "vps_info": {
      "hostname": "",
      "ip": "",
      "os": "",
      "ram": "",
      "cpu": ""
    }
  }
}
EOF
        echo -e "${GREEN}Database initialized!${NC}"
    fi
}

collect_bot_config() {
    echo ""
    echo -e "${YELLOW}====== KONFIGURASI BOT TELEGRAM ======${NC}"
    read -p "Masukkan BOT TOKEN Telegram: " BOT_TOKEN
    read -p "Masukkan ADMIN ID Telegram (pisah koma jika > 1): " ADMIN_IDS

    # Update config
    python3 - <<PYEOF
import json
with open('$DB_FILE', 'r') as f:
    db = json.load(f)

db['settings']['bot_token'] = '$BOT_TOKEN'
admin_list = [int(x.strip()) for x in '$ADMIN_IDS'.split(',') if x.strip()]
db['settings']['admin_ids'] = admin_list

# VPS Info
import subprocess, socket
try:
    ip = subprocess.check_output(['curl','-s','ifconfig.me'], timeout=5).decode().strip()
except:
    ip = ''
try:
    hostname = socket.gethostname()
except:
    hostname = ''

db['settings']['vps_info']['ip'] = ip
db['settings']['vps_info']['hostname'] = hostname
db['settings']['vps_info']['os'] = '$(lsb_release -ds 2>/dev/null || echo "Unknown")'

with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Config saved!")
PYEOF
}

install_panel_scripts() {
    echo -e "${CYAN}Installing panel scripts...${NC}"

    # Copy main panel script
    cp /tmp/zivpn_panel/panel.sh "$BIN_DIR/zivpn-panel"
    chmod +x "$BIN_DIR/zivpn-panel"

    # Copy bot
    cp /tmp/zivpn_panel/bot.py "$BOT_DIR/bot.py"
    chmod +x "$BOT_DIR/bot.py"

    # Copy account manager
    cp /tmp/zivpn_panel/account.sh "$BIN_DIR/zivpn-account"
    chmod +x "$BIN_DIR/zivpn-account"

    echo -e "${GREEN}Panel scripts installed!${NC}"
}

setup_cron() {
    # Auto delete expired accounts every hour
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/zivpn-account delete-expired >/dev/null 2>&1") | crontab -
    # Auto kill over-login every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/zivpn-account check-maxlogin >/dev/null 2>&1") | crontab -
    echo -e "${GREEN}Cron jobs set!${NC}"
}

setup_bot_service() {
    BOT_TOKEN=$(python3 -c "import json; d=json.load(open('$DB_FILE')); print(d['settings']['bot_token'])")
    cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=ZIVPN Telegram Bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $BOT_DIR/bot.py
Restart=always
RestartSec=5
Environment=BOT_TOKEN=$BOT_TOKEN
Environment=DB_FILE=$DB_FILE

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable zivpn-bot.service
    systemctl start zivpn-bot.service
}

print_success() {
    IP=$(curl -s ifconfig.me 2>/dev/null)
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ZIVPN PANEL BERHASIL TERPASANG   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo -e " IP VPS     : ${CYAN}$IP${NC}"
    echo -e " Panel CMD  : ${YELLOW}zivpn-panel${NC}"
    echo -e " Akun CMD   : ${YELLOW}zivpn-account${NC}"
    echo -e " Bot Status : ${GREEN}Running${NC}"
    echo ""
}

main() {
    check_root
    detect_os
    setup_panel_dirs
    install_dependencies
    install_zivpn_bin
    init_database
    collect_bot_config
    setup_cron
    setup_bot_service
    print_success
}

main
