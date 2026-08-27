#!/bin/bash
# Break this would catch: overlay helper listing screens in a different
# order than ffmpeg "Capture screen N", so the red dot lands on the
# display that is not being recorded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="/tmp/record-dot-test-$$"
swiftc -O -o "$BIN" "$ROOT/record-dot.swift" -framework AppKit
trap 'rm -f "$BIN"' EXIT

out=$("$BIN" screens)
[ -n "$out" ] || { echo "FAIL: screens produced no output"; exit 1; }

first=$(echo "$out" | head -1)
index=$(echo "$first" | awk -F'\t' '{print $1}')
size=$(echo "$first" | awk -F'\t' '{print $4}')
flags=$(echo "$first" | awk -F'\t' '{print $5}')

[ "$index" = "0" ] || { echo "FAIL: first screen index is '$index', want 0"; exit 1; }
echo "$size" | grep -Eq '^[0-9]+x[0-9]+$' || { echo "FAIL: size '$size' is not WxH"; exit 1; }
echo "$flags" | grep -q 'main' || { echo "FAIL: screen 0 is not marked main (got '$flags')"; exit 1; }

echo "dot_screens: ok"
echo "$out"
