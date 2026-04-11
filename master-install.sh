#!/bin/bash
# ============================================================
#   ZIVPN UDP PANEL - ALL IN ONE INSTALLER
#   Support: Debian 9/10/11/12 | Ubuntu 18/20/22/24
#   Usage  : bash <(curl -s https://raw.githubusercontent.com/chanelog/cek/main/master-install.sh)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/etc/zivpn-panel"
BIN_DIR="/usr/local/bin"
BOT_DIR="$PANEL_DIR/bot"
DB_FILE="$PANEL_DIR/database.json"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Harus dijalankan sebagai root!${NC}"; exit 1; }
}

detect_os() {
    . /etc/os-release
    OS=$ID; VER=$VERSION_ID
    echo -e "${GREEN}OS: $OS $VER${NC}"
    case $OS in debian|ubuntu) ;; *) echo -e "${RED}OS tidak didukung!${NC}"; exit 1 ;; esac
}

install_deps() {
    echo -e "${CYAN}[1/6] Installing dependencies...${NC}"
    apt-get update -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget jq openssl iptables python3 python3-pip \
        net-tools cron bc uuid-runtime ufw lsb-release >/dev/null 2>&1
    pip3 install "python-telegram-bot>=20.0" requests --quiet >/dev/null 2>&1
    echo -e "${GREEN}  ✓ Dependencies OK${NC}"
}

setup_dirs() {
    echo -e "${CYAN}[2/6] Setting up directories...${NC}"
    mkdir -p "$PANEL_DIR" "$BOT_DIR" "$PANEL_DIR/backup" "$PANEL_DIR/logs"
    echo -e "${GREEN}  ✓ Directories OK${NC}"
}

install_zivpn() {
    echo -e "${CYAN}[3/6] Installing ZIVPN binary...${NC}"
    if [ ! -f "$BIN_DIR/zivpn" ]; then
        wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" \
            -O "$BIN_DIR/zivpn" && chmod +x "$BIN_DIR/zivpn"
    fi
    mkdir -p /etc/zivpn
    [ ! -f /etc/zivpn/config.json ] && \
        wget -q "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" -O /etc/zivpn/config.json
    [ ! -f /etc/zivpn/zivpn.crt ] && \
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/C=US/ST=CA/L=LA/O=ZiVPN/CN=zivpn" \
            -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
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
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
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

write_scripts() {
    echo -e "${CYAN}[4/6] Writing panel scripts...${NC}"

    # ── ACCOUNT MANAGER ────────────────────────────────────────
    cat > "$BIN_DIR/zivpn-account" <<'ACCEOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
DB_FILE="/etc/zivpn-panel/database.json"
PANEL_DIR="/etc/zivpn-panel"
CONFIG_JSON="/etc/zivpn/config.json"

get_vps_ip() { curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'; }

update_zivpn_config() {
    python3 -c "
import json
with open('/etc/zivpn/config.json') as f:
    cfg = json.load(f)
with open('/etc/zivpn-panel/database.json') as f:
    db = json.load(f)
cfg['config'] = [a['password'] for a in db['accounts']] or ['zi']
with open('/etc/zivpn/config.json','w') as f:
    json.dump(cfg, f, indent=2)
"
    systemctl restart zivpn.service >/dev/null 2>&1
}

create_account() {
    local USERNAME="$1" PASSWORD="$2" DAYS="$3" MAXLOGIN="${4:-2}" CREATED_BY="${5:-admin}"
    [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$DAYS" ] && { echo "Usage: $0 create <user> <pass> <days> [maxlogin] [by]"; exit 1; }
    EXISTS=$(python3 -c "import json; db=json.load(open('/etc/zivpn-panel/database.json')); print('yes' if any(a['username']=='$USERNAME' for a in db['accounts']) else 'no')")
    [ "$EXISTS" = "yes" ] && { echo "ERROR: Username '$USERNAME' sudah ada!"; exit 1; }
    EXP_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d")
    UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    python3 -c "
import json
from datetime import datetime
db = json.load(open('/etc/zivpn-panel/database.json'))
db['accounts'].append({'uuid':'$UUID','username':'$USERNAME','password':'$PASSWORD',
    'days':$DAYS,'maxlogin':$MAXLOGIN,'created_at':datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'expired_at':'$EXP_DATE','created_by':'$CREATED_BY','active':True,'current_login':0})
json.dump(db, open('/etc/zivpn-panel/database.json','w'), indent=2)
"
    update_zivpn_config
    VPS_IP=$(get_vps_ip)
    echo -e "\n${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        AKUN BERHASIL DIBUAT           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo -e " Username   : ${CYAN}$USERNAME${NC}"
    echo -e " Password   : ${CYAN}$PASSWORD${NC}"
    echo -e " Max Login  : ${CYAN}$MAXLOGIN${NC}"
    echo -e " Expired    : ${YELLOW}$EXP_DATE${NC}"
    echo -e " IP VPS     : ${CYAN}$VPS_IP${NC}"
    echo -e " Port UDP   : ${CYAN}6000-19999${NC}"
    echo -e " Port Slow  : ${CYAN}5667${NC}\n"
}

delete_account() {
    local USERNAME="$1"
    [ -z "$USERNAME" ] && { echo "Usage: $0 delete <username>"; exit 1; }
    INFO=$(python3 -c "
import json
db = json.load(open('/etc/zivpn-panel/database.json'))
acc = next((a for a in db['accounts'] if a['username']=='$USERNAME'), None)
print(f'Username : {acc[\"username\"]}\nPassword : {acc[\"password\"]}\nExpired  : {acc[\"expired_at\"]}\nMaxLogin : {acc[\"maxlogin\"]}' if acc else 'NOT_FOUND')
")
    echo "$INFO" | grep -q "NOT_FOUND" && { echo "ERROR: Akun '$USERNAME' tidak ditemukan!"; exit 1; }
    echo -e "${YELLOW}Akun yang akan dihapus:${NC}\n$INFO\n"
    python3 -c "
import json
db = json.load(open('/etc/zivpn-panel/database.json'))
db['accounts'] = [a for a in db['accounts'] if a['username']!='$USERNAME']
json.dump(db, open('/etc/zivpn-panel/database.json','w'), indent=2)
"
    update_zivpn_config
    echo -e "${GREEN}Akun '$USERNAME' berhasil dihapus!${NC}"
}

delete_expired() {
    DELETED=$(python3 -c "
import json
from datetime import datetime
db = json.load(open('/etc/zivpn-panel/database.json'))
today = datetime.now().strftime('%Y-%m-%d')
exp = [a['username'] for a in db['accounts'] if a['expired_at'] < today]
db['accounts'] = [a for a in db['accounts'] if a['expired_at'] >= today]
json.dump(db, open('/etc/zivpn-panel/database.json','w'), indent=2)
print('\n'.join(exp))
")
    [ -n "$DELETED" ] && { update_zivpn_config; echo -e "${GREEN}Dihapus:\n$DELETED${NC}"; } || echo -e "${YELLOW}Tidak ada akun expired.${NC}"
}

check_maxlogin() {
    python3 -c "
import json, subprocess
db = json.load(open('/etc/zivpn-panel/database.json'))
for acc in db['accounts']:
    uname, ml = acc['username'], acc.get('maxlogin',2)
    try:
        cur = int(subprocess.check_output(f'ss -tnp 2>/dev/null | grep -c {uname} || echo 0', shell=True).decode().strip())
    except: cur = 0
    if cur > ml:
        subprocess.run(f'pkill -u {uname} 2>/dev/null || true', shell=True)
        print(f'[KILL] {uname}: {cur} login (max:{ml})')
"
}

list_accounts() {
    python3 -c "
import json
from datetime import datetime
db = json.load(open('/etc/zivpn-panel/database.json'))
today = datetime.now().strftime('%Y-%m-%d')
accs = db['accounts']
if not accs:
    print('Belum ada akun.')
else:
    print(f\"{'No':<4} {'Username':<15} {'Exp':<12} {'Days':<6} {'MaxLogin':<9} {'Status':<8}\")
    print('-'*60)
    for i,a in enumerate(accs,1):
        st = 'AKTIF' if a['expired_at'] >= today else 'EXPIRED'
        print(f\"{i:<4} {a['username']:<15} {a['expired_at']:<12} {a['days']:<6} {a['maxlogin']:<9} {st:<8}\")
"
}

backup_database() {
    TS=$(date +"%Y%m%d_%H%M%S")
    BF="$PANEL_DIR/backup/backup_$TS.json"
    cp "$DB_FILE" "$BF" && echo "$BF"
}

restore_database() {
    [ ! -f "$1" ] && { echo "ERROR: File tidak ditemukan!"; exit 1; }
    cp "$1" "$DB_FILE"
    update_zivpn_config
    echo -e "${GREEN}Database berhasil di-restore!${NC}"
}

case "$1" in
    create)         create_account "$2" "$3" "$4" "$5" "$6" ;;
    delete)         delete_account "$2" ;;
    delete-expired) delete_expired ;;
    check-maxlogin) check_maxlogin ;;
    list)           list_accounts ;;
    backup)         backup_database ;;
    restore)        restore_database "$2" ;;
    *) echo "Usage: $0 {create|delete|delete-expired|check-maxlogin|list|backup|restore}" ;;
