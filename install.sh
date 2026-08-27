#!/bin/bash
# Rebuild the toolchain on a new Mac. Idempotent: running it again is safe.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${REGISTRA_CONFIG:-$HOME/.config/registra/config}"
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi
DIR="${REGISTRA_DIR:-$HOME/Recordings}"

echo "== brew dependencies =="
brew list ffmpeg      >/dev/null 2>&1 || brew install ffmpeg
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
brew list skhd        >/dev/null 2>&1 || brew install koekeishiya/formulae/skhd
brew list --cask handy >/dev/null 2>&1 || brew install --cask handy
brew list switchaudio-osx >/dev/null 2>&1 || brew install switchaudio-osx
# BlackHole is a driver: it asks for the password. Without it, only the mic is recorded.
brew list --cask blackhole-2ch >/dev/null 2>&1 || brew install blackhole-2ch || \
  echo "WARN: BlackHole not installed; on a call only your voice will be recorded."

echo "== CoreAudio helper (registra-audio) =="
mkdir -p "$HOME/bin"
swiftc -O -o "$HOME/bin/registra-audio" "$HERE/registra-audio.swift" -framework CoreAudio

echo "== recording-dot overlay (registra-dot) =="
swiftc -O -o "$HOME/bin/registra-dot" "$HERE/registra-dot.swift" -framework AppKit

echo "== scripts in ~/bin =="
cp "$HERE/registra" "$HOME/bin/registra"
cp "$HERE/registra-lib.sh" "$HOME/bin/registra-lib.sh"
chmod +x "$HOME/bin/registra" "$HOME/bin/registra-lib.sh"
grep -q 'HOME/bin' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"

echo "== local config =="
mkdir -p "$HOME/.config/registra"
if [ ! -f "$CONFIG" ]; then
  cp "$HERE/config.example" "$CONFIG"
  echo "Wrote $CONFIG (edit it to point at your vault)."
else
  echo "Keeping existing $CONFIG"
fi

echo "== Option+R hotkey (skhd) =="
mkdir -p "$HOME/.config/skhd"
cp "$HERE/skhdrc" "$HOME/.config/skhd/skhdrc"

echo "== whisper model (large-v3-turbo, ~574 MB) =="
MODEL="$DIR/.whisper/ggml-large-v3-turbo-q5_0.bin"
if [ ! -f "$MODEL" ]; then
  mkdir -p "$(dirname "$MODEL")"
  curl -L --fail -o "$MODEL.part" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
  mv "$MODEL.part" "$MODEL"
fi

echo "== skhd service =="
skhd --start-service 2>/dev/null || skhd --restart-service 2>/dev/null || true

echo
echo "Done. Remaining permissions, once (System Settings > Privacy and Security):"
echo "  1. Accessibility      -> /opt/homebrew/bin/skhd"
echo "  2. Screen Recording   -> skhd (macOS asks on the first Option+R)"
echo "  3. Microphone         -> skhd"
echo
echo "Defaults: videos in $DIR, notes in ${REGISTRA_NOTES:-${REGISTRA_VAULT:-$HOME/Documents/Obsidian}/Recordings}"
echo "Edit $CONFIG to change paths or REGISTRA_SCREEN."
echo "List displays with: registra screens"
