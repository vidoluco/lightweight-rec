#!/bin/bash
# Prints the number of displays CoreGraphics considers ACTIVE.
#
# Exit 0 and a number: the answer is trustworthy. 0 means every display is
# asleep or detached, so nothing can be drawn on screen right now.
# Any other exit status: the question could not be answered. A caller must
# treat that as "unknown" and run the test anyway, never as "no display".
# Guessing "no display" is how a real failure turns into a silent skip.
#
# The Swift source next to this file is compiled once per source revision into
# TMPDIR and reused, so gating a whole suite costs one compile, not one per
# test.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/active-displays.swift"

[ -f "$SRC" ] || { echo "active-displays.swift is missing next to $0" >&2; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "swiftc not found" >&2; exit 1; }

# The stamp changes when the source changes, so an edited probe is rebuilt and
# a stale binary is never consulted.
stamp=$(cksum < "$SRC" | tr -d ' ')
BIN="${TMPDIR:-/tmp}/record-test-active-displays-$stamp"

if [ ! -x "$BIN" ]; then
  tmp="$BIN.$$"
  swiftc -O -o "$tmp" "$SRC" -framework CoreGraphics >/dev/null 2>&1 || {
    rm -f "$tmp"
    echo "could not compile $SRC" >&2
    exit 1
  }
  mv -f "$tmp" "$BIN"
fi

"$BIN"