esac
ACCEOF
    chmod +x "$BIN_DIR/zivpn-account"

    # ── PANEL MENU ─────────────────────────────────────────────
    cat > "$BIN_DIR/zivpn-panel" <<'PANEOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
DB_FILE="/etc/zivpn-panel/database.json"
PANEL_DIR="/etc/zivpn-panel"
get_ip()     { curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'; }
acct_count() { python3 -c "import json; print(len(json.load(open('$DB_FILE'))['accounts']))" 2>/dev/null || echo 0; }
exp_count()  { python3 -c "import json,datetime; db=json.load(open('$DB_FILE')); t=datetime.datetime.now().strftime('%Y-%m-%d'); print(sum(1 for a in db['accounts'] if a['expired_at']<t))" 2>/dev/null || echo 0; }
srv_count()  { python3 -c "import json; print(len(json.load(open('$DB_FILE'))['servers']))" 2>/dev/null || echo 0; }
zi_stat()    { systemctl is-active zivpn.service 2>/dev/null | grep -q active && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}"; }
bot_stat()   { systemctl is-active zivpn-bot.service 2>/dev/null | grep -q active && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}"; }

header() {
    clear
    IP=$(get_ip); TOT=$(acct_count); EXP=$(exp_count); SRV=$(srv_count)
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         ZIVPN UDP PANEL - FULL POWER             ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC}  IP    : %-18s ZIVPN : %-11s${CYAN}║${NC}\n" "$IP" "$(zi_stat|sed 's/\x1B\[[0-9;]*m//g')"
    printf "${CYAN}║${NC}  Akun  : %-5s  Exp: %-5s  Server: %-4s        ${CYAN}║${NC}\n" "$TOT" "$EXP" "$SRV"
    printf "${CYAN}║${NC}  Bot   : %-40s${CYAN}║${NC}\n" "$(bot_stat|sed 's/\x1B\[[0-9;]*m//g')"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

menu_utama() {
    header
    echo -e "${WHITE}  ╔═══════════════════╦═══════════════════╗${NC}"
    echo -e "${WHITE}  ║  [1] Create Akun  ║  [2] Hapus Akun   ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╬═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [3] Info Akun    ║  [4] Hapus Expired║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╬═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [5] Backup/Resto ║  [6] Kelola Server║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╬═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [7] Install Bin  ║  [8] Bot Telegram ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╬═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [9] Pengaturan   ║  [0] Keluar       ║${NC}"
    echo -e "${WHITE}  ╚═══════════════════╩═══════════════════╝${NC}"
    echo ""
    read -p "  Pilih menu [0-9]: " C
    case "$C" in
        1) m_create;;  2) m_hapus;;   3) m_info;;
        4) m_expired;; 5) m_backup;;  6) m_server;;
        7) m_bin;;     8) m_bot;;     9) m_setting;;
        0) exit 0;;    *) echo -e "${RED}Tidak valid!${NC}"; sleep 1; menu_utama;;
    esac
}

