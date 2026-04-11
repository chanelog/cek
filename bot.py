#!/usr/bin/env python3
# ============================================================
#   ZIVPN TELEGRAM BOT - FULL FEATURE
#   Support: Multi VPS | Reseller | Toko | Admin Control
# ============================================================

import os, json, subprocess, logging, uuid
from datetime import datetime, timedelta
from functools import wraps
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    ReplyKeyboardMarkup, KeyboardButton
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes, ConversationHandler
)
from telegram.constants import ParseMode

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

DB_FILE = os.environ.get("DB_FILE", "/etc/zivpn-panel/database.json")
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")

# States
(AWAIT_USERNAME, AWAIT_PASSWORD, AWAIT_DAYS, AWAIT_MAXLOGIN,
 AWAIT_DEL_USER, AWAIT_SERVER_NAME, AWAIT_SERVER_IP, AWAIT_SERVER_PORT,
 AWAIT_RESELLER_USER, AWAIT_RESELLER_ID, AWAIT_RESELLER_MAX,
 AWAIT_QRIS_PHOTO, AWAIT_HARGA15, AWAIT_HARGA30,
 AWAIT_RESTORE_FILE) = range(15)

# ─── DB HELPERS ─────────────────────────────────────────────

def load_db():
    with open(DB_FILE) as f:
        return json.load(f)

def save_db(db):
    with open(DB_FILE, 'w') as f:
        json.dump(db, f, indent=2)

def is_admin(uid):
    db = load_db()
    return uid in db['settings']['admin_ids']

def is_reseller(uid):
    db = load_db()
    return any(r['telegram_id'] == uid for r in db['resellers'])

def get_reseller(uid):
    db = load_db()
    for r in db['resellers']:
        if r['telegram_id'] == uid:
            return r
    return None

# ─── DECORATORS ─────────────────────────────────────────────

def admin_only(func):
    @wraps(func)
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id
        if not is_admin(uid):
            await update.message.reply_text("⛔ *Akses ditolak! Admin only.*", parse_mode=ParseMode.MARKDOWN)
            return
        return await func(update, ctx)
    return wrapper

def admin_or_reseller(func):
    @wraps(func)
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id
        if not is_admin(uid) and not is_reseller(uid):
            await update.message.reply_text("⛔ *Akses ditolak!*", parse_mode=ParseMode.MARKDOWN)
            return
        return await func(update, ctx)
    return wrapper

# ─── KEYBOARDS ──────────────────────────────────────────────

def main_keyboard(uid):
    db = load_db()
    admin = is_admin(uid)
    reseller = is_reseller(uid)

    if admin:
        kb = [
            [InlineKeyboardButton("👤 Create Akun", callback_data="create_akun"),
             InlineKeyboardButton("🗑 Hapus Akun", callback_data="hapus_akun")],
            [InlineKeyboardButton("📋 Info Akun", callback_data="info_akun"),
             InlineKeyboardButton("⏰ Hapus Expired", callback_data="hapus_expired")],
            [InlineKeyboardButton("🖥 Kelola Server", callback_data="kelola_server"),
             InlineKeyboardButton("💾 Backup/Restore", callback_data="backup")],
            [InlineKeyboardButton("🏪 Toko UDP", callback_data="toko"),
             InlineKeyboardButton("⚙️ Pengaturan", callback_data="pengaturan")],
            [InlineKeyboardButton("📊 Info VPS", callback_data="info_vps"),
             InlineKeyboardButton("🤖 Status Bot", callback_data="status_bot")],
        ]
    elif reseller:
        kb = [
            [InlineKeyboardButton("👤 Create Akun", callback_data="create_akun"),
             InlineKeyboardButton("🗑 Hapus Akun", callback_data="hapus_akun")],
            [InlineKeyboardButton("📋 Info Akun Saya", callback_data="info_akun_reseller"),
             InlineKeyboardButton("🏪 Toko UDP", callback_data="toko")],
        ]
    else:
        kb = [
            [InlineKeyboardButton("🏪 Beli Akun UDP", callback_data="toko"),
             InlineKeyboardButton("ℹ️ Cara Beli", callback_data="cara_beli")],
        ]
    return InlineKeyboardMarkup(kb)

