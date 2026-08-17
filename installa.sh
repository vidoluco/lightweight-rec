#!/bin/bash
# Rimonta il sistema su un Mac nuovo. Idempotente: rilanciarlo non rompe niente.
set -euo pipefail

QUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== dipendenze (brew) =="
brew list ffmpeg      >/dev/null 2>&1 || brew install ffmpeg
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
brew list skhd        >/dev/null 2>&1 || brew install koekeishiya/formulae/skhd
brew list --cask handy >/dev/null 2>&1 || brew install --cask handy
brew list switchaudio-osx >/dev/null 2>&1 || brew install switchaudio-osx
# BlackHole e' un driver: chiede la password. Senza, si registra solo il microfono.
brew list --cask blackhole-2ch >/dev/null 2>&1 || brew install blackhole-2ch || \
  echo "AVVISO: BlackHole non installato, in call si registrera' solo la tua voce."

echo "== helper CoreAudio (registra-audio) =="
mkdir -p "$HOME/bin"
swiftc -O -o "$HOME/bin/registra-audio" "$QUI/registra-audio.swift" -framework CoreAudio

echo "== script in ~/bin =="
mkdir -p "$HOME/bin"
cp "$QUI/registra" "$HOME/bin/registra"
chmod +x "$HOME/bin/registra"
grep -q 'HOME/bin' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"

echo "== scorciatoia Option+R (skhd) =="
mkdir -p "$HOME/.config/skhd"
cp "$QUI/skhdrc" "$HOME/.config/skhd/skhdrc"

echo "== modello whisper (large-v3-turbo, ~574 MB) =="
MODELLO="$HOME/Registrazioni/.whisper/ggml-large-v3-turbo-q5_0.bin"
if [ ! -f "$MODELLO" ]; then
  mkdir -p "$(dirname "$MODELLO")"
  curl -L --fail -o "$MODELLO.part" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
  mv "$MODELLO.part" "$MODELLO"
fi

echo "== servizio skhd =="
skhd --start-service 2>/dev/null || skhd --restart-service 2>/dev/null || true

echo
echo "Fatto. Restano i permessi, una volta sola (Impostazioni > Privacy e Sicurezza):"
echo "  1. Accessibilita'         -> /opt/homebrew/bin/skhd"
echo "  2. Registrazione Schermo  -> skhd (lo chiede alla prima pressione di Option+R)"
echo "  3. Microfono              -> skhd"
echo "Controlla anche VAULT= in ~/bin/registra: deve puntare al tuo vault Obsidian."