m_create() {
    header
    echo -e "${CYAN}  ╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║        CREATE AKUN BARU          ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════╝${NC}\n"
    read -p "  Username     : " U
    read -p "  Password     : " P
    read -p "  Durasi (hari): " D
    read -p "  Max Login    : " M; M=${M:-2}
    zivpn-account create "$U" "$P" "$D" "$M" "admin"
    read -p "  Tekan Enter..." _; menu_utama
}

m_hapus() {
    header
    echo -e "${RED}  ╔══════════════════════════════════╗${NC}"
    echo -e "${RED}  ║          HAPUS AKUN              ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════╝${NC}\n"
    zivpn-account list; echo ""
    read -p "  Username yang dihapus: " U
    [ -n "$U" ] && zivpn-account delete "$U"
    read -p "  Tekan Enter..." _; menu_utama
}

m_info() {
    header
    echo -e "${YELLOW}  ╔══════════════════════════════════╗${NC}"
    echo -e "${YELLOW}  ║         INFO SEMUA AKUN          ║${NC}"
    echo -e "${YELLOW}  ╚══════════════════════════════════╝${NC}\n"
    zivpn-account list
    read -p "  Tekan Enter..." _; menu_utama
}

m_expired() {
    header
    echo -e "${RED}  ╔══════════════════════════════════╗${NC}"
    echo -e "${RED}  ║       HAPUS AKUN EXPIRED         ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════╝${NC}\n"
    zivpn-account delete-expired
    read -p "  Tekan Enter..." _; menu_utama
}

m_backup() {
    header
    echo -e "${BLUE}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${BLUE}  ║         BACKUP / RESTORE          ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [1] Backup       ║  [2] Restore  ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [3] Backup+Kirim ke Telegram     ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${BLUE}  ║  [0] Kembali                      ║${NC}"
    echo -e "${BLUE}  ╚═══════════════════════════════════╝${NC}\n"
    read -p "  Pilih: " C
    case "$C" in
        1) BF=$(zivpn-account backup); echo -e "${GREEN}Backup: $BF${NC}" ;;
        2) ls "$PANEL_DIR/backup/"; echo ""; read -p "  Path backup: " BF; zivpn-account restore "$BF" ;;
        3) BF=$(zivpn-account backup)
           TOKEN=$(python3 -c "import json; print(json.load(open('$DB_FILE'))['settings']['bot_token'])" 2>/dev/null)
           ADMIN=$(python3 -c "import json; d=json.load(open('$DB_FILE')); print(d['settings']['admin_ids'][0])" 2>/dev/null)
           [ -n "$TOKEN" ] && [ -n "$ADMIN" ] && \
               curl -s -F "document=@$BF" -F "chat_id=$ADMIN" -F "caption=ZIVPN Backup $(date)" \
               "https://api.telegram.org/bot$TOKEN/sendDocument" >/dev/null && \
               echo -e "${GREEN}Terkirim ke Telegram!${NC}" ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter..." _; menu_utama
}

m_server() {
    header
    echo -e "${CYAN}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║         KELOLA SERVER (VPS)       ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [1] Tambah       ║  [2] List VPS ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [3] Hapus Server ║  [0] Kembali  ║${NC}"
    echo -e "${CYAN}  ╚═══════════════════════════════════╝${NC}\n"
    read -p "  Pilih: " C
    case "$C" in
        1) read -p "  Nama : " SN; read -p "  IP   : " SI; read -p "  Port : " SP
           python3 -c "
import json,uuid
db=json.load(open('$DB_FILE'))
db['servers'].append({'id':str(uuid.uuid4())[:8],'name':'$SN','ip':'$SI','port':'$SP','active':True})
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Server ditambahkan!')
" ;;
        2) python3 -c "
import json
db=json.load(open('$DB_FILE'))
[print(f\"[{s['id']}] {s['name']} - {s['ip']}:{s['port']}\") for s in db['servers']] or print('Belum ada server.')
" ;;
        3) python3 -c "import json; [print(f\"[{s['id']}] {s['name']}\") for s in json.load(open('$DB_FILE'))['servers']]"
           read -p "  ID server: " SID
           python3 -c "
import json
db=json.load(open('$DB_FILE'))
db['servers']=[s for s in db['servers'] if s['id']!='$SID']
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Server dihapus!')
" ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter..." _; m_server
}

m_bin() {
    header
    echo -e "${CYAN}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║     INSTALL / REINSTALL BIN       ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [1] Reinstall    ║  [2] Restart  ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [3] Stop         ║  [4] Start    ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║  [0] Kembali                      ║${NC}"
    echo -e "${CYAN}  ╚═══════════════════════════════════╝${NC}\n"
    echo -e "  Status: $(zi_stat)"
    read -p "  Pilih: " C
    case "$C" in
        1) systemctl stop zivpn.service 2>/dev/null; rm -f /usr/local/bin/zivpn
           wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O /usr/local/bin/zivpn
           chmod +x /usr/local/bin/zivpn; systemctl start zivpn.service; echo -e "${GREEN}Reinstall OK!${NC}" ;;
        2) systemctl restart zivpn.service; echo -e "${GREEN}Restarted!${NC}" ;;
        3) systemctl stop zivpn.service; echo -e "${YELLOW}Stopped!${NC}" ;;
        4) systemctl start zivpn.service; echo -e "${GREEN}Started!${NC}" ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter..." _; menu_utama
}

