#!/bin/bash
# Break this would catch: ffmpeg device indices resolved to the wrong
# capture screen or the wrong microphone when cameras and iPhones shift the list.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../record-lib.sh
. "$ROOT/record-lib.sh"

LIST=$(cat "$ROOT/test/fixtures/avfoundation.txt")

fail=0
check() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $msg (got '$got', want '$want')"
    fail=1
  fi
}

check "$(parse_capture_index "$LIST" 0)" "5" "Capture screen 0 is ffmpeg video device 5"
check "$(parse_capture_index "$LIST" 1)" "6" "Capture screen 1 is ffmpeg video device 6"
check "$(parse_capture_index "$LIST" 2)" ""  "missing Capture screen 2 is empty, not a camera"
check "$(parse_audio_index "$LIST" "MacBook Pro Microphone")" "1" "built-in mic is audio device 1"
check "$(parse_audio_index "$LIST" "Record-In")" "" "missing aggregate is empty, not BlackHole"

if [ "$fail" -ne 0 ]; then
  echo "parse_devices: failed"
  exit 1
fi
echo "parse_devices: ok"
