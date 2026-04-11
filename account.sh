#!/bin/bash
# ============================================================
#   ZIVPN ACCOUNT MANAGER
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_FILE="/etc/zivpn-panel/database.json"
PANEL_DIR="/etc/zivpn-panel"
CONFIG_JSON="/etc/zivpn/config.json"

get_vps_ip() {
    hostname -I | awk '{print $1}'
}

update_zivpn_config() {
    # Rebuild config.json passwords dari database
    PASSWORDS=$(python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
accs = [a['password'] for a in db['accounts']]
if not accs:
    accs = ['zi']
print(','.join([f'"{p}"' for p in accs]))
EOF
)
    TMP=$(cat "$CONFIG_JSON")
    echo "$TMP" | python3 -c "
import json, sys
data = json.load(sys.stdin)
import subprocess
result = subprocess.check_output(['python3','-c','''
import json
with open(\"$DB_FILE\") as f:
    db = json.load(f)
accs = [a[\"password\"] for a in db[\"accounts\"]]
if not accs:
    accs = [\"zi\"]
print(json.dumps(accs))
'''])
data['config'] = json.loads(result)
print(json.dumps(data, indent=2))
" > /tmp/zivpn_config_tmp.json
    mv /tmp/zivpn_config_tmp.json "$CONFIG_JSON"
    systemctl restart zivpn.service >/dev/null 2>&1
}

create_account() {
    local USERNAME="$1"
    local PASSWORD="$2"
    local DAYS="$3"
    local MAXLOGIN="${4:-2}"
    local CREATED_BY="${5:-admin}"

    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$DAYS" ]; then
        echo "Usage: $0 create <username> <password> <days> [maxlogin] [created_by]"
        exit 1
    fi

    # Check duplicate
    EXISTS=$(python3 -c "
import json
with open('$DB_FILE') as f:
    db = json.load(f)
found = any(a['username'] == '$USERNAME' for a in db['accounts'])
print('yes' if found else 'no')
")
    if [ "$EXISTS" = "yes" ]; then
        echo "ERROR: Username '$USERNAME' sudah ada!"
        exit 1
    fi

    EXP_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d")
    UUID=$(uuidgen)

    python3 - <<EOF
import json
from datetime import datetime, timedelta

with open('$DB_FILE') as f:
    db = json.load(f)

account = {
    "uuid": "$UUID",
    "username": "$USERNAME",
    "password": "$PASSWORD",
    "days": $DAYS,
    "maxlogin": $MAXLOGIN,
    "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    "expired_at": "$EXP_DATE",
    "created_by": "$CREATED_BY",
    "active": True,
    "current_login": 0
}
db['accounts'].append(account)

with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)

print("OK")
EOF

    update_zivpn_config

    VPS_IP=$(get_vps_ip)
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        AKUN BERHASIL DIBUAT           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo -e " Username   : ${CYAN}$USERNAME${NC}"
    echo -e " Password   : ${CYAN}$PASSWORD${NC}"
    echo -e " Max Login  : ${CYAN}$MAXLOGIN${NC}"
    echo -e " Expired    : ${YELLOW}$EXP_DATE${NC}"
    echo -e " IP VPS     : ${CYAN}$VPS_IP${NC}"
    echo -e " Port UDP   : ${CYAN}6000-19999${NC}"
    echo -e " Port Slow  : ${CYAN}5667${NC}"
    echo ""
}

delete_account() {
    local USERNAME="$1"
    if [ -z "$USERNAME" ]; then
        echo "Usage: $0 delete <username>"
        exit 1
    fi

    ACCOUNT_INFO=$(python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
for a in db['accounts']:
    if a['username'] == '$USERNAME':
        print(f"Username : {a['username']}")
        print(f"Password : {a['password']}")
        print(f"Expired  : {a['expired_at']}")
        print(f"MaxLogin : {a['maxlogin']}")
        break
else:
    print("NOT_FOUND")
EOF
)

    if echo "$ACCOUNT_INFO" | grep -q "NOT_FOUND"; then
        echo "ERROR: Akun '$USERNAME' tidak ditemukan!"
        exit 1
    fi

    echo -e "${YELLOW}Akun yang akan dihapus:${NC}"
    echo "$ACCOUNT_INFO"
    echo ""

    python3 - <<EOF
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['accounts'] = [a for a in db['accounts'] if a['username'] != '$USERNAME']
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print("OK")
EOF

    update_zivpn_config
    echo -e "${GREEN}Akun '$USERNAME' berhasil dihapus!${NC}"
}

delete_expired() {
    echo -e "${CYAN}Menghapus akun expired...${NC}"
    DELETED=$(python3 - <<EOF
import json
from datetime import datetime

with open('$DB_FILE') as f:
    db = json.load(f)

today = datetime.now().strftime("%Y-%m-%d")
expired = [a['username'] for a in db['accounts'] if a['expired_at'] < today]
db['accounts'] = [a for a in db['accounts'] if a['expired_at'] >= today]

with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)

print('\n'.join(expired))
EOF
)
    if [ -n "$DELETED" ]; then
        update_zivpn_config
        echo -e "${GREEN}Dihapus: $DELETED${NC}"
    else
        echo -e "${YELLOW}Tidak ada akun expired.${NC}"
    fi
}

check_maxlogin() {
    # Kill user yang melebihi maxlogin
    python3 - <<EOF
import json, subprocess

with open('$DB_FILE') as f:
    db = json.load(f)

for acc in db['accounts']:
    uname = acc['username']
    maxlogin = acc.get('maxlogin', 2)
    try:
        result = subprocess.check_output(
            f"ps aux | grep -w '{uname}' | grep -v grep | wc -l",
            shell=True
        ).decode().strip()
        current = int(result)
    except:
        current = 0

    if current > maxlogin:
        # Kill kelebihan koneksi
        subprocess.run(
            f"pkill -u {uname} 2>/dev/null || true",
            shell=True
        )
        print(f"[KILL] {uname}: {current} login (max:{maxlogin})")

EOF
}

list_accounts() {
    python3 - <<EOF
import json
from datetime import datetime

with open('$DB_FILE') as f:
    db = json.load(f)

today = datetime.now().strftime("%Y-%m-%d")
accs = db['accounts']

if not accs:
    print("Belum ada akun.")
else:
    print(f"{'No':<4} {'Username':<15} {'Exp':<12} {'Days':<6} {'MaxLogin':<9} {'Status':<8}")
    print("-" * 60)
    for i, a in enumerate(accs, 1):
        status = "AKTIF" if a['expired_at'] >= today else "EXPIRED"
        print(f"{i:<4} {a['username']:<15} {a['expired_at']:<12} {a['days']:<6} {a['maxlogin']:<9} {status:<8}")

EOF
}

backup_database() {
    BACKUP_DIR="$PANEL_DIR/backup"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.json"
    cp "$DB_FILE" "$BACKUP_FILE"
    echo "$BACKUP_FILE"
}

restore_database() {
    local BACKUP_FILE="$1"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "ERROR: File backup tidak ditemukan!"
        exit 1
    fi
    cp "$BACKUP_FILE" "$DB_FILE"
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
