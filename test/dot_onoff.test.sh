#!/bin/bash
# Break this would catch: on/off leaving a stuck overlay, or the pid file
# never being written so registra cannot hide the dot on stop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="/tmp/registra-dot-onoff-$$"
PIDFILE="/tmp/registra-dot-pid-$$"
swiftc -O -o "$BIN" "$ROOT/registra-dot.swift" -framework AppKit
trap 'kill "$dotpid" 2>/dev/null || true; rm -f "$BIN" "$PIDFILE"' EXIT

"$BIN" on --screen 0 --pid-file "$PIDFILE" &
dotpid=$!

for _ in $(seq 1 40); do
  [ -s "$PIDFILE" ] && break
  sleep 0.1
done
[ -s "$PIDFILE" ] || { echo "FAIL: pid file was not written"; exit 1; }

file_pid=$(tr -d '[:space:]' < "$PIDFILE")
[ "$file_pid" = "$dotpid" ] || { echo "FAIL: pid file has '$file_pid', process is '$dotpid'"; exit 1; }
kill -0 "$dotpid" 2>/dev/null || { echo "FAIL: overlay process died immediately"; exit 1; }

kill -TERM "$dotpid"
for _ in $(seq 1 40); do
  kill -0 "$dotpid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$dotpid" 2>/dev/null; then
  echo "FAIL: overlay did not exit on SIGTERM"
  exit 1
fi

echo "dot_onoff: ok"