m_bot() {
    header
    echo -e "${BLUE}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${BLUE}  ║        KELOLA BOT TELEGRAM        ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [1] Start        ║  [2] Stop     ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [3] Restart      ║  [4] Log Bot  ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${BLUE}  ║  [0] Kembali                      ║${NC}"
    echo -e "${BLUE}  ╚═══════════════════════════════════╝${NC}\n"
    echo -e "  Status: $(bot_stat)"
    read -p "  Pilih: " C
    case "$C" in
        1) systemctl start zivpn-bot.service; echo -e "${GREEN}Started!${NC}" ;;
        2) systemctl stop zivpn-bot.service; echo -e "${YELLOW}Stopped!${NC}" ;;
        3) systemctl restart zivpn-bot.service; echo -e "${GREEN}Restarted!${NC}" ;;
        4) journalctl -u zivpn-bot.service -n 50 --no-pager ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter..." _; menu_utama
}

m_setting() {
    header
    echo -e "${WHITE}  ╔═══════════════════════════════════════╗${NC}"
    echo -e "${WHITE}  ║            PENGATURAN PANEL           ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╦═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [1] Tambah Resell║  [2] Hapus Resell ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╩═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [3] Upload QRIS  ║  [4] Ubah Harga   ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [5] Info VPS     ║  [6] Ganti Token  ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [0] Kembali                          ║${NC}"
    echo -e "${WHITE}  ╚═══════════════════════════════════════╝${NC}\n"
    read -p "  Pilih: " C
    case "$C" in
        1) read -p "  Username : " RU; read -p "  TG ID    : " RT; read -p "  Max Akun : " RM; RM=${RM:-10}
           python3 -c "
import json,uuid
from datetime import datetime
db=json.load(open('$DB_FILE'))
db['resellers'].append({'id':str(uuid.uuid4())[:8],'username':'$RU','telegram_id':int('$RT'),'max_accounts':$RM,'joined_at':datetime.now().strftime('%Y-%m-%d')})
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Reseller ditambahkan!')
" ;;
        2) python3 -c "import json; [print(f\"  {r['username']} (ID:{r['telegram_id']})\") for r in json.load(open('$DB_FILE'))['resellers']]"
           read -p "  Username: " RU
           python3 -c "
import json
db=json.load(open('$DB_FILE'))
db['resellers']=[r for r in db['resellers'] if r['username']!='$RU']
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Reseller dihapus!')
" ;;
        3) read -p "  URL QRIS: " QU
           python3 -c "
import json
db=json.load(open('$DB_FILE'))
db['settings']['qris_photo']='$QU'
json.dump(db,open('$DB_FILE','w'),indent=2)
print('QRIS updated!')
" ;;
        4) read -p "  Harga 15 Hari: " H15; read -p "  Harga 30 Hari: " H30
           python3 -c "
import json
db=json.load(open('$DB_FILE'))
if '$H15': db['settings']['price_15days']=int('$H15')
if '$H30': db['settings']['price_30days']=int('$H30')
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Harga updated!')
" ;;
        5) IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
           RAM=$(free -h|awk '/^Mem:/{print $2}'); CPU=$(nproc)
           OS=$(lsb_release -ds 2>/dev/null); UP=$(uptime -p); DISK=$(df -h /|awk 'NR==2{print $3"/"$2}')
           echo -e "\n${CYAN}  IP: $IP | OS: $OS\n  RAM: $RAM | CPU: $CPU Core | Disk: $DISK\n  $UP${NC}" ;;
        6) read -p "  Token baru: " NT
           python3 -c "
import json
db=json.load(open('$DB_FILE'))
db['settings']['bot_token']='$NT'
json.dump(db,open('$DB_FILE','w'),indent=2)
print('Token updated!')
"
           sed -i "s|^Environment=BOT_TOKEN=.*|Environment=BOT_TOKEN=$NT|" /etc/systemd/system/zivpn-bot.service
           systemctl daemon-reload; systemctl restart zivpn-bot.service
           echo -e "${GREEN}Token diupdate & bot direstart!${NC}" ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter..." _; m_setting
}

menu_utama
PANEOF
    chmod +x "$BIN_DIR/zivpn-panel"
    echo -e "${GREEN}  ✓ Scripts OK${NC}"
}

write_bot() {
    cat > "$BOT_DIR/bot.py" <<'BOTEOF'
#!/usr/bin/env python3
import os, json, subprocess, logging, uuid
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler)
from telegram.constants import ParseMode

logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=logging.INFO)
DB_FILE = os.environ.get("DB_FILE", "/etc/zivpn-panel/database.json")
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")

(AWAIT_USER, AWAIT_PASS, AWAIT_DAYS, AWAIT_ML,
 AWAIT_SRV_NAME, AWAIT_SRV_IP, AWAIT_SRV_PORT,
 AWAIT_RS_USER, AWAIT_RS_ID, AWAIT_RS_MAX,
 AWAIT_QRIS, AWAIT_H15, AWAIT_H30) = range(13)

def load_db():
    with open(DB_FILE) as f: return json.load(f)
def save_db(db):
    with open(DB_FILE, 'w') as f: json.dump(db, f, indent=2)
def is_admin(uid): return uid in load_db()['settings']['admin_ids']
def is_reseller(uid): return any(r['telegram_id']==uid for r in load_db()['resellers'])
def get_reseller(uid): return next((r for r in load_db()['resellers'] if r['telegram_id']==uid), None)
def back_btn(): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu Utama", callback_data="main_menu")]])