# ─── START / MENU ────────────────────────────────────────────

async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    name = update.effective_user.first_name
    db = load_db()

    if is_admin(uid):
        role = "👑 *ADMIN*"
    elif is_reseller(uid):
        role = "💼 *RESELLER*"
    else:
        role = "👤 *User*"

    text = (
        f"╔══════════════════════════╗\n"
        f"║   🌐 ZIVPN UDP PANEL     ║\n"
        f"╚══════════════════════════╝\n\n"
        f"Halo, *{name}*!\n"
        f"Role: {role}\n\n"
        f"Pilih menu di bawah:"
    )
    await update.message.reply_text(text, reply_markup=main_keyboard(uid), parse_mode=ParseMode.MARKDOWN)

async def menu_callback(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    uid = query.from_user.id
    data = query.data

    handlers = {
        "main_menu":         show_main_menu,
        "create_akun":       cb_create_akun,
        "hapus_akun":        cb_hapus_akun,
        "info_akun":         cb_info_akun,
        "info_akun_reseller":cb_info_akun_reseller,
        "hapus_expired":     cb_hapus_expired,
        "kelola_server":     cb_kelola_server,
        "tambah_server":     cb_tambah_server,
        "list_server":       cb_list_server,
        "backup":            cb_backup_menu,
        "do_backup":         cb_do_backup,
        "toko":              cb_toko,
        "beli_15":           cb_beli_15,
        "beli_30":           cb_beli_30,
        "cara_beli":         cb_cara_beli,
        "pengaturan":        cb_pengaturan,
        "tambah_reseller":   cb_tambah_reseller_menu,
        "list_reseller":     cb_list_reseller,
        "upload_qris":       cb_upload_qris,
        "info_vps":          cb_info_vps,
        "status_bot":        cb_status_bot,
        "ubah_harga":        cb_ubah_harga,
    }

    if data in handlers:
        await handlers[data](query, ctx)
    elif data.startswith("hapus_user:"):
        await cb_konfirmasi_hapus(query, ctx, data.split(":")[1])
    elif data.startswith("confirm_hapus:"):
        await cb_do_hapus(query, ctx, data.split(":")[1])
    elif data.startswith("hapus_server:"):
        await cb_do_hapus_server(query, ctx, data.split(":")[1])
    elif data.startswith("hapus_reseller:"):
        await cb_do_hapus_reseller(query, ctx, data.split(":")[1])

async def show_main_menu(query, ctx):
    uid = query.from_user.id
    await query.edit_message_text(
        "🌐 *ZIVPN UDP PANEL*\n\nPilih menu:",
        reply_markup=main_keyboard(uid),
        parse_mode=ParseMode.MARKDOWN
    )

# ─── CREATE AKUN ────────────────────────────────────────────

async def cb_create_akun(query, ctx):
    uid = query.from_user.id
    if not is_admin(uid) and not is_reseller(uid):
        await query.edit_message_text("⛔ Akses ditolak!"); return

    if is_reseller(uid):
        rs = get_reseller(uid)
        db = load_db()
        my_accs = [a for a in db['accounts'] if a.get('created_by_id') == uid]
        if len(my_accs) >= rs['max_accounts']:
            await query.edit_message_text(
                f"⛔ Kamu sudah mencapai batas maksimal akun ({rs['max_accounts']})."
            ); return

    ctx.user_data['create_step'] = 'username'
    await query.edit_message_text(
        "👤 *CREATE AKUN BARU*\n\n"
        "Masukkan *username* akun:\n_(ketik /batal untuk membatalkan)_",
        parse_mode=ParseMode.MARKDOWN
    )
    return AWAIT_USERNAME

async def recv_username(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if update.message.text == '/batal':
        await update.message.reply_text("❌ Dibatalkan.")
        return ConversationHandler.END
    ctx.user_data['new_username'] = update.message.text.strip()
    await update.message.reply_text("🔑 Masukkan *password* akun:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_PASSWORD

async def recv_password(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['new_password'] = update.message.text.strip()
    await update.message.reply_text("📅 Masukkan *durasi* (hari), contoh: `15` atau `30`:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_DAYS

async def recv_days(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except:
        await update.message.reply_text("❌ Masukkan angka!"); return AWAIT_DAYS
    ctx.user_data['new_days'] = days
    await update.message.reply_text("🔒 Masukkan *max login* (default: 2):", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_MAXLOGIN

async def recv_maxlogin(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        ml = int(update.message.text.strip())
    except:
        ml = 2
    ctx.user_data['new_maxlogin'] = ml

    uid = update.effective_user.id
    uname = ctx.user_data['new_username']
    passwd = ctx.user_data['new_password']
    days = ctx.user_data['new_days']

    # Create account
    result = subprocess.run(
        ['zivpn-account', 'create', uname, passwd, str(days), str(ml), str(uid)],
        capture_output=True, text=True
    )
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    db = load_db()

    # Update created_by_id
    for a in db['accounts']:
        if a['username'] == uname:
            a['created_by_id'] = uid
    save_db(db)

    ip_list = "\n".join([f"• `{s['ip']}:{s['port']}`" for s in db['servers']] or ["• Belum ada server terdaftar"])
    msg = (
        f"✅ *AKUN BERHASIL DIBUAT*\n"
        f"{'═'*30}\n"
        f"👤 Username  : `{uname}`\n"
        f"🔑 Password  : `{passwd}`\n"
        f"📅 Expired   : `{exp}`\n"
        f"🔒 Max Login : `{ml}`\n"
        f"{'═'*30}\n"
        f"🌐 *Server Tersedia:*\n{ip_list}\n"
        f"🔌 Port UDP  : `6000-19999`\n"
        f"🔌 Port Slow : `5667`"
    )
    await update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN,
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🏠 Menu", callback_data="main_menu")]]))
    return ConversationHandler.END

# ─── HAPUS AKUN ─────────────────────────────────────────────

async def cb_hapus_akun(query, ctx):
    uid = query.from_user.id
    if not is_admin(uid) and not is_reseller(uid):
        await query.edit_message_text("⛔ Akses ditolak!"); return

    db = load_db()
    if is_reseller(uid):
        accs = [a for a in db['accounts'] if a.get('created_by_id') == uid]
    else:
        accs = db['accounts']

    if not accs:
        await query.edit_message_text("📭 Tidak ada akun.", reply_markup=back_btn()); return

    kb = []
    for a in accs:
        kb.append([InlineKeyboardButton(
            f"🗑 {a['username']} (exp: {a['expired_at']})",
            callback_data=f"hapus_user:{a['username']}"
        )])
    kb.append([InlineKeyboardButton("🔙 Kembali", callback_data="main_menu")])
    await query.edit_message_text("🗑 *Pilih akun yang akan dihapus:*",
        reply_markup=InlineKeyboardMarkup(kb), parse_mode=ParseMode.MARKDOWN)

async def cb_konfirmasi_hapus(query, ctx, username):
    db = load_db()
    acc = next((a for a in db['accounts'] if a['username'] == username), None)
    if not acc:
        await query.edit_message_text("❌ Akun tidak ditemukan!"); return

    msg = (
        f"⚠️ *KONFIRMASI HAPUS AKUN*\n\n"
        f"👤 Username : `{acc['username']}`\n"
        f"🔑 Password : `{acc['password']}`\n"
        f"📅 Expired  : `{acc['expired_at']}`\n\n"
        f"Yakin ingin menghapus?"
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Ya, Hapus", callback_data=f"confirm_hapus:{username}"),
         InlineKeyboardButton("❌ Batal", callback_data="hapus_akun")]
    ])
    await query.edit_message_text(msg, reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_do_hapus(query, ctx, username):
    subprocess.run(['zivpn-account', 'delete', username], capture_output=True)
    await query.edit_message_text(
        f"✅ Akun *{username}* berhasil dihapus!",
        reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN
    )

# ─── INFO AKUN ──────────────────────────────────────────────

async def cb_info_akun(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return
    db = load_db()
    accs = db['accounts']
    if not accs:
        await query.edit_message_text("📭 Belum ada akun.", reply_markup=back_btn()); return

    today = datetime.now().strftime("%Y-%m-%d")
    msg = "📋 *DAFTAR SEMUA AKUN*\n" + "═"*30 + "\n"
    for i, a in enumerate(accs, 1):
        status = "✅" if a['expired_at'] >= today else "❌"
        msg += (
            f"{i}. {status} `{a['username']}`\n"
            f"   🔑 `{a['password']}` | 📅 {a['expired_at']} | 👥 Max:{a['maxlogin']}\n"
        )
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

async def cb_info_akun_reseller(query, ctx):
    uid = query.from_user.id
    db = load_db()
    accs = [a for a in db['accounts'] if a.get('created_by_id') == uid]
    if not accs:
        await query.edit_message_text("📭 Kamu belum punya akun.", reply_markup=back_btn()); return

    today = datetime.now().strftime("%Y-%m-%d")
    msg = "📋 *AKUN KAMU*\n" + "═"*30 + "\n"
    for i, a in enumerate(accs, 1):
        status = "✅" if a['expired_at'] >= today else "❌"
        msg += f"{i}. {status} `{a['username']}` | 📅 {a['expired_at']}\n"

    rs = get_reseller(uid)
    msg += f"\n📊 Digunakan: {len(accs)}/{rs['max_accounts']}"
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

# ─── HAPUS EXPIRED ──────────────────────────────────────────

async def cb_hapus_expired(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return

    db = load_db()
    today = datetime.now().strftime("%Y-%m-%d")
    expired = [a['username'] for a in db['accounts'] if a['expired_at'] < today]

    if not expired:
        await query.edit_message_text("✅ Tidak ada akun expired.", reply_markup=back_btn()); return

    result = subprocess.run(['zivpn-account', 'delete-expired'], capture_output=True, text=True)
    msg = f"🗑 *{len(expired)} akun expired dihapus:*\n" + "\n".join([f"• `{u}`" for u in expired])
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

# ─── SERVER ─────────────────────────────────────────────────

async def cb_kelola_server(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Tambah Server", callback_data="tambah_server"),
         InlineKeyboardButton("📋 List Server", callback_data="list_server")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="main_menu")]
    ])
    await query.edit_message_text("🖥 *KELOLA SERVER*", reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_tambah_server(query, ctx):
    ctx.user_data['add_server_step'] = 'name'
    await query.edit_message_text("🖥 Masukkan *Nama Server* (contoh: VPS-1 Jakarta):",
        parse_mode=ParseMode.MARKDOWN)
    return AWAIT_SERVER_NAME

async def recv_server_name(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['srv_name'] = update.message.text.strip()
    await update.message.reply_text("🌐 Masukkan *IP Server*:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_SERVER_IP

async def recv_server_ip(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['srv_ip'] = update.message.text.strip()
    await update.message.reply_text("🔌 Masukkan *Port UDP* (contoh: 6000-19999):", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_SERVER_PORT

async def recv_server_port(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    db = load_db()
    server = {
        "id": str(uuid.uuid4())[:8],
        "name": ctx.user_data['srv_name'],
        "ip": ctx.user_data['srv_ip'],
        "port": update.message.text.strip(),
        "active": True
    }
    db['servers'].append(server)
    save_db(db)
    await update.message.reply_text(
        f"✅ *Server berhasil ditambahkan!*\n\n"
        f"🖥 Nama  : `{server['name']}`\n"
        f"🌐 IP    : `{server['ip']}`\n"
        f"🔌 Port  : `{server['port']}`",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=back_btn()
    )
    return ConversationHandler.END

async def cb_list_server(query, ctx):
    db = load_db()
    servers = db['servers']
    if not servers:
        await query.edit_message_text("📭 Belum ada server.", reply_markup=back_btn()); return

    kb = []
    msg = "🖥 *DAFTAR SERVER*\n" + "═"*30 + "\n"
    for s in servers:
        msg += f"• *{s['name']}*\n  IP: `{s['ip']}` | Port: `{s['port']}`\n"
        kb.append([InlineKeyboardButton(f"🗑 Hapus {s['name']}", callback_data=f"hapus_server:{s['id']}")])
    kb.append([InlineKeyboardButton("🔙 Kembali", callback_data="kelola_server")])
    await query.edit_message_text(msg, reply_markup=InlineKeyboardMarkup(kb), parse_mode=ParseMode.MARKDOWN)

async def cb_do_hapus_server(query, ctx, srv_id):
    db = load_db()
    db['servers'] = [s for s in db['servers'] if s['id'] != srv_id]
    save_db(db)
    await query.edit_message_text("✅ Server dihapus!", reply_markup=back_btn())

# ─── BACKUP ─────────────────────────────────────────────────

async def cb_backup_menu(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("💾 Backup & Kirim", callback_data="do_backup")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="main_menu")]
    ])
    await query.edit_message_text("💾 *BACKUP / RESTORE*\n\nPilih aksi:", reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_do_backup(query, ctx):
    result = subprocess.run(['zivpn-account', 'backup'], capture_output=True, text=True)
    backup_file = result.stdout.strip()
    if os.path.exists(backup_file):
        await query.message.reply_document(
            document=open(backup_file, 'rb'),
            caption=f"🗄 *ZIVPN Backup*\n📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            parse_mode=ParseMode.MARKDOWN
        )
        await query.edit_message_text("✅ Backup berhasil dikirim!", reply_markup=back_btn())
    else:
        await query.edit_message_text("❌ Gagal membuat backup!", reply_markup=back_btn())

async def handle_restore_file(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.effective_user.id):
        return
    if ctx.user_data.get('awaiting_restore'):
        doc = update.message.document
        file = await ctx.bot.get_file(doc.file_id)
        restore_path = f"/etc/zivpn-panel/backup/restore_{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
        await file.download_to_drive(restore_path)
        result = subprocess.run(['zivpn-account', 'restore', restore_path], capture_output=True, text=True)
        await update.message.reply_text("✅ Database berhasil di-restore!")
        ctx.user_data['awaiting_restore'] = False

# ─── TOKO ───────────────────────────────────────────────────

async def cb_toko(query, ctx):
    db = load_db()
    s = db['settings']
    p15 = s.get('price_15days', 6000)
    p30 = s.get('price_30days', 10000)

    servers_txt = "\n".join([f"• {sv['name']} - `{sv['ip']}`" for sv in db['servers']] or ["• Belum ada server"])
    msg = (
        f"🏪 *TOKO UDP ZIVPN*\n"
        f"{'═'*30}\n"
        f"📦 *Paket Tersedia:*\n\n"
        f"⏱ *15 Hari* — Rp {p15:,}\n"
        f"⏱ *30 Hari* — Rp {p30:,}\n\n"
        f"🌐 *Server Aktif:*\n{servers_txt}\n\n"
        f"🔌 Port: `6000-19999` (UDP)\n\n"
        f"💳 Pembayaran via QRIS"
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton(f"🛒 Beli 15 Hari (Rp {p15:,})", callback_data="beli_15"),
         InlineKeyboardButton(f"🛒 Beli 30 Hari (Rp {p30:,})", callback_data="beli_30")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="main_menu")]
    ])
    await query.edit_message_text(msg, reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_beli_15(query, ctx):
    await show_qris(query, 15)

async def cb_beli_30(query, ctx):
    await show_qris(query, 30)

async def show_qris(query, days):
    db = load_db()
    s = db['settings']
    price = s.get(f'price_{days}days', 6000 if days == 15 else 10000)
    qris = s.get('qris_photo', '')

    msg = (
        f"💳 *PEMBAYARAN QRIS*\n"
        f"{'═'*30}\n"
        f"📦 Paket   : *{days} Hari*\n"
        f"💰 Harga   : *Rp {price:,}*\n\n"
        f"Scan QR di bawah lalu kirim bukti transfer ke admin.\n\n"
        f"Admin akan membuatkan akun setelah pembayaran dikonfirmasi."
    )
    kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="toko")]])

    if qris:
        await query.message.reply_photo(photo=qris, caption=msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
        await query.delete_message()
    else:
        await query.edit_message_text(msg + "\n\n_QR belum dikonfigurasi, hubungi admin._",
            reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_cara_beli(query, ctx):
    msg = (
        "📖 *CARA BELI AKUN UDP*\n"
        "═"*30 + "\n\n"
        "1️⃣ Pilih paket (15/30 hari)\n"
        "2️⃣ Scan QRIS & bayar\n"
        "3️⃣ Screenshot bukti bayar\n"
        "4️⃣ Kirim ke admin\n"
        "5️⃣ Akun akan dikirim segera\n\n"
        "❓ Butuh bantuan? Hubungi admin."
    )
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

# ─── PENGATURAN ─────────────────────────────────────────────

async def cb_pengaturan(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Tambah Reseller", callback_data="tambah_reseller"),
         InlineKeyboardButton("📋 List Reseller", callback_data="list_reseller")],
        [InlineKeyboardButton("🖼 Upload QRIS", callback_data="upload_qris"),
         InlineKeyboardButton("💰 Ubah Harga", callback_data="ubah_harga")],
        [InlineKeyboardButton("📊 Info VPS", callback_data="info_vps")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="main_menu")]
    ])
    await query.edit_message_text("⚙️ *PENGATURAN*", reply_markup=kb, parse_mode=ParseMode.MARKDOWN)

async def cb_tambah_reseller_menu(query, ctx):
    ctx.user_data['add_rs_step'] = 'username'
    await query.edit_message_text("👤 Masukkan *username reseller*:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_RESELLER_USER

async def recv_reseller_user(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    ctx.user_data['rs_username'] = update.message.text.strip()
    await update.message.reply_text("🆔 Masukkan *Telegram ID* reseller:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_RESELLER_ID

async def recv_reseller_id(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        ctx.user_data['rs_tid'] = int(update.message.text.strip())
    except:
        await update.message.reply_text("❌ ID harus angka!"); return AWAIT_RESELLER_ID
    await update.message.reply_text("📦 Max akun yang bisa dibuat:", parse_mode=ParseMode.MARKDOWN)
    return AWAIT_RESELLER_MAX

async def recv_reseller_max(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        max_acc = int(update.message.text.strip())
    except:
        max_acc = 10
    db = load_db()
    reseller = {
        "id": str(uuid.uuid4())[:8],
        "username": ctx.user_data['rs_username'],
        "telegram_id": ctx.user_data['rs_tid'],
        "max_accounts": max_acc,
        "created_accounts": 0,
        "joined_at": datetime.now().strftime("%Y-%m-%d")
    }
    db['resellers'].append(reseller)
    save_db(db)
    await update.message.reply_text(
        f"✅ *Reseller berhasil ditambahkan!*\n\n"
        f"👤 Username  : `{reseller['username']}`\n"
        f"🆔 TG ID     : `{reseller['telegram_id']}`\n"
        f"📦 Max Akun  : `{max_acc}`",
        parse_mode=ParseMode.MARKDOWN, reply_markup=back_btn()
    )
    return ConversationHandler.END

async def cb_list_reseller(query, ctx):
    db = load_db()
    resellers = db['resellers']
    if not resellers:
        await query.edit_message_text("📭 Belum ada reseller.", reply_markup=back_btn()); return

    kb = []
    msg = "💼 *DAFTAR RESELLER*\n" + "═"*30 + "\n"
    for r in resellers:
        msg += f"• *{r['username']}* (ID: `{r['telegram_id']}`)\n  Max: {r['max_accounts']} akun\n"
        kb.append([InlineKeyboardButton(f"🗑 Hapus {r['username']}", callback_data=f"hapus_reseller:{r['id']}")])
    kb.append([InlineKeyboardButton("🔙 Kembali", callback_data="pengaturan")])
    await query.edit_message_text(msg, reply_markup=InlineKeyboardMarkup(kb), parse_mode=ParseMode.MARKDOWN)

async def cb_do_hapus_reseller(query, ctx, rs_id):
    db = load_db()
    db['resellers'] = [r for r in db['resellers'] if r['id'] != rs_id]
    save_db(db)
    await query.edit_message_text("✅ Reseller dihapus!", reply_markup=back_btn())

async def cb_upload_qris(query, ctx):
    ctx.user_data['awaiting_qris'] = True
    await query.edit_message_text(
        "🖼 *UPLOAD QRIS*\n\n"
        "Kirim *URL gambar QRIS* kamu\n_(Upload ke imgbb.com atau imgur.com terlebih dahulu)_",
        parse_mode=ParseMode.MARKDOWN
    )
    return AWAIT_QRIS_PHOTO

async def recv_qris_url(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    url = update.message.text.strip()
    db = load_db()
    db['settings']['qris_photo'] = url
    save_db(db)
    await update.message.reply_text("✅ QRIS berhasil diupdate!", reply_markup=back_btn())
    return ConversationHandler.END

async def cb_ubah_harga(query, ctx):
    db = load_db()
    s = db['settings']
    await query.edit_message_text(
        f"💰 *UBAH HARGA*\n\n"
        f"Harga saat ini:\n"
        f"• 15 Hari: Rp {s.get('price_15days', 6000):,}\n"
        f"• 30 Hari: Rp {s.get('price_30days', 10000):,}\n\n"
        f"Masukkan harga 15 hari baru:",
        parse_mode=ParseMode.MARKDOWN
    )
    return AWAIT_HARGA15

async def recv_harga15(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        ctx.user_data['harga15'] = int(update.message.text.strip())
    except:
        await update.message.reply_text("❌ Angka tidak valid!"); return AWAIT_HARGA15
    await update.message.reply_text("Masukkan harga 30 hari baru:")
    return AWAIT_HARGA30

async def recv_harga30(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    try:
        h30 = int(update.message.text.strip())
    except:
        await update.message.reply_text("❌ Angka tidak valid!"); return AWAIT_HARGA30
    db = load_db()
    db['settings']['price_15days'] = ctx.user_data['harga15']
    db['settings']['price_30days'] = h30
    save_db(db)
    await update.message.reply_text(
        f"✅ Harga diupdate!\n"
        f"• 15 Hari: Rp {ctx.user_data['harga15']:,}\n"
        f"• 30 Hari: Rp {h30:,}",
        reply_markup=back_btn()
    )
    return ConversationHandler.END

# ─── INFO & STATUS ──────────────────────────────────────────

async def cb_info_vps(query, ctx):
    try:
        ip = subprocess.check_output(['curl', '-s', 'ifconfig.me'], timeout=5).decode().strip()
    except:
        ip = 'N/A'

    ram = subprocess.check_output("free -h | awk '/^Mem:/{print $2\"/\"$3}'", shell=True).decode().strip()
    cpu = subprocess.check_output("nproc", shell=True).decode().strip()
    uptime = subprocess.check_output("uptime -p", shell=True).decode().strip()
    os_info = subprocess.check_output("lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2", shell=True).decode().strip()
    disk = subprocess.check_output("df -h / | awk 'NR==2{print $3\"/\"$2}'", shell=True).decode().strip()

    msg = (
        f"📊 *INFO VPS*\n"
        f"{'═'*30}\n"
        f"🌐 IP      : `{ip}`\n"
        f"💻 OS      : `{os_info}`\n"
        f"🧠 RAM     : `{ram}`\n"
        f"⚙️ CPU     : `{cpu} Core`\n"
        f"💽 Disk    : `{disk}`\n"
        f"⏱ Uptime  : `{uptime}`"
    )
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

async def cb_status_bot(query, ctx):
    if not is_admin(query.from_user.id):
        await query.edit_message_text("⛔ Akses ditolak!"); return
    db = load_db()

    total = len(db['accounts'])
    today = datetime.now().strftime("%Y-%m-%d")
    expired = sum(1 for a in db['accounts'] if a['expired_at'] < today)
    active = total - expired
    servers = len(db['servers'])
    resellers = len(db['resellers'])

    msg = (
        f"🤖 *STATUS PANEL*\n"
        f"{'═'*30}\n"
        f"👤 Total Akun  : `{total}`\n"
        f"✅ Akun Aktif  : `{active}`\n"
        f"❌ Akun Expired: `{expired}`\n"
        f"🖥 Server      : `{servers}`\n"
        f"💼 Reseller    : `{resellers}`\n"
        f"📅 Tanggal     : `{today}`"
    )
    await query.edit_message_text(msg, reply_markup=back_btn(), parse_mode=ParseMode.MARKDOWN)

# ─── UTILS ──────────────────────────────────────────────────

def back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu Utama", callback_data="main_menu")]])

async def cancel(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("❌ Dibatalkan.")
    return ConversationHandler.END

# ─── MAIN ───────────────────────────────────────────────────

def main():
    db = load_db()
    token = BOT_TOKEN or db['settings'].get('bot_token', '')
    if not token:
        print("ERROR: Bot token tidak ditemukan!")
        return

    app = Application.builder().token(token).build()

    # Conversation: Create Akun
    create_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(cb_create_akun, pattern="^create_akun$")],
        states={
            AWAIT_USERNAME:  [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_username)],
            AWAIT_PASSWORD:  [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_password)],
            AWAIT_DAYS:      [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_days)],
            AWAIT_MAXLOGIN:  [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_maxlogin)],
        },
        fallbacks=[CommandHandler("batal", cancel)]
    )

    # Conversation: Tambah Server
    server_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(cb_tambah_server, pattern="^tambah_server$")],
        states={
            AWAIT_SERVER_NAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_server_name)],
            AWAIT_SERVER_IP:   [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_server_ip)],
            AWAIT_SERVER_PORT: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_server_port)],
        },
        fallbacks=[CommandHandler("batal", cancel)]
    )

    # Conversation: Tambah Reseller
    reseller_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(cb_tambah_reseller_menu, pattern="^tambah_reseller$")],
        states={
            AWAIT_RESELLER_USER: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_reseller_user)],
            AWAIT_RESELLER_ID:   [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_reseller_id)],
            AWAIT_RESELLER_MAX:  [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_reseller_max)],
        },
        fallbacks=[CommandHandler("batal", cancel)]
    )

    # Conversation: Upload QRIS
    qris_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(cb_upload_qris, pattern="^upload_qris$")],
        states={
            AWAIT_QRIS_PHOTO: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_qris_url)],
        },
        fallbacks=[CommandHandler("batal", cancel)]
    )

    # Conversation: Ubah Harga
    harga_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(cb_ubah_harga, pattern="^ubah_harga$")],
        states={
            AWAIT_HARGA15: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_harga15)],
            AWAIT_HARGA30: [MessageHandler(filters.TEXT & ~filters.COMMAND, recv_harga30)],
        },
        fallbacks=[CommandHandler("batal", cancel)]
    )

    app.add_handler(CommandHandler("start", start))
    app.add_handler(create_conv)
    app.add_handler(server_conv)
    app.add_handler(reseller_conv)
    app.add_handler(qris_conv)
    app.add_handler(harga_conv)
    app.add_handler(CallbackQueryHandler(menu_callback))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_restore_file))

    print("🤖 ZIVPN Bot berjalan...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
