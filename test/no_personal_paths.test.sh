#!/bin/bash
# Break this would catch: a personal vault path, iCloud account folder, or
# first-name device leaking into the published tree as a default.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

hits=$(grep -RInE 'KB-Ludovico|Ludovico’s iPhone|Ludovico.s iPhone|it\.ludovico\.|HP E233' \
  "$ROOT" \
  --exclude-dir .git \
  --exclude-dir build \
  --exclude no_personal_paths.test.sh \
  || true)

if [ -n "$hits" ]; then
  echo "FAIL: personal identifiers in the published tree:"
  echo "$hits"
  exit 1
fi

echo "no_personal_paths: ok"
