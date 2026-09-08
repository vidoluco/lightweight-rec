#!/bin/bash
# Break this would catch: RECORD_MIC never reaching record-audio, so the
# Record-In aggregate is built on CoreAudio's default input and the user
# records a microphone they did not ask for, silently.
#
# The bug was one missing word. RECORD_MIC arrives in `record` from
# `. "$CONFIG"`, which makes it a shell variable and NOT an exported one, and
# the helper was called bare: `PREV=$("$AUDIO_HELPER" up)`. record-audio reads
# ProcessInfo.processInfo.environment, found nothing, and fell through to the
# default input. Reverting the fix leaves the rest of the suite green, which is
# exactly why this file exists.
#
# The config here deliberately sets RECORD_MIC WITHOUT `export`, because the
# exported form always worked and would assert nothing.
#
# Only the `up` and `which` calls matter, and both happen early in `start`,
# before any device is resolved. The stub ffmpeg lists no capture screen on
# purpose, so the run fails immediately afterwards: this test is about what the
# helper was handed, not about reaching ffmpeg, and a start that cannot
# complete keeps the test far away from anything that records.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base micexport)
trap 'rm -rf "$BASE"' EXIT

SB="$BASE/home"
DIR="$SB/Recordings"
BIN="$BASE/bin"
LOG="$BASE/helper.log"
CONFIG="$SB/.config/record/config"
MIC_NAME="Scarlett Solo USB"

mkdir -p "$DIR" "$BIN" "$SB/.config/record"
sandbox_guard "$DIR" "$BASE" "the recordings directory"

# The helper stub records what it was handed and nothing else. `up` has to
# print a previous-output name, because record only calls `which` when `up`
# succeeded with non-empty output.
cat > "$BIN/record-audio" <<STUB
#!/bin/bash
printf 'cmd=%s RECORD_MIC=[%s]\n' "\${1:-}" "\${RECORD_MIC-<UNSET>}" >> "$LOG"
case "\${1:-}" in
  up)    echo "External Headphones" ;;
  which) echo "$MIC_NAME" ;;
esac
exit 0
STUB

# No capture screen in the list, so `start` stops right after the two calls
# under test. The audio side is present so nothing fails earlier than intended.
cat > "$BIN/ffmpeg" <<'STUB'
#!/bin/bash
for a in "$@"; do
  if [ "$a" = "-list_devices" ]; then
    cat >&2 <<'DEVICES'
[AVFoundation indev @ 0x1] AVFoundation video devices:
[AVFoundation indev @ 0x1] AVFoundation audio devices:
[AVFoundation indev @ 0x1] [0] Record-In
DEVICES
    exit 1
  fi
done
exit 0
STUB

chmod +x "$BIN/record-audio" "$BIN/ffmpeg"

# Not exported, on purpose: this is the shape the bug needed.
cat > "$CONFIG" <<CONF
RECORD_MIC="$MIC_NAME"
CONF

run_start() {
  env -i \
    PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$SB" \
    TMPDIR="$BASE/tmp" \
    RECORD_TEST_REAL_HOME="$REAL_HOME" \
    RECORD_CONFIG="$1" \
    RECORD_DIR="$DIR" \
    RECORD_DOT="$BASE/no-such-dot" \
    RECORD_AUDIO="$BIN/record-audio" \
    bash "$ROOT/record" start 2>&1 || true
}

mkdir -p "$BASE/tmp"
fail=0

# --- the assertion the bug would break ------------------------------------
: > "$LOG"
out=$(run_start "$CONFIG")

for cmd in up which; do
  if ! grep -qF "cmd=$cmd RECORD_MIC=[$MIC_NAME]" "$LOG"; then
    echo "FAIL: record-audio '$cmd' did not receive RECORD_MIC=\"$MIC_NAME\""
    echo "      helper log:"
    sed 's/^/        /' "$LOG"
    fail=1
  fi
done

# The start line has to name the device, not the aggregate wrapper. This also
# pins the fallback staying OUTSIDE the command substitution: with `|| true`
# inside it, a helper that fails prints its usage string here instead.
if ! printf '%s\n' "$out" | grep -qF "Full audio: $MIC_NAME"; then
  echo "FAIL: the start line did not name the resolved microphone"
  printf '%s\n' "$out" | sed 's/^/        /'
  fail=1
fi

# --- proof the log can show the failing state too --------------------------
# Without this, an assertion that only ever sees one value could be matching
# its own scaffolding rather than the behaviour.
: > "$LOG"
run_start "$SB/.config/record/config-that-does-not-exist" >/dev/null

if ! grep -qF 'cmd=up RECORD_MIC=[]' "$LOG"; then
  echo "FAIL: with no RECORD_MIC configured the helper should receive an empty"
  echo "      value, so the positive assertion above proves something."
  sed 's/^/        /' "$LOG"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "record_mic_export: failed"
  exit 1
fi

echo "record_mic_export: ok"
