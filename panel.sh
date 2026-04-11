#!/bin/bash
# ============================================================
#   ZIVPN UDP PANEL - MENU UTAMA
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

DB_FILE="/etc/zivpn-panel/database.json"
PANEL_DIR="/etc/zivpn-panel"
BOT_DIR="$PANEL_DIR/bot"

clear_screen() { clear; }

get_ip() { curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'; }

get_account_count() {
    python3 -c "
import json
with open('$DB_FILE') as f:
    db = json.load(f)
print(len(db['accounts']))
" 2>/dev/null || echo "0"
}

get_expired_count() {
    python3 -c "
import json
from datetime import datetime
with open('$DB_FILE') as f:
    db = json.load(f)
today = datetime.now().strftime('%Y-%m-%d')
print(sum(1 for a in db['accounts'] if a['expired_at'] < today))
" 2>/dev/null || echo "0"
}

get_server_count() {
    python3 -c "
import json
with open('$DB_FILE') as f:
    db = json.load(f)
print(len(db['servers']))
" 2>/dev/null || echo "0"
}

zivpn_status() {
    systemctl is-active zivpn.service 2>/dev/null | grep -q "active" && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}"
}

bot_status() {
    systemctl is-active zivpn-bot.service 2>/dev/null | grep -q "active" && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}"
}

header() {
    clear_screen
    IP=$(get_ip)
    TOTAL=$(get_account_count)
    EXPIRED=$(get_expired_count)
    SERVERS=$(get_server_count)
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ZIVPN UDP PANEL - FULL POWER            ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC}  IP VPS    : %-20s  ZIVPN: %-8s${CYAN}║${NC}\n" "$IP" "$(zivpn_status | sed 's/\x1B\[[0-9;]*m//g')"
    printf "${CYAN}║${NC}  Akun      : %-5s  Expired: %-5s  Server: %-4s  ${CYAN}║${NC}\n" "$TOTAL" "$EXPIRED" "$SERVERS"
    printf "${CYAN}║${NC}  Bot TG    : %-20s                  ${CYAN}║${NC}\n" "$(bot_status | sed 's/\x1B\[[0-9;]*m//g')"
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
    read -p "  Pilih menu [0-9]: " CHOICE
    case "$CHOICE" in
        1) menu_create_akun ;;
        2) menu_hapus_akun ;;
        3) menu_info_akun ;;
        4) menu_hapus_expired ;;
        5) menu_backup ;;
        6) menu_server ;;
        7) menu_install_bin ;;
        8) menu_bot ;;
        9) menu_pengaturan ;;
        0) exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; menu_utama ;;
    esac
}

menu_create_akun() {
    header
    echo -e "${CYAN}  ╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║        CREATE AKUN BARU          ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════╝${NC}"
    echo ""
    read -p "  Username    : " USERNAME
    read -p "  Password    : " PASSWORD
    read -p "  Durasi (hari): " DAYS
    read -p "  Max Login   : " MAXLOGIN
    MAXLOGIN=${MAXLOGIN:-2}

    echo ""
    zivpn-account create "$USERNAME" "$PASSWORD" "$DAYS" "$MAXLOGIN" "admin"
    echo ""
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_hapus_akun() {
    header
    echo -e "${RED}  ╔══════════════════════════════════╗${NC}"
    echo -e "${RED}  ║          HAPUS AKUN              ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════╝${NC}"
    echo ""
    zivpn-account list
    echo ""
    read -p "  Username yang akan dihapus: " USERNAME
    if [ -n "$USERNAME" ]; then
        zivpn-account delete "$USERNAME"
    fi
    echo ""
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_info_akun() {
    header
    echo -e "${YELLOW}  ╔══════════════════════════════════╗${NC}"
    echo -e "${YELLOW}  ║         INFO SEMUA AKUN          ║${NC}"
    echo -e "${YELLOW}  ╚══════════════════════════════════╝${NC}"
    echo ""
    zivpn-account list
    echo ""
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_hapus_expired() {
    header
    echo -e "${RED}  ╔══════════════════════════════════╗${NC}"
    echo -e "${RED}  ║       HAPUS AKUN EXPIRED         ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════╝${NC}"
    echo ""
    zivpn-account delete-expired
    echo ""
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_backup() {
    header
    echo -e "${BLUE}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${BLUE}  ║         BACKUP / RESTORE          ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [1] Backup       ║  [2] Restore  ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [3] Backup + Kirim ke Telegram   ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${BLUE}  ║  [0] Kembali                      ║${NC}"
    echo -e "${BLUE}  ╚═══════════════════════════════════╝${NC}"
    echo ""
    read -p "  Pilih [0-3]: " CHOICE
    case "$CHOICE" in
        1)
            BFILE=$(zivpn-account backup)
            echo -e "${GREEN}Backup disimpan: $BFILE${NC}"
            ;;
        2)
            ls "$PANEL_DIR/backup/" 2>/dev/null
            echo ""
            read -p "  Nama file backup (full path): " BFILE
            zivpn-account restore "$BFILE"
            ;;
        3)
            BFILE=$(zivpn-account backup)
            send_backup_telegram "$BFILE"
            ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

send_backup_telegram() {
    local FILE="$1"
    TOKEN=$(python3 -c "import json; d=json.load(open('$DB_FILE')); print(d['settings']['bot_token'])")
    ADMIN=$(python3 -c "import json; d=json.load(open('$DB_FILE')); print(d['settings']['admin_ids'][0])" 2>/dev/null)
    if [ -n "$TOKEN" ] && [ -n "$ADMIN" ]; then
        curl -s -F "document=@$FILE" \
            -F "chat_id=$ADMIN" \
            -F "caption=🗄 ZIVPN Backup - $(date)" \
            "https://api.telegram.org/bot$TOKEN/sendDocument" >/dev/null
        echo -e "${GREEN}Backup terkirim ke Telegram!${NC}"
    else
        echo -e "${RED}Bot token/admin belum dikonfigurasi!${NC}"
    fi
}

menu_server() {
    header
    echo -e "${CYAN}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║         KELOLA SERVER (VPS)       ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [1] Tambah Server║  [2] List VPS ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${CYAN}  ║  [3] Hapus Server                 ║${NC}"
    echo -e "${CYAN}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║  [0] Kembali                      ║${NC}"
    echo -e "${CYAN}  ╚═══════════════════════════════════╝${NC}"
    echo ""
    read -p "  Pilih [0-3]: " CHOICE
    case "$CHOICE" in
        1) menu_tambah_server ;;
        2) list_servers ;;
        3) menu_hapus_server ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_server
}

