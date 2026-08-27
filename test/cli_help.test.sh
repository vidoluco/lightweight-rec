#!/bin/bash
# Break this would catch: the CLI drifting back to Italian-only help, or
# dropping the screens subcommand that tells you which display is recorded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/record" "$ROOT/record-lib.sh"

help=$("$ROOT/record" help 2>&1) && hrc=0 || hrc=$?
echo "$help" | grep -q 'Usage: record' || { echo "FAIL: help is not English: $help"; exit 1; }
echo "$help" | grep -q 'screens' || { echo "FAIL: help does not mention screens"; exit 1; }
[ "$hrc" -eq 1 ] || { echo "FAIL: unknown command should exit 1"; exit 1; }

echo "cli_help: ok"