def main_kb(uid):
    if is_admin(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("👤 Create Akun",callback_data="create"),InlineKeyboardButton("🗑 Hapus Akun",callback_data="hapus")],
            [InlineKeyboardButton("📋 Info Akun",callback_data="info"),InlineKeyboardButton("⏰ Hapus Expired",callback_data="expired")],
            [InlineKeyboardButton("🖥 Server",callback_data="server"),InlineKeyboardButton("💾 Backup",callback_data="backup")],
            [InlineKeyboardButton("🏪 Toko",callback_data="toko"),InlineKeyboardButton("⚙️ Pengaturan",callback_data="setting")],
            [InlineKeyboardButton("📊 Info VPS",callback_data="infovps"),InlineKeyboardButton("🤖 Status",callback_data="status")],
        ])
    elif is_reseller(uid):
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("👤 Create Akun",callback_data="create"),InlineKeyboardButton("🗑 Hapus Akun",callback_data="hapus")],
            [InlineKeyboardButton("📋 Akun Saya",callback_data="info_rs"),InlineKeyboardButton("🏪 Toko",callback_data="toko")],
        ])
    else:
        return InlineKeyboardMarkup([
            [InlineKeyboardButton("🏪 Beli Akun UDP",callback_data="toko"),InlineKeyboardButton("📖 Cara Beli",callback_data="cara")],
        ])

async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid=update.effective_user.id; name=update.effective_user.first_name
    role="👑 ADMIN" if is_admin(uid) else ("💼 RESELLER" if is_reseller(uid) else "👤 User")
    await update.message.reply_text(
        f"╔══════════════════════════╗\n║   🌐 ZIVPN UDP PANEL     ║\n╚══════════════════════════╝\n\nHalo *{name}*!\nRole: *{role}*\n\nPilih menu:",
        reply_markup=main_kb(uid), parse_mode=ParseMode.MARKDOWN)

