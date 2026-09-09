#!/bin/bash
# Break this would catch: a start that records the microphone alone while
# saying it has system audio, or the reverse; ffmpeg handed the FIFO before
# the helper is ready, so it blocks on the open forever; a helper that failed
# or hung leaving the start hanging, or left running after the take.
#
# System audio arrives from record-audio, a Swift helper that streams raw PCM
# into a FIFO the moment ffmpeg opens it, and touches a ready file once its
# capture is up. `record start` waits on that file, not on a timer: a helper
# that fails exits without touching it, so the wait ends at once; one that
# hangs is given five seconds and then killed. In every case the recording
# starts, with or without the second input, and the start says which.
#
# The helper and ffmpeg are stubs. The helper stub does what the real one
# does from the outside: writes the ready file (or fails, or hangs, on
# request) and then sleeps in place of streaming. The ffmpeg stub answers the
# device probe from a fixture, writes down every argument it was given, drops
# one segment file so the start sees the capture come up, and sleeps.
# Everything lives under a throwaway HOME and the run is `env -i`, so nothing
# of the real machine, config or recordings is reachable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base sysaudio)
trap 'cleanup' EXIT

SB="$BASE/home"
DIR="$SB/Recordings"
BIN="$BASE/bin"
ARGV="$BASE/ffmpeg-argv.txt"
HELPER_LOG="$BASE/helper.log"
FIXTURE="$ROOT/test/fixtures/avfoundation.txt"

mkdir -p "$DIR" "$BIN" "$BASE/tmp"
sandbox_guard "$DIR" "$BASE" "the recordings directory"

# Whatever a case left running, so a failed assertion cannot leak a sleeping
# stub past the test. Pids only, never a pattern: a pattern could reach a
# real process of whoever runs the suite.
cleanup() {
  for f in "$DIR/.record.pid" "$DIR/.sysaudio.pid"; do
    if [ -f "$f" ]; then
      kill "$(tr -d '[:space:]' < "$f")" 2>/dev/null || true
    fi
  done
  rm -rf "$BASE"
}

cat > "$BIN/ffmpeg" <<'STUB'
#!/bin/bash
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub ffmpeg: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
  if [ "$a" = "-list_devices" ]; then
    cat "$RECORD_TEST_FIXTURE" >&2
    exit 1
  fi
done
printf '%s\n' "$@" > "$RECORD_TEST_ARGV"
# The output pattern is the last argument. One segment in its directory is
# what `record start` waits for before it calls the capture up.
out="${*: -1}"
: > "$(dirname "$out")/$(date +%Y-%m-%d_%H-%M).mp4"
exec sleep 30
STUB

cat > "$BIN/record-audio" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'argv: %s\n' "$*" >> "$RECORD_TEST_HELPER_LOG"
case "${RECORD_TEST_HELPER:-ok}" in
  fail)
    echo "record-audio: could not start the system audio capture: stub says no" >&2
    exit 1 ;;
  hang)
    exec sleep 30 ;;
  ok)
    ready=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--ready" ] && ready="$a"
      prev="$a"
    done
    [ -n "$ready" ] && : > "$ready"
    exec sleep 30 ;;
esac
STUB
chmod +x "$BIN/ffmpeg" "$BIN/record-audio"

# $1 = subcommand, then NAME=value pairs for record and the stubs.
run_record() {
  local sub="$1"
  shift
  env -i \
    PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$SB" \
    TMPDIR="$BASE/tmp" \
    RECORD_TEST_REAL_HOME="$REAL_HOME" \
    RECORD_TEST_FIXTURE="$FIXTURE" \
    RECORD_TEST_ARGV="$ARGV" \
    RECORD_TEST_HELPER_LOG="$HELPER_LOG" \
    RECORD_CONFIG="$SB/.config/record/config-that-does-not-exist" \
    RECORD_DIR="$DIR" \
    RECORD_DOT="$BASE/no-such-dot" \
    RECORD_AUDIO="$BIN/record-audio" \
    "$@" \
    bash "$ROOT/record" "$sub" 2>&1
}

