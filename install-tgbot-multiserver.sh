#!/bin/bash
# ============================================================
#   OGH-ZIV Multi-Server Installer (Enhanced)
#   Support: 1 Master + Unlimited Worker Server
#   GitHub : https://github.com/chanelog/Cek-bot
# ============================================================

R='\033[1;31m'; Y='\033[1;33m'; G='\033[1;32m'
C='\033[1;36m'; W='\033[1;37m'; N='\033[0m'
DIM='\033[2m'; B='\033[1m'

# ── Path ─────────────────────────────────────────────────────
BOT_STORE_CONF="/etc/zivpn/bot_store.conf"
BOT_PY="/usr/local/bin/zivpn-tgbot.py"
WORKER_PY="/usr/local/bin/zivpn-api-worker.py"
WORKER_CONF="/etc/zivpn/worker.conf"
BOT_SVC="/etc/systemd/system/zivpn-tgbot.service"
WORKER_SVC="/etc/systemd/system/zivpn-api-worker.service"
SERVERS_JSON="/etc/zivpn/servers.json"

# ── URL Script ────────────────────────────────────────────────
BOT_URL="https://raw.githubusercontent.com/chanelog/Socks/main/zivpn_bot_v2.py"
WORKER_URL="https://raw.githubusercontent.com/chanelog/Socks/main/zivpn_api_worker.py"

clear
echo ""
echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
echo -e "${C}  ║   🤖  OGH-ZIV MULTI-SERVER INSTALLER               ║${N}"
echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
echo -e "${C}  ║${N}  Support: 1 Master Bot + Unlimited Worker Server     ${C}║${N}"
echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
echo ""

# ── Cek root ─────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo -e "${R}  ✘ Jalankan sebagai root!${N}"; exit 1; }

# ── Pilih mode install ────────────────────────────────────────
echo -e "${C}  Pilih mode instalasi:${N}"
echo ""
echo -e "  ${W}[1]${N} 🖥  VPS Master   ${DIM}— Install Bot Telegram (satu saja)${N}"
echo -e "  ${W}[2]${N} 🔌  VPS Worker   ${DIM}— Install API Worker (semua VPS remote)${N}"
echo -e "  ${W}[3]${N} 💾  Backup       ${DIM}— Backup config ZiVPN & Bot → kirim ke Telegram${N}"
echo -e "  ${W}[4]${N} 📦  Restore      ${DIM}— Restore dari file backup${N}"
echo -e "  ${W}[0]${N}     Keluar"
echo ""
read -rp "$(echo -e "  ${C}Pilih [0-4] : ${N}")" MODE

case "$MODE" in
  1) MODE_NAME="master" ;;
  2) MODE_NAME="worker" ;;
  3) MODE_NAME="backup" ;;
  4) MODE_NAME="restore" ;;
  0) echo -e "\n  ${Y}Dibatalkan.${N}\n"; exit 0 ;;
  *) echo -e "\n  ${R}✘ Pilihan tidak valid!${N}\n"; exit 1 ;;
esac

echo ""

