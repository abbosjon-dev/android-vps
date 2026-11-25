#!/usr/bin/env bash
# Android (Termux) yoki Linux'ga o'rnatish:
#   curl -fsSL https://raw.githubusercontent.com/abbosjon-dev/android-vps/main/install.sh | bash
# yoki repo ichida: bash install.sh
set -euo pipefail

REPO="https://github.com/abbosjon-dev/android-vps.git"
DIR="${LUABOT_HOME:-$HOME/android-vps}"

if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] && command -v pkg >/dev/null 2>&1; then
  echo "==> Termux aniqlandi, paketlar o'rnatilmoqda"
  pkg install -y lua54 curl git
  BIN="$PREFIX/bin"
else
  echo "==> Linux: lua, curl, git o'rnatilganiga ishonch hosil qiling"
  for c in curl git; do command -v $c >/dev/null || { echo "$c kerak" >&2; exit 1; }; done
  BIN="$HOME/.local/bin"; mkdir -p "$BIN"
fi

# Agar skript repo ichidan ishga tushgan bo'lsa — shu papkani ishlatamiz
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -f "$HERE/bot/init.lua" ]; then
  DIR="$HERE"
elif [ -d "$DIR/.git" ]; then
  echo "==> Yangilanmoqda: $DIR"; git -C "$DIR" pull --ff-only
else
  echo "==> Yuklanmoqda: $DIR"; git clone --depth 1 "$REPO" "$DIR"
fi

ln -sf "$DIR/bin/luabot" "$BIN/luabot"
echo "==> Tayyor! Sinash:  luabot --once $DIR/examples/basic.lua"
echo "    Avto-yoqish (Termux:Boot): bash $DIR/scripts/termux-boot.sh <bot.lua>"