menu_tambah_server() {
    echo ""
    read -p "  Nama Server  : " SRV_NAME
    read -p "  IP Server    : " SRV_IP
    read -p "  Port UDP     : " SRV_PORT
    read -p "  Keterangan   : " SRV_DESC

    python3 - <<EOF
import json, uuid
with open('$DB_FILE') as f:
    db = json.load(f)
server = {
    "id": str(uuid.uuid4())[:8],
    "name": "$SRV_NAME",
    "ip": "$SRV_IP",
    "port": "$SRV_PORT",
    "desc": "$SRV_DESC",
    "active": True
}
db['servers'].append(server)
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Server berhasil ditambahkan!")
EOF
}

list_servers() {
    echo ""
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
servers = db['servers']
if not servers:
    print("Belum ada server.")
else:
    print(f"{'No':<4} {'Nama':<20} {'IP':<16} {'Port':<8} {'Desc':<20}")
    print("-" * 72)
    for i, s in enumerate(servers, 1):
        print(f"{i:<4} {s['name']:<20} {s['ip']:<16} {s['port']:<8} {s['desc']:<20}")
EOF
}

menu_hapus_server() {
    list_servers
    echo ""
    read -p "  ID server yang dihapus: " SRV_ID
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['servers'] = [s for s in db['servers'] if s['id'] != '$SRV_ID']
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Server dihapus!")
EOF
}

menu_install_bin() {
    header
    echo -e "${CYAN}  ╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║     INSTALL / REINSTALL BIN      ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Status ZIVPN: $(zivpn_status)"
    echo ""
    echo -e "  [1] Install/Reinstall ZIVPN Binary"
    echo -e "  [2] Restart ZIVPN Service"
    echo -e "  [3] Stop ZIVPN Service"
    echo -e "  [4] Start ZIVPN Service"
    echo -e "  [0] Kembali"
    echo ""
    read -p "  Pilih: " CHOICE
    case "$CHOICE" in
        1)
            systemctl stop zivpn.service 2>/dev/null
            rm -f /usr/local/bin/zivpn
            wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
                -O /usr/local/bin/zivpn
            chmod +x /usr/local/bin/zivpn
            systemctl start zivpn.service
            echo -e "${GREEN}ZIVPN binary berhasil diinstall!${NC}"
            ;;
        2) systemctl restart zivpn.service; echo -e "${GREEN}ZIVPN restarted!${NC}" ;;
        3) systemctl stop zivpn.service; echo -e "${YELLOW}ZIVPN stopped!${NC}" ;;
        4) systemctl start zivpn.service; echo -e "${GREEN}ZIVPN started!${NC}" ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_bot() {
    header
    echo -e "${BLUE}  ╔═══════════════════════════════════╗${NC}"
    echo -e "${BLUE}  ║        KELOLA BOT TELEGRAM        ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╦═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [1] Start Bot    ║  [2] Stop Bot ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════╩═══════════════╣${NC}"
    echo -e "${BLUE}  ║  [3] Restart Bot                  ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${BLUE}  ║  [4] Log Bot                      ║${NC}"
    echo -e "${BLUE}  ╠═══════════════════════════════════╣${NC}"
    echo -e "${BLUE}  ║  [0] Kembali                      ║${NC}"
    echo -e "${BLUE}  ╚═══════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Status Bot: $(bot_status)"
    echo ""
    read -p "  Pilih [0-4]: " CHOICE
    case "$CHOICE" in
        1) systemctl start zivpn-bot.service; echo -e "${GREEN}Bot started!${NC}" ;;
        2) systemctl stop zivpn-bot.service; echo -e "${YELLOW}Bot stopped!${NC}" ;;
        3) systemctl restart zivpn-bot.service; echo -e "${GREEN}Bot restarted!${NC}" ;;
        4) journalctl -u zivpn-bot.service -n 50 --no-pager ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_utama
}