# ════════════════════════════════════════════════════════════
#   MODE 1 — VPS MASTER (Bot Telegram)
# ════════════════════════════════════════════════════════════
install_master() {
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   🖥  INSTALL BOT TELEGRAM — VPS MASTER              ║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""

  # ── Install dependencies ───────────────────────────────────
  echo -e "${Y}  ➜  Menginstall dependencies...${N}"
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq python3 python3-pip curl wget 2>/dev/null
  echo -e "${G}  ✔  Dependencies selesai${N}"

  echo -e "${Y}  ➜  Menginstall python-telegram-bot...${N}"
  pip3 install python-telegram-bot --break-system-packages -q 2>/dev/null || \
  pip3 install python-telegram-bot -q 2>/dev/null

  echo -e "${Y}  ➜  Menginstall OCR (Tesseract)...${N}"
  apt-get install -y -qq tesseract-ocr tesseract-ocr-ind 2>/dev/null
  pip3 install pytesseract Pillow --break-system-packages -q 2>/dev/null || \
  pip3 install pytesseract Pillow -q 2>/dev/null

  # ── Download bot script ────────────────────────────────────
  echo -e "${Y}  ➜  Mengunduh bot script...${N}"
  mkdir -p /etc/zivpn
  curl -Ls "$BOT_URL" -o "$BOT_PY" 2>/dev/null || \
  wget -qO "$BOT_PY" "$BOT_URL" 2>/dev/null
  chmod +x "$BOT_PY" 2>/dev/null

  # Fix kompatibilitas Python lama
  sed -i '1s/^/from __future__ import annotations\n/' "$BOT_PY" 2>/dev/null
  echo -e "${G}  ✔  Script diunduh${N}"

  # ── Konfigurasi ────────────────────────────────────────────
  echo ""
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo -e "${C}  ⚙️   KONFIGURASI BOT${N}"
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo ""

  [[ -f "$BOT_STORE_CONF" ]] && source "$BOT_STORE_CONF" 2>/dev/null

  echo -ne "  ${C}Bot Token${N} (dari @BotFather) [${BOT_TOKEN:--}]: "
  read -r inp_token
  [[ -z "$inp_token" ]] && inp_token="${BOT_TOKEN:-}"
  [[ -z "$inp_token" ]] && { echo -e "${R}  ✘ Token tidak boleh kosong!${N}"; exit 1; }

  echo -ne "  ${C}No. DANA${N} [${DANA_NUMBER:-08xxxxxxxxxx}]: "
  read -r inp_dana_num
  [[ -z "$inp_dana_num" ]] && inp_dana_num="${DANA_NUMBER:-08xxxxxxxxxx}"

  echo -ne "  ${C}Nama Pemilik DANA${N} [${DANA_NAME:-Nama Pemilik}]: "
  read -r inp_dana_name
  [[ -z "$inp_dana_name" ]] && inp_dana_name="${DANA_NAME:-Nama Pemilik}"

  echo -ne "  ${C}Nama Brand${N} [${BRAND:-OGH-ZIV}]: "
  read -r inp_brand
  [[ -z "$inp_brand" ]] && inp_brand="${BRAND:-OGH-ZIV}"

  echo -ne "  ${C}Username Admin TG${N} [${ADMIN_TG:-@admin}]: "
  read -r inp_admin_tg
  [[ -z "$inp_admin_tg" ]] && inp_admin_tg="${ADMIN_TG:-@admin}"
  [[ "$inp_admin_tg" != @* ]] && inp_admin_tg="@${inp_admin_tg}"

  # ── Setup Server Remote (opsional, bisa tambah banyak) ─────
  echo ""
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo -e "${C}  🌍  KONFIGURASI SERVER REMOTE (Opsional)${N}"
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo -e "  ${DIM}Bisa dilewati dan ditambah nanti via bot Telegram.${N}"
  echo ""

  # Mulai dari server lokal (master)
  MY_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  MY_PORT=$(python3 -c "import json;d=json.load(open('/etc/zivpn/config.json'));print(d.get('listen',':5667').lstrip(':'))" 2>/dev/null || echo "5667")

  # Buat servers.json dengan server master dulu
  SERVERS_JSON_CONTENT=$(cat <<EOF
{
  "server1": {
    "label":   "🇮🇩 Indonesia",
    "enabled": true,
    "host":    "${MY_IP}",
    "port":    "${MY_PORT}",
    "api_url": "",
    "api_key": "",
    "note":    "Server Master — Lokal",
    "stock":   -1
  }
EOF
)

  # Loop tambah server remote
  SRV_INDEX=2
  while true; do
    echo -ne "  ${C}Tambah server remote ke-$((SRV_INDEX-1))?${N} [y/N]: "
    read -r add_more
    [[ "$add_more" != "y" && "$add_more" != "Y" ]] && break

    echo -ne "  ${C}Nama Region${N} (contoh: SG 01 / Japan / Germany): "
    read -r inp_srv_label
    [[ -z "$inp_srv_label" ]] && { echo -e "${R}  ✘ Nama tidak boleh kosong!${N}"; continue; }

    echo -ne "  ${C}IP/Domain VPS${N}: "
    read -r inp_srv_host
    [[ -z "$inp_srv_host" ]] && { echo -e "${R}  ✘ IP tidak boleh kosong!${N}"; continue; }

    echo -ne "  ${C}Port ZIVPN${N} [5667]: "
    read -r inp_srv_port
    [[ -z "$inp_srv_port" ]] && inp_srv_port="5667"

    echo -ne "  ${C}API URL${N} [http://${inp_srv_host}:8765]: "
    read -r inp_srv_api_url
    [[ -z "$inp_srv_api_url" ]] && inp_srv_api_url="http://${inp_srv_host}:8765"

    echo -ne "  ${C}API Key${N} (buat sendiri, catat untuk dipakai di VPS ini): "
    read -r inp_srv_api_key
    [[ -z "$inp_srv_api_key" ]] && inp_srv_api_key="ogh-ziv-$(openssl rand -hex 6)"
    echo -e "  ${G}  API Key: ${W}${inp_srv_api_key}${N}"

    # Buat server_id dari label
    SRV_ID=$(echo "$inp_srv_label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')_${SRV_INDEX}

    SERVERS_JSON_CONTENT+=",
  \"${SRV_ID}\": {
    \"label\":   \"${inp_srv_label}\",
    \"enabled\": true,
    \"host\":    \"${inp_srv_host}\",
    \"port\":    \"${inp_srv_port}\",
    \"api_url\": \"${inp_srv_api_url}\",
    \"api_key\": \"${inp_srv_api_key}\",
    \"note\":    \"Server Remote\",
    \"stock\":   -1
  }"

    echo -e "  ${G}  ✔ Server '${inp_srv_label}' ditambahkan.${N}"
    echo -e "  ${Y}  ⚠ Catat: install API Worker di VPS tersebut dengan API Key: ${W}${inp_srv_api_key}${N}"
    echo ""
    SRV_INDEX=$((SRV_INDEX + 1))
  done

  SERVERS_JSON_CONTENT+="
}"

  # ── Simpan konfigurasi ─────────────────────────────────────
  cat > "$BOT_STORE_CONF" <<EOF
# OGH-ZIV Bot Store Config
# Dibuat: $(date "+%Y-%m-%d %H:%M:%S")
BOT_TOKEN=${inp_token}
OWNER_ID=
ADMIN_IDS=
DANA_NUMBER=${inp_dana_num}
DANA_NAME=${inp_dana_name}
QRIS_ENABLED=0
BRAND=${inp_brand}
ADMIN_TG=${inp_admin_tg}
EOF

  echo "$SERVERS_JSON_CONTENT" > "$SERVERS_JSON"
  echo -e "${G}  ✔  Konfigurasi disimpan.${N}"

  # ── Buat systemd service ───────────────────────────────────
  cat > "$BOT_SVC" <<EOF
[Unit]
Description=OGH-ZIV Telegram Bot (Master)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${BOT_PY}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable zivpn-tgbot.service &>/dev/null
  systemctl restart zivpn-tgbot.service
  sleep 2

  if systemctl is-active --quiet zivpn-tgbot; then
    STATUS="${G}● RUNNING${N}"
  else
    STATUS="${R}● FAILED — cek: journalctl -u zivpn-tgbot -n 20${N}"
  fi

  echo ""
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   ✦  INSTALASI VPS MASTER SELESAI!                  ║${N}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "Brand"    "${inp_brand}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "No. DANA" "${inp_dana_num}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "A/N DANA" "${inp_dana_name}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "Admin TG" "${inp_admin_tg}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "IP Master" "${MY_IP}"
  printf  "  ${C}║${N}  %-20s : ${W}%s server${N}\n" "Total Server" "$((SRV_INDEX-1))"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  Status Bot : $STATUS"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  Perintah :                                          ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}systemctl status  zivpn-tgbot${N}                       ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}systemctl restart zivpn-tgbot${N}                       ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}journalctl -u zivpn-tgbot -f${N}                        ${C}║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""
  echo -e "  ${Y}⚠️  LANGKAH SELANJUTNYA:${N}"
  echo -e "  Untuk setiap VPS remote, login dan jalankan:"
  echo ""
  echo -e "  ${W}bash <(curl -Ls https://raw.githubusercontent.com/chanelog/cek/main/install-tgbot-multiserver.sh)${N}"
  echo ""
  echo -e "  Pilih ${W}[2] VPS Worker${N}, masukkan API Key yang sudah dicatat."
  echo ""
  echo -e "  ${G}✔  Buka Telegram → cari bot → kirim /start${N}"
  echo ""
}