async def cb(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q=update.callback_query; await q.answer()
    uid=q.from_user.id; d=q.data

    if d=="main_menu":
        await q.edit_message_text("🌐 *ZIVPN UDP PANEL*\n\nPilih menu:", reply_markup=main_kb(uid), parse_mode=ParseMode.MARKDOWN); return

    if d=="create":
        if not is_admin(uid) and not is_reseller(uid):
            await q.edit_message_text("⛔ Akses ditolak!"); return
        if is_reseller(uid):
            rs=get_reseller(uid); db=load_db()
            my=[a for a in db['accounts'] if a.get('created_by_id')==uid]
            if len(my)>=rs['max_accounts']:
                await q.edit_message_text(f"⛔ Batas max akun ({rs['max_accounts']}) tercapai!",reply_markup=back_btn()); return
        ctx.user_data.clear()
        await q.edit_message_text("👤 *CREATE AKUN*\n\nMasukkan *username*:\n_(/batal untuk membatalkan)_",parse_mode=ParseMode.MARKDOWN)
        return AWAIT_USER

    if d=="hapus":
        if not is_admin(uid) and not is_reseller(uid):
            await q.edit_message_text("⛔ Akses ditolak!"); return
        db=load_db()
        accs=[a for a in db['accounts'] if a.get('created_by_id')==uid] if is_reseller(uid) else db['accounts']
        if not accs: await q.edit_message_text("📭 Tidak ada akun.",reply_markup=back_btn()); return
        kb=[[InlineKeyboardButton(f"🗑 {a['username']} | {a['expired_at']}",callback_data=f"del:{a['username']}")] for a in accs]
        kb.append([InlineKeyboardButton("🔙 Kembali",callback_data="main_menu")])
        await q.edit_message_text("🗑 *Pilih akun:*",reply_markup=InlineKeyboardMarkup(kb),parse_mode=ParseMode.MARKDOWN); return

    if d.startswith("del:"):
        uname=d[4:]; db=load_db()
        acc=next((a for a in db['accounts'] if a['username']==uname),None)
        if not acc: await q.edit_message_text("❌ Akun tidak ditemukan!",reply_markup=back_btn()); return
        kb=InlineKeyboardMarkup([[InlineKeyboardButton("✅ Ya Hapus",callback_data=f"confirm:{uname}"),InlineKeyboardButton("❌ Batal",callback_data="hapus")]])
        await q.edit_message_text(f"⚠️ *KONFIRMASI HAPUS*\n\n👤 `{acc['username']}`\n🔑 `{acc['password']}`\n📅 `{acc['expired_at']}`",reply_markup=kb,parse_mode=ParseMode.MARKDOWN); return

    if d.startswith("confirm:"):
        uname=d[8:]; subprocess.run(['zivpn-account','delete',uname],capture_output=True)
        await q.edit_message_text(f"✅ Akun *{uname}* dihapus!",reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="info":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        db=load_db(); today=datetime.now().strftime("%Y-%m-%d")
        msg="📋 *DAFTAR AKUN*\n"+"═"*28+"\n"
        for i,a in enumerate(db['accounts'],1):
            st="✅" if a['expired_at']>=today else "❌"
            msg+=f"{i}. {st} `{a['username']}` | {a['expired_at']} | Max:{a['maxlogin']}\n"
        await q.edit_message_text(msg or "📭 Belum ada akun.",reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="info_rs":
        db=load_db(); today=datetime.now().strftime("%Y-%m-%d")
        accs=[a for a in db['accounts'] if a.get('created_by_id')==uid]; rs=get_reseller(uid)
        msg="📋 *AKUN KAMU*\n"+"═"*28+"\n"
        for i,a in enumerate(accs,1):
            st="✅" if a['expired_at']>=today else "❌"
            msg+=f"{i}. {st} `{a['username']}` | {a['expired_at']}\n"
        msg+=f"\n📊 {len(accs)}/{rs['max_accounts']} akun"
        await q.edit_message_text(msg,reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="expired":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        db=load_db(); today=datetime.now().strftime("%Y-%m-%d")
        exp=[a['username'] for a in db['accounts'] if a['expired_at']<today]
        if not exp: await q.edit_message_text("✅ Tidak ada akun expired.",reply_markup=back_btn()); return
        subprocess.run(['zivpn-account','delete-expired'],capture_output=True)
        await q.edit_message_text(f"🗑 *{len(exp)} akun dihapus:*\n"+"\n".join([f"• `{u}`" for u in exp]),reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="server":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        kb=InlineKeyboardMarkup([[InlineKeyboardButton("➕ Tambah",callback_data="srv_add"),InlineKeyboardButton("📋 List",callback_data="srv_list")],[InlineKeyboardButton("🔙 Kembali",callback_data="main_menu")]])
        await q.edit_message_text("🖥 *KELOLA SERVER*",reply_markup=kb,parse_mode=ParseMode.MARKDOWN); return

    if d=="srv_add":
        await q.edit_message_text("🖥 Masukkan *nama server*:",parse_mode=ParseMode.MARKDOWN); return AWAIT_SRV_NAME

    if d=="srv_list":
        db=load_db(); msg="🖥 *DAFTAR SERVER*\n"+"═"*28+"\n"; kb=[]
        for s in db['servers']:
            msg+=f"• *{s['name']}* — `{s['ip']}:{s['port']}`\n"
            kb.append([InlineKeyboardButton(f"🗑 Hapus {s['name']}",callback_data=f"srv_del:{s['id']}")])
        kb.append([InlineKeyboardButton("🔙 Kembali",callback_data="server")])
        await q.edit_message_text(msg or "📭 Belum ada server.",reply_markup=InlineKeyboardMarkup(kb),parse_mode=ParseMode.MARKDOWN); return

    if d.startswith("srv_del:"):
        sid=d[8:]; db=load_db(); db['servers']=[s for s in db['servers'] if s['id']!=sid]; save_db(db)
        await q.edit_message_text("✅ Server dihapus!",reply_markup=back_btn()); return

    if d=="backup":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        result=subprocess.run(['zivpn-account','backup'],capture_output=True,text=True); bf=result.stdout.strip()
        if os.path.exists(bf):
            await q.message.reply_document(document=open(bf,'rb'),caption=f"🗄 ZIVPN Backup\n📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            await q.edit_message_text("✅ Backup terkirim!",reply_markup=back_btn())
        else:
            await q.edit_message_text("❌ Gagal backup!",reply_markup=back_btn()); return

    if d=="toko":
        db=load_db(); s=db['settings']; p15=s.get('price_15days',6000); p30=s.get('price_30days',10000)
        srvs="\n".join([f"• {sv['name']} — `{sv['ip']}`" for sv in db['servers']]) or "• Belum ada server"
        kb=InlineKeyboardMarkup([[InlineKeyboardButton(f"🛒 15 Hari — Rp {p15:,}",callback_data="beli:15"),InlineKeyboardButton(f"🛒 30 Hari — Rp {p30:,}",callback_data="beli:30")],[InlineKeyboardButton("🔙 Kembali",callback_data="main_menu")]])
        await q.edit_message_text(f"🏪 *TOKO UDP ZIVPN*\n{'═'*28}\n⏱ 15 Hari — Rp {p15:,}\n⏱ 30 Hari — Rp {p30:,}\n\n🌐 *Server:*\n{srvs}\n\n🔌 Port: `6000-19999`\n💳 Bayar via QRIS",reply_markup=kb,parse_mode=ParseMode.MARKDOWN); return

    if d.startswith("beli:"):
        days=int(d[5:]); db=load_db(); price=db['settings'].get(f'price_{days}days',6000); qris=db['settings'].get('qris_photo','')
        msg=f"💳 *PEMBAYARAN QRIS*\n{'═'*28}\n📦 Paket: *{days} Hari*\n💰 Harga: *Rp {price:,}*\n\nScan QR lalu kirim bukti ke admin."
        kb=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali",callback_data="toko")]])
        if qris:
            await q.message.reply_photo(photo=qris,caption=msg,parse_mode=ParseMode.MARKDOWN,reply_markup=kb); await q.delete_message()
        else:
            await q.edit_message_text(msg+"\n\n_QR belum dikonfigurasi._",reply_markup=kb,parse_mode=ParseMode.MARKDOWN)
        return

    if d=="cara":
        await q.edit_message_text("📖 *CARA BELI*\n1️⃣ Pilih paket\n2️⃣ Scan QRIS & bayar\n3️⃣ Screenshot bukti\n4️⃣ Kirim ke admin\n5️⃣ Akun dikirim segera",reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="setting":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        kb=InlineKeyboardMarkup([[InlineKeyboardButton("➕ Tambah Reseller",callback_data="rs_add"),InlineKeyboardButton("📋 List Reseller",callback_data="rs_list")],[InlineKeyboardButton("🖼 Upload QRIS",callback_data="set_qris"),InlineKeyboardButton("💰 Ubah Harga",callback_data="set_harga")],[InlineKeyboardButton("🔙 Kembali",callback_data="main_menu")]])
        await q.edit_message_text("⚙️ *PENGATURAN*",reply_markup=kb,parse_mode=ParseMode.MARKDOWN); return

    if d=="rs_add":
        await q.edit_message_text("👤 Masukkan *username reseller*:",parse_mode=ParseMode.MARKDOWN); return AWAIT_RS_USER

    if d=="rs_list":
        db=load_db(); msg="💼 *DAFTAR RESELLER*\n"+"═"*28+"\n"; kb=[]
        for r in db['resellers']:
            msg+=f"• *{r['username']}* (ID:`{r['telegram_id']}`) Max:{r['max_accounts']}\n"
            kb.append([InlineKeyboardButton(f"🗑 Hapus {r['username']}",callback_data=f"rs_del:{r['id']}")])
        kb.append([InlineKeyboardButton("🔙 Kembali",callback_data="setting")])
        await q.edit_message_text(msg or "📭 Belum ada reseller.",reply_markup=InlineKeyboardMarkup(kb),parse_mode=ParseMode.MARKDOWN); return

    if d.startswith("rs_del:"):
        rid=d[7:]; db=load_db(); db['resellers']=[r for r in db['resellers'] if r['id']!=rid]; save_db(db)
        await q.edit_message_text("✅ Reseller dihapus!",reply_markup=back_btn()); return

    if d=="set_qris":
        await q.edit_message_text("🖼 Kirim *URL gambar QRIS*:",parse_mode=ParseMode.MARKDOWN); return AWAIT_QRIS

    if d=="set_harga":
        db=load_db(); s=db['settings']
        await q.edit_message_text(f"💰 Harga saat ini:\n• 15 Hari: Rp {s.get('price_15days',6000):,}\n• 30 Hari: Rp {s.get('price_30days',10000):,}\n\nMasukkan harga *15 hari* baru:",parse_mode=ParseMode.MARKDOWN); return AWAIT_H15

    if d=="infovps":
        try: ip=subprocess.check_output(['curl','-s','--connect-timeout','5','ifconfig.me'],timeout=6).decode().strip()
        except: ip='N/A'
        ram=subprocess.check_output("free -h|awk '/^Mem:/{print $2\"/\"$3}'",shell=True).decode().strip()
        cpu=subprocess.check_output("nproc",shell=True).decode().strip()
        up=subprocess.check_output("uptime -p",shell=True).decode().strip()
        os_=subprocess.check_output("lsb_release -ds 2>/dev/null||grep PRETTY_NAME /etc/os-release|cut -d'\"' -f2",shell=True).decode().strip()
        disk=subprocess.check_output("df -h /|awk 'NR==2{print $3\"/\"$2}'",shell=True).decode().strip()
        await q.edit_message_text(f"📊 *INFO VPS*\n{'═'*28}\n🌐 IP: `{ip}`\n💻 OS: `{os_}`\n🧠 RAM: `{ram}`\n⚙️ CPU: `{cpu} Core`\n💽 Disk: `{disk}`\n⏱ {up}",reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

    if d=="status":
        if not is_admin(uid): await q.edit_message_text("⛔ Akses ditolak!"); return
        db=load_db(); today=datetime.now().strftime("%Y-%m-%d")
        total=len(db['accounts']); exp=sum(1 for a in db['accounts'] if a['expired_at']<today)
        await q.edit_message_text(f"🤖 *STATUS PANEL*\n{'═'*28}\n👤 Total: `{total}`\n✅ Aktif: `{total-exp}`\n❌ Expired: `{exp}`\n🖥 Server: `{len(db['servers'])}`\n💼 Reseller: `{len(db['resellers'])}`",reply_markup=back_btn(),parse_mode=ParseMode.MARKDOWN); return

async def recv_user(u,ctx):
    if u.message.text=='/batal': await u.message.reply_text("❌ Dibatalkan."); return ConversationHandler.END
    ctx.user_data['u']=u.message.text.strip()
    await u.message.reply_text("🔑 Masukkan *password*:",parse_mode=ParseMode.MARKDOWN); return AWAIT_PASS

async def recv_pass(u,ctx):
    ctx.user_data['p']=u.message.text.strip()
    await u.message.reply_text("📅 Masukkan *durasi* (hari):",parse_mode=ParseMode.MARKDOWN); return AWAIT_DAYS

async def recv_days(u,ctx):
    try: ctx.user_data['d']=int(u.message.text.strip())
    except: await u.message.reply_text("❌ Harus angka!"); return AWAIT_DAYS
    await u.message.reply_text("🔒 Max login (default 2):",parse_mode=ParseMode.MARKDOWN); return AWAIT_ML

async def recv_ml(u,ctx):
    try: ml=int(u.message.text.strip())
    except: ml=2
    uid=u.effective_user.id; un,pw,days=ctx.user_data['u'],ctx.user_data['p'],ctx.user_data['d']
    subprocess.run(['zivpn-account','create',un,pw,str(days),str(ml),str(uid)],capture_output=True)
    db=load_db()
    for a in db['accounts']:
        if a['username']==un: a['created_by_id']=uid
    save_db(db)
    exp=(datetime.now()+timedelta(days=days)).strftime("%Y-%m-%d")
    srvs="\n".join([f"• `{s['ip']}:{s['port']}`" for s in db['servers']]) or "• Belum ada server"
    await u.message.reply_text(f"✅ *AKUN DIBUAT!*\n{'═'*28}\n👤 `{un}`\n🔑 `{pw}`\n📅 Exp: `{exp}`\n🔒 Max: `{ml}`\n\n🌐 *Server:*\n{srvs}\n🔌 Port: `6000-19999`",parse_mode=ParseMode.MARKDOWN,reply_markup=back_btn())
    return ConversationHandler.END

async def recv_srv_name(u,ctx):
    ctx.user_data['sn']=u.message.text.strip(); await u.message.reply_text("🌐 IP server:"); return AWAIT_SRV_IP

async def recv_srv_ip(u,ctx):
    ctx.user_data['si']=u.message.text.strip(); await u.message.reply_text("🔌 Port UDP (contoh: 6000-19999):"); return AWAIT_SRV_PORT

async def recv_srv_port(u,ctx):
    db=load_db(); db['servers'].append({"id":str(uuid.uuid4())[:8],"name":ctx.user_data['sn'],"ip":ctx.user_data['si'],"port":u.message.text.strip(),"active":True}); save_db(db)
    await u.message.reply_text(f"✅ Server *{ctx.user_data['sn']}* ditambahkan!",parse_mode=ParseMode.MARKDOWN,reply_markup=back_btn()); return ConversationHandler.END

async def recv_rs_user(u,ctx):
    ctx.user_data['ru']=u.message.text.strip(); await u.message.reply_text("🆔 Telegram ID reseller:"); return AWAIT_RS_ID

async def recv_rs_id(u,ctx):
    try: ctx.user_data['rt']=int(u.message.text.strip())
    except: await u.message.reply_text("❌ ID harus angka!"); return AWAIT_RS_ID
    await u.message.reply_text("📦 Max akun yang bisa dibuat:"); return AWAIT_RS_MAX

async def recv_rs_max(u,ctx):
    try: mx=int(u.message.text.strip())
    except: mx=10
    db=load_db(); db['resellers'].append({"id":str(uuid.uuid4())[:8],"username":ctx.user_data['ru'],"telegram_id":ctx.user_data['rt'],"max_accounts":mx,"joined_at":datetime.now().strftime("%Y-%m-%d")}); save_db(db)
    await u.message.reply_text(f"✅ Reseller *{ctx.user_data['ru']}* ditambahkan!",parse_mode=ParseMode.MARKDOWN,reply_markup=back_btn()); return ConversationHandler.END

async def recv_qris(u,ctx):
    db=load_db(); db['settings']['qris_photo']=u.message.text.strip(); save_db(db)
    await u.message.reply_text("✅ QRIS diupdate!",reply_markup=back_btn()); return ConversationHandler.END

async def recv_h15(u,ctx):
    try: ctx.user_data['h15']=int(u.message.text.strip())
    except: await u.message.reply_text("❌ Angka!"); return AWAIT_H15
    await u.message.reply_text("Masukkan harga *30 hari* baru:",parse_mode=ParseMode.MARKDOWN); return AWAIT_H30

async def recv_h30(u,ctx):
    try: h30=int(u.message.text.strip())
    except: await u.message.reply_text("❌ Angka!"); return AWAIT_H30
    db=load_db(); db['settings']['price_15days']=ctx.user_data['h15']; db['settings']['price_30days']=h30; save_db(db)
    await u.message.reply_text(f"✅ Harga diupdate!\n• 15 Hari: Rp {ctx.user_data['h15']:,}\n• 30 Hari: Rp {h30:,}",reply_markup=back_btn()); return ConversationHandler.END

async def cancel(u,ctx):
    await u.message.reply_text("❌ Dibatalkan."); return ConversationHandler.END

def main():
    db=load_db(); token=BOT_TOKEN or db['settings'].get('bot_token','')
    if not token: print("ERROR: Token tidak ditemukan!"); return
    app=Application.builder().token(token).build()
    conv=ConversationHandler(
        entry_points=[CallbackQueryHandler(cb)],
        states={
            AWAIT_USER:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_user)],
            AWAIT_PASS:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_pass)],
            AWAIT_DAYS:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_days)],
            AWAIT_ML:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_ml)],
            AWAIT_SRV_NAME:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_srv_name)],
            AWAIT_SRV_IP:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_srv_ip)],
            AWAIT_SRV_PORT:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_srv_port)],
            AWAIT_RS_USER:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_rs_user)],
            AWAIT_RS_ID:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_rs_id)],
            AWAIT_RS_MAX:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_rs_max)],
            AWAIT_QRIS:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_qris)],
            AWAIT_H15:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_h15)],
            AWAIT_H30:[MessageHandler(filters.TEXT&~filters.COMMAND,recv_h30)],
        },
        fallbacks=[CommandHandler("batal",cancel),CallbackQueryHandler(cb,pattern="^main_menu$")]
    )
    app.add_handler(CommandHandler("start",start))
    app.add_handler(conv)
    print("🤖 ZIVPN Bot running...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__=="__main__":
    main()
BOTEOF
    chmod +x "$BOT_DIR/bot.py"
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
    echo -e "${WHITE}  1. Buka @BotFather di Telegram${NC}"
    echo -e "${WHITE}  2. Ketik /newbot lalu ikuti instruksi${NC}"
    echo -e "${WHITE}  3. Copy TOKEN yang diberikan${NC}"
    echo ""
    read -p "  Bot TOKEN   : " BOT_TOKEN
    echo -e "${WHITE}  Cek Telegram ID kamu di @userinfobot${NC}"
    read -p "  Admin ID(s) : " ADMIN_IDS

    python3 - <<PYEOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['settings']['bot_token'] = '$BOT_TOKEN'
db['settings']['admin_ids'] = [int(x.strip()) for x in '$ADMIN_IDS'.split(',') if x.strip().isdigit()]
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("  ✓ Config disimpan!")
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
    systemctl is-active --quiet zivpn-bot.service && \
        echo -e "${GREEN}  ✓ Bot service OK${NC}" || \
        echo -e "${YELLOW}  ⚠ Bot gagal start. Cek: journalctl -u zivpn-bot.service -n 30${NC}"
}

print_done() {
    IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅  ZIVPN PANEL TERPASANG SEMPURNA!   ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  IP VPS    : ${CYAN}$IP${NC}"
    echo -e "${GREEN}║${NC}  Panel CMD : ${YELLOW}zivpn-panel${NC}"
    echo -e "${GREEN}║${NC}  Akun CMD  : ${YELLOW}zivpn-account${NC}"
    echo -e "${GREEN}║${NC}  ZIVPN     : $(systemctl is-active zivpn.service 2>/dev/null)"
    echo -e "${GREEN}║${NC}  Bot TG    : $(systemctl is-active zivpn-bot.service 2>/dev/null)"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Ketik ${YELLOW}zivpn-panel${NC} untuk membuka panel"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    clear
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
    write_scripts
    write_bot
    setup_cron
    configure_bot
    print_done
}

main