# Between cases: stop what is running, forget what was recorded.
reset_case() {
  for f in "$DIR/.record.pid" "$DIR/.sysaudio.pid"; do
    [ -f "$f" ] && { kill "$(tr -d '[:space:]' < "$f")" 2>/dev/null || true; }
  done
  rm -f "$DIR"/.record.pid "$DIR"/.sysaudio.* "$DIR"/.session "$DIR"/*.mp4 "$ARGV" "$HELPER_LOG"
  rmdir "$DIR/.lock" 2>/dev/null || true
  : > "$HELPER_LOG"
}

pid_alive() { [ -f "$1" ] && kill -0 "$(tr -d '[:space:]' < "$1")" 2>/dev/null; }

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# ------------------------------------------------------- helper comes up
reset_case
out=$(run_record start) || bad "ok: start exited non-zero: $out"
printf '%s\n' "$out" | grep -qF 'Audio: MacBook Pro Microphone + system audio' \
  || bad "ok: the start line does not say microphone plus system audio: $out"
grep -q '^argv: capture ' "$HELPER_LOG" || bad "ok: the helper was not asked to capture"
grep -qF -- "--ready $DIR/.sysaudio.ready" "$HELPER_LOG" || bad "ok: the helper was not given the ready file"
[ -p "$DIR/.sysaudio.fifo" ] || bad "ok: no FIFO at $DIR/.sysaudio.fifo while recording"
pid_alive "$DIR/.sysaudio.pid" || bad "ok: the helper is not running after the start"
# ffmpeg got the FIFO as a raw second input, and a mix, not a plain -ac 1.
grep -q -x -- 'f32le' "$ARGV" || bad "ok: ffmpeg was not given the raw PCM input"
grep -q -x -- "$DIR/.sysaudio.fifo" "$ARGV" || bad "ok: ffmpeg was not given the FIFO"
grep -q -x -- '-filter_complex' "$ARGV" || bad "ok: ffmpeg has no mix filter"
grep -q 'amix=inputs=2' "$ARGV" || bad "ok: the filter does not mix two inputs"
grep -q -x -- '-map' "$ARGV" || bad "ok: without -map the mixed audio would not reach the file"
# The screen and microphone input stays exactly what it was: screen 0 is
# ffmpeg video [5], the built-in microphone audio [1] in this fixture.
grep -q -x -- '5:1' "$ARGV" || bad "ok: the avfoundation input is not 5:1: $(grep -A1 -x -- '-i' "$ARGV" | tr '\n' ' ')"
st=$(run_record status)
printf '%s\n' "$st" | grep -q 'Audio: microphone + system audio' || bad "ok: status does not report system audio: $st"

# stop: ffmpeg goes, the helper goes, the FIFO goes.
out=$(run_record stop) || bad "ok: stop exited non-zero: $out"
sleep 0.3
pid_alive "$DIR/.sysaudio.pid" && bad "ok: the helper survived the stop"
[ -e "$DIR/.sysaudio.fifo" ] && bad "ok: the FIFO survived the stop"
[ -e "$DIR/.sysaudio.pid" ] && bad "ok: .sysaudio.pid survived the stop"

# ------------------------------------------------------- helper fails
reset_case
out=$(run_record start RECORD_TEST_HELPER=fail) || bad "fail: start exited non-zero: $out"
printf '%s\n' "$out" | grep -q 'System audio unavailable' || bad "fail: the start did not say system audio is unavailable: $out"
printf '%s\n' "$out" | grep -q 'stub says no' || bad "fail: the helper's own reason was not shown: $out"
printf '%s\n' "$out" | grep -qF 'Audio: MacBook Pro Microphone only' || bad "fail: the start line does not say microphone only: $out"
grep -q -x -- 'f32le' "$ARGV" && bad "fail: ffmpeg was given the raw input although the helper failed"
grep -q -x -- '-filter_complex' "$ARGV" && bad "fail: ffmpeg was given a mix although the helper failed"
grep -A1 -x -- '-ac' "$ARGV" | grep -q -x -- '1' || bad "fail: the microphone-only path lost -ac 1"
[ -e "$DIR/.sysaudio.fifo" ] && bad "fail: the FIFO was left behind"
[ -e "$DIR/.sysaudio.pid" ] && bad "fail: .sysaudio.pid was left behind"
pid_alive "$DIR/.record.pid" || bad "fail: the recording itself did not start"

# ------------------------------------------------------- switched off
reset_case
out=$(run_record start RECORD_SYSTEM_AUDIO=0) || bad "off: start exited non-zero: $out"
printf '%s\n' "$out" | grep -q 'System audio is off' || bad "off: the start did not say the switch is off: $out"
[ -s "$HELPER_LOG" ] && bad "off: the helper was called although RECORD_SYSTEM_AUDIO=0: $(cat "$HELPER_LOG")"
grep -q -x -- 'f32le' "$ARGV" && bad "off: ffmpeg was given the raw input with the switch off"
grep -A1 -x -- '-ac' "$ARGV" | grep -q -x -- '1' || bad "off: the microphone-only path lost -ac 1"

# ------------------------------------------------------- helper hangs
# Never ready, never dead: the one case a start could wait on forever.
reset_case
start=$SECONDS
out=$(run_record start RECORD_TEST_HELPER=hang) || bad "hang: start exited non-zero: $out"
took=$((SECONDS - start))
printf '%s\n' "$out" | grep -q 'System audio unavailable' || bad "hang: the start did not give up on the helper: $out"
[ "$took" -lt 15 ] || bad "hang: the start waited ${took}s on a hung helper"
pid_alive "$DIR/.sysaudio.pid" && bad "hang: the hung helper was left running"
grep -q -x -- 'f32le' "$ARGV" && bad "hang: ffmpeg was given the raw input although the helper never came up"
pid_alive "$DIR/.record.pid" || bad "hang: the recording itself did not start"

# ------------------------------------------------------- record mic
reset_case
out=$(run_record mic) || bad "mic: exited non-zero: $out"
printf '%s\n' "$out" | grep -qF 'MacBook Pro Microphone' || bad "mic: does not name the resolved microphone: $out"
printf '%s\n' "$out" | grep -q '^System audio:' || bad "mic: does not say what happens to system audio: $out"
[ -s "$HELPER_LOG" ] && bad "mic: the helper was called by a read-only command: $(cat "$HELPER_LOG")"
out=$(run_record mic RECORD_MIC="MacBook Pro Mic") && bad "mic: a near-miss RECORD_MIC did not exit 1"
printf '%s\n' "$out" | grep -qF 'RECORD_MIC is "MacBook Pro Mic"' || bad "mic: the near miss is not quoted back: $out"

reset_case
if [ "$fail" -ne 0 ]; then
  echo "sysaudio_native: failed"
  exit 1
fi
echo "sysaudio_native: ok"