# ════════════════════════════════════════════════════════════
#   MODE 2 — VPS WORKER (API Worker)
# ════════════════════════════════════════════════════════════
install_worker() {
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   🔌  INSTALL API WORKER — VPS REMOTE                ║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""

  # ── Install dependencies ───────────────────────────────────
  echo -e "${Y}  ➜  Menginstall dependencies...${N}"
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq python3 curl wget ufw 2>/dev/null
  echo -e "${G}  ✔  Dependencies selesai${N}"

  # ── Download worker script ─────────────────────────────────
  echo -e "${Y}  ➜  Mengunduh API Worker script...${N}"
  mkdir -p /etc/zivpn
  curl -Ls "$WORKER_URL" -o "$WORKER_PY" 2>/dev/null || \
  wget -qO "$WORKER_PY" "$WORKER_URL" 2>/dev/null
  chmod +x "$WORKER_PY" 2>/dev/null
  echo -e "${G}  ✔  Script diunduh${N}"

  # ── Konfigurasi ────────────────────────────────────────────
  echo ""
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo -e "${C}  ⚙️   KONFIGURASI API WORKER${N}"
  echo -e "${C}  ════════════════════════════════════════════════════${N}"
  echo -e "  ${DIM}API Key harus sama dengan yang dicatat saat install Master!${N}"
  echo ""

  [[ -f "$WORKER_CONF" ]] && source "$WORKER_CONF" 2>/dev/null

  echo -ne "  ${C}Nama Region VPS ini${N} (contoh: SG 01 / Japan): "
  read -r inp_region
  [[ -z "$inp_region" ]] && inp_region="Remote Server"

  echo -ne "  ${C}API Key${N} (dari VPS Master) [${API_KEY:--}]: "
  read -r inp_api_key
  [[ -z "$inp_api_key" ]] && inp_api_key="${API_KEY:-}"
  [[ -z "$inp_api_key" ]] && { echo -e "${R}  ✘ API Key tidak boleh kosong!${N}"; exit 1; }

  echo -ne "  ${C}Port API Worker${N} [8765]: "
  read -r inp_api_port
  [[ -z "$inp_api_port" ]] && inp_api_port="8765"

  # ── Simpan konfigurasi worker ──────────────────────────────
  cat > "$WORKER_CONF" <<EOF
# OGH-ZIV API Worker Config
# Region : ${inp_region}
# Dibuat : $(date "+%Y-%m-%d %H:%M:%S")
API_KEY=${inp_api_key}
API_PORT=${inp_api_port}
REGION=${inp_region}
EOF

  sed -i "s|API_KEY.*=.*\"GANTI_API_KEY_RAHASIA_INI\"|API_KEY     = \"${inp_api_key}\"|g" "$WORKER_PY"
  sed -i "s|LISTEN_PORT.*=.*8765|LISTEN_PORT = ${inp_api_port}|g" "$WORKER_PY"
  echo -e "${G}  ✔  Konfigurasi disimpan${N}"

  # ── Buka port firewall ─────────────────────────────────────
  echo -e "${Y}  ➜  Membuka port ${inp_api_port} di firewall...${N}"
  ufw allow "${inp_api_port}" &>/dev/null
  echo -e "${G}  ✔  Port ${inp_api_port} dibuka${N}"

  # ── Buat systemd service worker ────────────────────────────
  cat > "$WORKER_SVC" <<EOF
[Unit]
Description=OGH-ZIV API Worker (${inp_region})
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${WORKER_PY}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable zivpn-api-worker.service &>/dev/null
  systemctl restart zivpn-api-worker.service
  sleep 2

  if systemctl is-active --quiet zivpn-api-worker; then
    STATUS="${G}● RUNNING${N}"
  else
    STATUS="${R}● FAILED — cek: journalctl -u zivpn-api-worker -n 20${N}"
  fi

  MY_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

  echo ""
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   ✦  INSTALASI API WORKER SELESAI!                  ║${N}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "Region"       "${inp_region}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "IP Publik"    "${MY_IP}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "API Port"     "${inp_api_port}"
  printf  "  ${C}║${N}  %-20s : ${W}%s${N}\n" "API Key"      "${inp_api_key}"
  printf  "  ${C}║${N}  %-20s : ${W}http://%s:%s${N}\n" "API URL" "${MY_IP}" "${inp_api_port}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  Status Worker : $STATUS"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  Perintah :                                          ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}systemctl status  zivpn-api-worker${N}                 ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}systemctl restart zivpn-api-worker${N}                 ${C}║${N}"
  echo -e "${C}  ║${N}  ${DIM}journalctl -u zivpn-api-worker -f${N}                  ${C}║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""
  echo -e "${Y}  ⚠️  DAFTARKAN DI BOT TELEGRAM (VPS Master):${N}"
  echo -e "  Admin Panel → Kelola Server → ➕ Tambah Server"
  echo ""
  echo -e "  Isi data berikut:"
  echo -e "  • Nama Region  : ${W}${inp_region}${N}"
  echo -e "  • Host/IP      : ${W}${MY_IP}${N}"
  echo -e "  • API URL      : ${W}http://${MY_IP}:${inp_api_port}${N}"
  echo -e "  • API Key      : ${W}${inp_api_key}${N}"
  echo -e "  • Aktifkan     : ✅"
  echo ""
  echo -e "  ${G}✔  VPS ${inp_region} siap menerima perintah dari Bot!${N}"
  echo ""
}

