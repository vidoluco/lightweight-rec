#!/bin/bash
# Break this would catch: the usage line losing a subcommand that record still
# accepts, or being written in anything other than English. That line is the
# only documentation a user gets from the tool itself, so a subcommand missing
# from it is a subcommand nobody outside this repo knows exists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/record" "$ROOT/record-lib.sh"

help=$("$ROOT/record" help 2>&1) && hrc=0 || hrc=$?
echo "$help" | grep -q 'Usage: record' || { echo "FAIL: help is not English: $help"; exit 1; }

# Every subcommand the case statement in record handles.
for sub in start stop status toggle screens transcribe; do
  echo "$help" | grep -q "$sub" || { echo "FAIL: help does not mention $sub: $help"; exit 1; }
done

[ "$hrc" -eq 1 ] || { echo "FAIL: unknown command should exit 1"; exit 1; }

echo "cli_help: ok"
