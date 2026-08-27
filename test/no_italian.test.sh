#!/bin/bash
# Break this would catch: the Italian command name or aliases leaking back
# into the published tree after the rename to `record`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

hits=$(grep -RInE 'registra|Registra|avvia|trascrivi|installa|\bgiu\b|\bstato\b|distruggi|impilato' \
  "$ROOT" \
  --exclude-dir .git \
  --exclude-dir build \
  --exclude no_italian.test.sh \
  || true)

names=$(find "$ROOT" \( -name '*registra*' -o -name '*installa*' \) ! -path '*/.git/*' ! -name no_italian.test.sh || true)

if [ -n "$hits" ] || [ -n "$names" ]; then
  echo "FAIL: Italian leftovers in the published tree:"
  [ -n "$hits" ] && echo "$hits"
  [ -n "$names" ] && echo "$names"
  exit 1
fi

echo "no_italian: ok"