menu_pengaturan() {
    header
    echo -e "${WHITE}  ╔═══════════════════════════════════════╗${NC}"
    echo -e "${WHITE}  ║            PENGATURAN PANEL           ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╦═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [1] Tambah Resell║  [2] Hapus Resell ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════╩═══════════════════╣${NC}"
    echo -e "${WHITE}  ║  [3] Upload QRIS                      ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [4] Info VPS                         ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [5] Ubah Harga                       ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [6] Ganti Bot Token                  ║${NC}"
    echo -e "${WHITE}  ╠═══════════════════════════════════════╣${NC}"
    echo -e "${WHITE}  ║  [0] Kembali                          ║${NC}"
    echo -e "${WHITE}  ╚═══════════════════════════════════════╝${NC}"
    echo ""
    read -p "  Pilih [0-6]: " CHOICE
    case "$CHOICE" in
        1) menu_tambah_reseller ;;
        2) menu_hapus_reseller ;;
        3) menu_upload_qris ;;
        4) menu_info_vps ;;
        5) menu_ubah_harga ;;
        6) menu_ganti_token ;;
        0) menu_utama; return ;;
    esac
    read -p "  Tekan Enter untuk kembali..." dummy
    menu_pengaturan
}

menu_tambah_reseller() {
    echo ""
    read -p "  Username Reseller : " RS_USER
    read -p "  Telegram ID       : " RS_TID
    read -p "  Max Akun          : " RS_MAX
    RS_MAX=${RS_MAX:-10}

    python3 - <<EOF
import json, uuid
from datetime import datetime
with open('$DB_FILE') as f:
    db = json.load(f)
reseller = {
    "id": str(uuid.uuid4())[:8],
    "username": "$RS_USER",
    "telegram_id": $RS_TID,
    "max_accounts": $RS_MAX,
    "created_accounts": 0,
    "joined_at": datetime.now().strftime("%Y-%m-%d")
}
db['resellers'].append(reseller)
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print(f"Reseller '{RS_USER}' berhasil ditambahkan!")
EOF
}

menu_hapus_reseller() {
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
resellers = db['resellers']
if not resellers:
    print("Belum ada reseller.")
else:
    for i, r in enumerate(resellers, 1):
        print(f"[{i}] {r['username']} (TG: {r['telegram_id']}) Max: {r['max_accounts']}")
EOF
    echo ""
    read -p "  Username reseller yang dihapus: " RS_USER
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['resellers'] = [r for r in db['resellers'] if r['username'] != '$RS_USER']
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Reseller dihapus!")
EOF
}

menu_upload_qris() {
    echo ""
    echo -e "${CYAN}Masukkan URL foto QRIS (upload dulu ke imgur/imgbb):${NC}"
    read -p "  URL Foto QRIS: " QRIS_URL
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['settings']['qris_photo'] = '$QRIS_URL'
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("QRIS berhasil diupdate!")
EOF
}

menu_info_vps() {
    echo ""
    IP=$(get_ip)
    RAM=$(free -h | awk '/^Mem:/{print $2}')
    CPU=$(nproc)
    OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
    UPTIME=$(uptime -p)

    echo -e "${CYAN}  ╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║          INFO VPS                ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════╝${NC}"
    printf "  %-12s: %s\n" "IP" "$IP"
    printf "  %-12s: %s\n" "OS" "$OS"
    printf "  %-12s: %s\n" "RAM" "$RAM"
    printf "  %-12s: %s Core\n" "CPU" "$CPU"
    printf "  %-12s: %s\n" "Uptime" "$UPTIME"
}

menu_ubah_harga() {
    echo ""
    python3 -c "
import json
with open('$DB_FILE') as f:
    d = json.load(f)
s = d['settings']
print(f'Harga saat ini:')
print(f'  15 Hari : Rp {s[\"price_15days\"]}')
print(f'  30 Hari : Rp {s[\"price_30days\"]}')
"
    read -p "  Harga 15 Hari (Rp): " P15
    read -p "  Harga 30 Hari (Rp): " P30
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
if '$P15': db['settings']['price_15days'] = int('$P15')
if '$P30': db['settings']['price_30days'] = int('$P30')
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Harga berhasil diupdate!")
EOF
}

menu_ganti_token() {
    echo ""
    read -p "  Bot Token baru: " NEW_TOKEN
    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['settings']['bot_token'] = '$NEW_TOKEN'
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("Token diupdate! Restart bot...")
EOF
    systemctl restart zivpn-bot.service
}

# Entry point
menu_utama