# ════════════════════════════════════════════════════════════
#   JALANKAN SESUAI PILIHAN
# ════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════
#   MODE 3 — BACKUP
# ════════════════════════════════════════════════════════════
do_backup() {
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   💾  BACKUP CONFIG ZIVPN & BOT                     ║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""

  # ── Muat konfigurasi bot ────────────────────────────────────
  [[ -f "$BOT_STORE_CONF" ]] && source "$BOT_STORE_CONF" 2>/dev/null

  # ── Tanya token & chat_id jika belum ada ────────────────────
  if [[ -z "$BOT_TOKEN" ]]; then
    echo -ne "  ${C}Bot Token${N} (dari @BotFather): "
    read -r BOT_TOKEN
    [[ -z "$BOT_TOKEN" ]] && { echo -e "${R}  ✘ Token tidak boleh kosong!${N}"; exit 1; }
  fi

  echo -ne "  ${C}Chat ID / Username Telegram${N} tujuan backup (misal: 123456789): "
  read -r BACKUP_CHAT_ID
  [[ -z "$BACKUP_CHAT_ID" ]] && { echo -e "${R}  ✘ Chat ID tidak boleh kosong!${N}"; exit 1; }

  # ── Tanya apakah jadwal otomatis ───────────────────────────
  echo ""
  echo -ne "  ${C}Aktifkan backup otomatis via cron?${N} [y/N]: "
  read -r ENABLE_CRON

  # ── Buat folder temp ────────────────────────────────────────
  BACKUP_TMP="/tmp/zivpn-backup-$$"
  BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILE="/tmp/zivpn-backup_${BACKUP_DATE}.tar.gz"
  mkdir -p "$BACKUP_TMP"

  echo ""
  echo -e "${Y}  ➜  Mengumpulkan file backup...${N}"

  # ── Kumpulkan file penting ──────────────────────────────────
  # Config ZiVPN
  [[ -f /etc/zivpn/config.json        ]] && cp /etc/zivpn/config.json        "$BACKUP_TMP/" 2>/dev/null
  [[ -f /etc/zivpn/user.db            ]] && cp /etc/zivpn/user.db            "$BACKUP_TMP/" 2>/dev/null
  [[ -f /etc/zivpn/accounts.json      ]] && cp /etc/zivpn/accounts.json      "$BACKUP_TMP/" 2>/dev/null
  [[ -f "$BOT_STORE_CONF"             ]] && cp "$BOT_STORE_CONF"             "$BACKUP_TMP/" 2>/dev/null
  [[ -f "$SERVERS_JSON"               ]] && cp "$SERVERS_JSON"               "$BACKUP_TMP/" 2>/dev/null
  [[ -f "$WORKER_CONF"                ]] && cp "$WORKER_CONF"                "$BACKUP_TMP/" 2>/dev/null
  [[ -f "$BOT_PY"                     ]] && cp "$BOT_PY"                     "$BACKUP_TMP/" 2>/dev/null
  [[ -f "$WORKER_PY"                  ]] && cp "$WORKER_PY"                  "$BACKUP_TMP/" 2>/dev/null

  # Seluruh folder /etc/zivpn jika ada file lain
  if [[ -d /etc/zivpn ]]; then
    rsync -a --exclude="*.sock" /etc/zivpn/ "$BACKUP_TMP/etc_zivpn/" 2>/dev/null || \
    cp -r /etc/zivpn/. "$BACKUP_TMP/etc_zivpn/" 2>/dev/null
  fi

  # Catat info backup
  cat > "$BACKUP_TMP/backup_info.txt" <<EOF
=== ZIVPN BACKUP INFO ===
Tanggal   : $(date "+%Y-%m-%d %H:%M:%S")
Hostname  : $(hostname)
IP Publik : $(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
Dibuat oleh: OGH-ZIV Multi-Server Installer
EOF

  # ── Buat arsip ──────────────────────────────────────────────
  tar -czf "$BACKUP_FILE" -C "$BACKUP_TMP" . 2>/dev/null
  BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
  echo -e "${G}  ✔  Arsip backup dibuat: ${W}${BACKUP_FILE}${N} (${BACKUP_SIZE})"

  # ── Kirim ke Telegram ───────────────────────────────────────
  echo -e "${Y}  ➜  Mengirim ke Telegram...${N}"

  CAPTION="💾 *BACKUP ZIVPN*%0A"
  CAPTION+="📅 $(date '+%Y-%m-%d %H:%M:%S')%0A"
  CAPTION+="🖥 $(hostname) | $(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)%0A"
  CAPTION+="📦 Ukuran: ${BACKUP_SIZE}"

  TG_SEND=$(curl -s \
    -F "chat_id=${BACKUP_CHAT_ID}" \
    -F "caption=${CAPTION}" \
    -F "parse_mode=Markdown" \
    -F "document=@${BACKUP_FILE}" \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument")

  TG_OK=$(echo "$TG_SEND" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok','false'))" 2>/dev/null)

  if [[ "$TG_OK" == "True" ]]; then
    echo -e "${G}  ✔  Backup berhasil dikirim ke Telegram!${N}"
  else
    TG_ERR=$(echo "$TG_SEND" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('description','unknown error'))" 2>/dev/null)
    echo -e "${R}  ✘  Gagal kirim Telegram: ${TG_ERR}${N}"
    echo -e "${Y}  ⚠  File backup tetap tersimpan di: ${BACKUP_FILE}${N}"
  fi

  # ── Bersihkan temp ──────────────────────────────────────────
  rm -rf "$BACKUP_TMP" 2>/dev/null

  # ── Setup cron jika diminta ─────────────────────────────────
  if [[ "$ENABLE_CRON" == "y" || "$ENABLE_CRON" == "Y" ]]; then
    echo ""
    echo -e "${C}  ════════════════════════════════════════════════════${N}"
    echo -e "${C}  ⏰  SETUP BACKUP OTOMATIS (CRON)${N}"
    echo -e "${C}  ════════════════════════════════════════════════════${N}"
    echo ""
    echo -e "  Pilih jadwal backup otomatis:"
    echo -e "  ${W}[1]${N} Setiap hari (jam 02:00)"
    echo -e "  ${W}[2]${N} Setiap 12 jam (02:00 & 14:00)"
    echo -e "  ${W}[3]${N} Setiap minggu (Senin 02:00)"
    echo -ne "  ${C}Pilih [1-3]: ${N}"
    read -r CRON_CHOICE

    # Simpan token & chat_id ke file env untuk cron
    BACKUP_ENV="/etc/zivpn/backup_cron.env"
    cat > "$BACKUP_ENV" <<EOF
BOT_TOKEN=${BOT_TOKEN}
BACKUP_CHAT_ID=${BACKUP_CHAT_ID}
EOF
    chmod 600 "$BACKUP_ENV"

    # Script backup standalone untuk cron
    CRON_SCRIPT="/usr/local/bin/zivpn-backup.sh"
    cat > "$CRON_SCRIPT" <<'CRONEOF'
#!/bin/bash
source /etc/zivpn/backup_cron.env 2>/dev/null
[[ -z "$BOT_TOKEN" || -z "$BACKUP_CHAT_ID" ]] && exit 1

BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="/tmp/zivpn-backup_${BACKUP_DATE}.tar.gz"
BACKUP_TMP="/tmp/zivpn-bk-$$"
mkdir -p "$BACKUP_TMP"

[[ -d /etc/zivpn ]] && cp -r /etc/zivpn/. "$BACKUP_TMP/etc_zivpn/" 2>/dev/null
[[ -f /usr/local/bin/zivpn-tgbot.py   ]] && cp /usr/local/bin/zivpn-tgbot.py   "$BACKUP_TMP/" 2>/dev/null
[[ -f /usr/local/bin/zivpn-api-worker.py ]] && cp /usr/local/bin/zivpn-api-worker.py "$BACKUP_TMP/" 2>/dev/null

cat > "$BACKUP_TMP/backup_info.txt" <<EOF
Tanggal   : $(date "+%Y-%m-%d %H:%M:%S")
Hostname  : $(hostname)
IP Publik : $(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
Jenis     : Backup Otomatis (Cron)
EOF

tar -czf "$BACKUP_FILE" -C "$BACKUP_TMP" . 2>/dev/null
BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
rm -rf "$BACKUP_TMP" 2>/dev/null

CAPTION="🔄 *BACKUP OTOMATIS ZIVPN*%0A📅 $(date '+%Y-%m-%d %H:%M:%S')%0A🖥 $(hostname)%0A📦 Ukuran: ${BACKUP_SIZE}"

curl -s \
  -F "chat_id=${BACKUP_CHAT_ID}" \
  -F "caption=${CAPTION}" \
  -F "parse_mode=Markdown" \
  -F "document=@${BACKUP_FILE}" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" > /dev/null 2>&1

rm -f "$BACKUP_FILE" 2>/dev/null
CRONEOF
    chmod +x "$CRON_SCRIPT"

    # Hapus cron lama jika ada
    crontab -l 2>/dev/null | grep -v "zivpn-backup" | crontab - 2>/dev/null

    case "$CRON_CHOICE" in
      1) CRON_EXPR="0 2 * * *" ;   CRON_INFO="Setiap hari jam 02:00" ;;
      2) CRON_EXPR="0 2,14 * * *"; CRON_INFO="Setiap 12 jam (02:00 & 14:00)" ;;
      3) CRON_EXPR="0 2 * * 1" ;   CRON_INFO="Setiap Senin jam 02:00" ;;
      *) CRON_EXPR="0 2 * * *" ;   CRON_INFO="Setiap hari jam 02:00 (default)" ;;
    esac

    (crontab -l 2>/dev/null; echo "${CRON_EXPR} ${CRON_SCRIPT} >> /var/log/zivpn-backup.log 2>&1") | crontab -
    echo -e "${G}  ✔  Cron backup otomatis aktif: ${W}${CRON_INFO}${N}"
  fi

  echo ""
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   ✦  BACKUP SELESAI!                                ║${N}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  if [[ "$TG_OK" == "True" ]]; then
    echo -e "${C}  ║${N}  ${G}✔ File dikirim ke Telegram${N}"
  else
    echo -e "${C}  ║${N}  ${R}✘ Gagal kirim Telegram — cek token/chat ID${N}"
  fi
  if [[ "$ENABLE_CRON" == "y" || "$ENABLE_CRON" == "Y" ]]; then
    echo -e "${C}  ║${N}  ${G}✔ Backup otomatis: ${CRON_INFO}${N}"
    echo -e "${C}  ║${N}  ${DIM}Log: /var/log/zivpn-backup.log${N}"
  fi
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  ${DIM}Untuk restore, jalankan installer ini lagi → [4]${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""
}

# ════════════════════════════════════════════════════════════
#   MODE 4 — RESTORE
# ════════════════════════════════════════════════════════════
do_restore() {
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   📦  RESTORE CONFIG ZIVPN & BOT                    ║${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""

  # ── Pilih sumber restore ────────────────────────────────────
  echo -e "  Sumber file backup:"
  echo -e "  ${W}[1]${N} 📥  Download dari Telegram (forward file ke bot)"
  echo -e "  ${W}[2]${N} 📂  File lokal di VPS"
  echo ""
  echo -ne "  ${C}Pilih [1-2]: ${N}"
  read -r RESTORE_SRC

  RESTORE_FILE=""

  if [[ "$RESTORE_SRC" == "1" ]]; then
    # ── Restore via Telegram ─────────────────────────────────
    [[ -f "$BOT_STORE_CONF" ]] && source "$BOT_STORE_CONF" 2>/dev/null

    if [[ -z "$BOT_TOKEN" ]]; then
      echo -ne "  ${C}Bot Token${N}: "
      read -r BOT_TOKEN
      [[ -z "$BOT_TOKEN" ]] && { echo -e "${R}  ✘ Token tidak boleh kosong!${N}"; exit 1; }
    fi

    echo ""
    echo -e "${Y}  ➜  Mendapatkan file_id backup terakhir dari Telegram...${N}"
    echo -e "  ${DIM}Kirimkan file backup (.tar.gz) ke bot Telegram sekarang,${N}"
    echo -e "  ${DIM}lalu tekan Enter setelah file terkirim...${N}"
    echo -ne "  ${C}Tekan Enter setelah kirim file ke bot: ${N}"
    read -r

    # Ambil update terbaru dari bot
    TG_UPDATES=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?limit=10&offset=-10")
    FILE_ID=$(echo "$TG_UPDATES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('result', [])
for r in reversed(results):
    msg = r.get('message', {})
    doc = msg.get('document', {})
    fname = doc.get('file_name', '')
    if fname.startswith('zivpn-backup') and fname.endswith('.tar.gz'):
        print(doc.get('file_id', ''))
        break
" 2>/dev/null)

    if [[ -z "$FILE_ID" ]]; then
      echo -e "${R}  ✘ File backup tidak ditemukan di pesan terbaru bot.${N}"
      echo -e "${Y}  ⚠  Pastikan file sudah dikirim ke bot dan coba lagi.${N}"
      exit 1
    fi

    echo -e "${G}  ✔  File ditemukan, mengunduh...${N}"

    FILE_PATH=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${FILE_ID}" | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['file_path'])" 2>/dev/null)

    RESTORE_FILE="/tmp/zivpn-restore-$$.tar.gz"
    curl -s "https://api.telegram.org/file/bot${BOT_TOKEN}/${FILE_PATH}" -o "$RESTORE_FILE" 2>/dev/null

    if [[ ! -s "$RESTORE_FILE" ]]; then
      echo -e "${R}  ✘ Gagal mengunduh file dari Telegram.${N}"
      exit 1
    fi
    echo -e "${G}  ✔  File berhasil diunduh.${N}"

  else
    # ── Restore dari file lokal ──────────────────────────────
    echo ""
    echo -ne "  ${C}Path file backup${N} (contoh: /tmp/zivpn-backup_20240101.tar.gz): "
    read -r RESTORE_FILE
    if [[ ! -f "$RESTORE_FILE" ]]; then
      echo -e "${R}  ✘ File tidak ditemukan: ${RESTORE_FILE}${N}"
      exit 1
    fi
  fi

  # ── Konfirmasi sebelum restore ──────────────────────────────
  echo ""
  echo -e "${R}  ⚠️  PERINGATAN:${N} Restore akan menimpa config yang ada sekarang!"
  echo -ne "  ${C}Lanjutkan restore?${N} [y/N]: "
  read -r CONFIRM
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && {
    echo -e "${Y}  Restore dibatalkan.${N}"; exit 0
  }

  # ── Backup kondisi sekarang dulu (auto-backup sebelum restore) ─
  echo ""
  echo -e "${Y}  ➜  Membuat backup kondisi saat ini sebelum restore...${N}"
  PRE_RESTORE_BACKUP="/tmp/zivpn-prerestore-$(date +%Y%m%d_%H%M%S).tar.gz"
  PRE_TMP="/tmp/zivpn-pre-$$"
  mkdir -p "$PRE_TMP"
  [[ -d /etc/zivpn ]] && cp -r /etc/zivpn/. "$PRE_TMP/" 2>/dev/null
  tar -czf "$PRE_RESTORE_BACKUP" -C "$PRE_TMP" . 2>/dev/null
  rm -rf "$PRE_TMP" 2>/dev/null
  echo -e "${G}  ✔  Pre-restore backup: ${W}${PRE_RESTORE_BACKUP}${N}"

  # ── Hentikan service sebelum restore ───────────────────────
  echo -e "${Y}  ➜  Menghentikan service...${N}"
  systemctl stop zivpn-tgbot.service 2>/dev/null
  systemctl stop zivpn-api-worker.service 2>/dev/null

  # ── Ekstrak backup ──────────────────────────────────────────
  echo -e "${Y}  ➜  Mengekstrak backup...${N}"
  RESTORE_TMP="/tmp/zivpn-restore-extract-$$"
  mkdir -p "$RESTORE_TMP"
  tar -xzf "$RESTORE_FILE" -C "$RESTORE_TMP" 2>/dev/null

  if [[ $? -ne 0 ]]; then
    echo -e "${R}  ✘ Gagal mengekstrak backup. File mungkin rusak.${N}"
    systemctl start zivpn-tgbot.service 2>/dev/null
    exit 1
  fi

  # Tampilkan info backup
  if [[ -f "$RESTORE_TMP/backup_info.txt" ]]; then
    echo ""
    echo -e "${C}  ── Info Backup ───────────────────────────────────────${N}"
    cat "$RESTORE_TMP/backup_info.txt" | while IFS= read -r line; do
      echo -e "  ${DIM}${line}${N}"
    done
    echo -e "${C}  ──────────────────────────────────────────────────────${N}"
    echo ""
  fi

  # ── Restore file ke lokasi asli ─────────────────────────────
  mkdir -p /etc/zivpn /usr/local/bin

  # Restore /etc/zivpn
  if [[ -d "$RESTORE_TMP/etc_zivpn" ]]; then
    cp -r "$RESTORE_TMP/etc_zivpn/." /etc/zivpn/ 2>/dev/null
    echo -e "${G}  ✔  /etc/zivpn restored${N}"
  fi

  # Restore file individual jika ada
  for f in config.json user.db accounts.json bot_store.conf servers.json worker.conf; do
    [[ -f "$RESTORE_TMP/$f" ]] && cp "$RESTORE_TMP/$f" /etc/zivpn/ 2>/dev/null
  done

  [[ -f "$RESTORE_TMP/zivpn-tgbot.py"     ]] && { cp "$RESTORE_TMP/zivpn-tgbot.py"     "$BOT_PY";    chmod +x "$BOT_PY";    echo -e "${G}  ✔  zivpn-tgbot.py restored${N}"; }
  [[ -f "$RESTORE_TMP/zivpn_api_worker.py" ]] && { cp "$RESTORE_TMP/zivpn_api_worker.py" "$WORKER_PY"; chmod +x "$WORKER_PY"; echo -e "${G}  ✔  zivpn-api-worker.py restored${N}"; }

  # ── Bersihkan temp ──────────────────────────────────────────
  rm -rf "$RESTORE_TMP" 2>/dev/null
  [[ "$RESTORE_SRC" == "1" ]] && rm -f "$RESTORE_FILE" 2>/dev/null

  # ── Restart service ─────────────────────────────────────────
  echo -e "${Y}  ➜  Merestart service...${N}"
  systemctl daemon-reload 2>/dev/null
  systemctl start zivpn-tgbot.service 2>/dev/null
  systemctl start zivpn-api-worker.service 2>/dev/null
  sleep 2

  BOT_STATUS="${R}● STOPPED${N}"
  WORKER_STATUS="${R}● STOPPED${N}"
  systemctl is-active --quiet zivpn-tgbot       && BOT_STATUS="${G}● RUNNING${N}"
  systemctl is-active --quiet zivpn-api-worker  && WORKER_STATUS="${G}● RUNNING${N}"

  echo ""
  echo -e "${C}  ╔══════════════════════════════════════════════════════╗${N}"
  echo -e "${C}  ║   ✦  RESTORE SELESAI!                               ║${N}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  Status Bot    : ${BOT_STATUS}"
  echo -e "${C}  ║${N}  Status Worker : ${WORKER_STATUS}"
  echo -e "${C}  ╠══════════════════════════════════════════════════════╣${N}"
  echo -e "${C}  ║${N}  ${DIM}Pre-restore backup: ${PRE_RESTORE_BACKUP}${N}"
  echo -e "${C}  ║${N}  ${DIM}(simpan file ini jika ingin rollback)${N}"
  echo -e "${C}  ╚══════════════════════════════════════════════════════╝${N}"
  echo ""
}

case "$MODE_NAME" in
  master)  install_master ;;
  worker)  install_worker ;;
  backup)  do_backup ;;
  restore) do_restore ;;
esac
