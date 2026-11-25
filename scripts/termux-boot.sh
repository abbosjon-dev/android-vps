#!/usr/bin/env bash
# Telefon yoqilganda botni avtomatik ishga tushirish (Termux:Boot ilovasi kerak).
#   bash scripts/termux-boot.sh ~/bots/mybot.lua
set -euo pipefail
BOT="$(readlink -f "${1:?Foydalanish: termux-boot.sh <bot.lua>}")"
NAME="$(basename "$BOT" .lua)"
mkdir -p "$HOME/.termux/boot"
TARGET="$HOME/.termux/boot/luabot-$NAME.sh"
cat > "$TARGET" <<BOOT
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
cd "$(dirname "$BOT")"
exec luabot "$BOT" >/dev/null 2>&1
BOOT
chmod +x "$TARGET"
echo "Yaratildi: $TARGET"
echo "Termux:Boot ilovasini bir marta ochib qo'ying (F-Droid'dan o'rnating)."
