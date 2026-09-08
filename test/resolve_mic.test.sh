#!/bin/bash
# Break this would catch: the microphone resolver picking a device that
# carries no voice. A loopback driver (BlackHole), a meeting app's virtual
# input or one of the Record-In / Record-Out aggregates this tool creates all
# open and record happily, and produce an hour of silence that nobody notices
# until the transcript comes back empty.
#
# One fixture per machine, because the resolver has to work on a Mac that is
# not the author's: every model names its built-in microphone after itself.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../record-lib.sh
. "$ROOT/record-lib.sh"

FIXTURES="$ROOT/test/fixtures"

if ! declare -F resolve_audio_index >/dev/null; then
  echo "FAIL: record-lib.sh has no resolve_audio_index helper"
  exit 1
fi

# Devices that must never be chosen. Recording any of them gives silence, or
# gives the machine its own output back.
NEVER='BlackHole|Soundflower|Loopback|Record-In|Record-Out|Multi-Output|ZoomAudioDevice|Teams Audio|VB-Cable|Krisp'

fail=0

# The audio device name ffmpeg lists at $2, so a test can say what an index
# means instead of asserting a bare number.
audio_name() {
  printf '%s\n' "$1" | awk -v want="$2" '
    /AVFoundation video devices:/ { audio = 0; next }
    /AVFoundation audio devices:/ { audio = 1; next }
    !audio { next }
    match($0, /\[[0-9]+\] /) {
      idx = substr($0, RSTART + 1, RLENGTH - 3)
      if (idx == want) { print substr($0, RSTART + RLENGTH); exit }
    }'
}

check() {
  local fixture="$1" want_index="$2" want_name="$3"
  local list got name
  list=$(cat "$FIXTURES/$fixture")
  got=$(resolve_audio_index "$list")
  name=$(audio_name "$list" "$got")
  if [ "$got" != "$want_index" ]; then
    echo "FAIL: $fixture resolved to '$got' ($name), want '$want_index' ($want_name)"
    fail=1
    return
  fi
  if [ -n "$got" ] && [ "$name" != "$want_name" ]; then
    echo "FAIL: $fixture index $got is '$name', the fixture meant '$want_name'"
    fail=1
  fi
}

# The machine this tool was written on: BlackHole sits at index 0, so a
# resolver that took the first input would record silence on every call.
check avfoundation.txt                    1 "MacBook Pro Microphone"
# Another model: the built-in is named after the machine, and the iPhone that
# happens to be on the desk is not the microphone anybody meant.
check avfoundation-macbook-air.txt        1 "MacBook Air Microphone"
# No built-in microphone at all: the USB one, not the loopback driver, not the
# meeting app's virtual input, and not the iPhone that walked past the desk.
# Continuity offers that iPhone to every nearby Mac and takes it away again
# when the phone leaves the room, so it is nobody's recording microphone.
check avfoundation-mac-mini.txt           2 "Yeti Stereo Microphone"
# Mid-recording on this tool's own setup: the aggregates it created are in the
# list, and they are the last thing it may record from.
check avfoundation-blackhole-aggregates.txt 4 "MacBook Pro Microphone"
# Both a built-in and an external microphone, the external one listed first.
# The documented order puts the built-in ahead of it: it is the one input the
# user cannot unplug halfway through a call.
check avfoundation-imac-usb-mic.txt        2 "iMac Microphone"
# An interface whose name says nothing about a microphone: still a real input,
# and still better than BlackHole.
check avfoundation-audio-interface.txt    1 "Scarlett 2i2 USB"
# Nothing real is plugged in. Printing nothing makes the caller refuse to start
# and name the failure, rather than open a loopback and record an hour of
# silence that nobody discovers until they go looking for the transcript.
check avfoundation-loopback-only.txt      "" ""
# ffmpeg lists the audio header with no devices under it when the microphone
# permission was refused.
check avfoundation-no-audio.txt           "" ""

# The invariant behind every case above, asserted over every fixture at once
# so a new one cannot be added without it.
for f in "$FIXTURES"/avfoundation*.txt; do
  list=$(cat "$f")
  idx=$(resolve_audio_index "$list")
  [ -n "$idx" ] || continue
  name=$(audio_name "$list" "$idx")
  if printf '%s\n' "$name" | grep -qE "$NEVER"; then
    echo "FAIL: $(basename "$f") resolved to '$name', which records no voice"
    fail=1
  fi
  if [ -z "$name" ]; then
    echo "FAIL: $(basename "$f") resolved to index $idx, which is not in the list"
    fail=1
  fi
done

# A video device index must never be mistaken for an audio one: the two lists
# are numbered independently and both start at 0.
list=$(cat "$FIXTURES/avfoundation.txt")
idx=$(resolve_audio_index "$list")
if [ "$(audio_name "$list" "$idx")" = "" ]; then
  echo "FAIL: the resolver returned an index outside the audio section"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "resolve_mic: failed"
  exit 1
fi
echo "resolve_mic: ok"
