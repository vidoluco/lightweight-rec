#!/bin/bash
# Break this would catch: a take started while the previous one is still
# transcribing losing its note. Stop, start again a minute later, and the first
# transcription is still running when the second take touches .session. That
# run used to finish with an unconditional `rm -f "$SESSION"`, deleting the
# marker of the take now recording. Its own stop then found "No session to
# transcribe." in .transcribe.log, exited 0, and the video sat on disk with no
# note and no error anywhere the user looks. Back-to-back meetings are exactly
# when this happens.
#
# The new take is started from inside the run: the whisper-cli stub touches
# .session forward in time the first time it is called, the moment a real
# start would land while Whisper is busy. The assertions are that the marker
# survives with that new mtime, and that the run still wrote its own note.
#
# Nothing real is touched. A throwaway HOME under TMPDIR, a stub for every
# external program, and `env -i` so the caller's own RECORD_* variables and
# ~/.config/record/config cannot reach the run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base newtake)
trap 'rm -rf "$BASE"' EXIT

SB="$BASE/home"
DIR="$SB/Recordings"
VAULT="$SB/Documents/Notebook"
NOTES="$VAULT/Recordings"
BIN="$BASE/bin"
TMP="$BASE/tmp"

sandbox_guard "$SB"    "$BASE" "the sandbox HOME"
sandbox_guard "$DIR"   "$BASE" "RECORD_DIR"
sandbox_guard "$NOTES" "$BASE" "RECORD_NOTES"

mkdir -p "$SB" "$DIR" "$VAULT/.obsidian" "$NOTES" "$TMP"
seed_recordings "$DIR"
make_stubs "$BIN"

# The stub whisper-cli, wrapped: on its first call it does what `record start`
# does to the marker, then answers as before.
mv "$BIN/whisper-cli" "$BIN/whisper-cli.real"
cat > "$BIN/whisper-cli" <<'EOF'
#!/bin/bash
# Wrapped stub whisper-cli: a new take starts during the first call.
set -euo pipefail
if [ ! -e "$RECORD_TEST_STARTED" ]; then
  touch -t 202601021100 "$RECORD_TEST_DIR/.session"
  : > "$RECORD_TEST_STARTED"
fi
exec "$(dirname "$0")/whisper-cli.real" "$@"
EOF
chmod +x "$BIN/whisper-cli"

out=$(run_transcribe "$ROOT" "$SB" "$BIN" "$TMP" "$DIR" "$VAULT" "$NOTES" \
  RECORD_TEST_DIR="$DIR" RECORD_TEST_STARTED="$BASE/started") && rc=0 || rc=$?

fail=0
bad() { echo "FAIL: $1"; fail=1; }

if [ "$rc" -ne 0 ]; then
  bad "record transcribe exited $rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# The fixture is the test: if the stub never ran, no take started mid-run and
# a surviving marker would prove nothing.
[ -e "$BASE/started" ] || bad "the wrapped whisper-cli never ran, so no take started mid-run"

count=$(find "$NOTES" -maxdepth 1 -name '*.md' | grep -c . || true)
[ "$count" -eq 1 ] || bad "expected exactly one note for the finished take, found $count"

# The assertion the old code fails: the new take's marker is still there, and
# it is the new one, not a leftover the next stop would read the wrong hours from.
if [ ! -e "$DIR/.session" ]; then
  bad "the transcription deleted the marker of the take started while it ran"
else
  touch -t 202601021100 "$BASE/expected"
  { [ "$DIR/.session" -nt "$BASE/expected" ] || [ "$BASE/expected" -nt "$DIR/.session" ]; } \
    && bad "the surviving marker is not the one the new take wrote"
fi

if [ "$fail" -ne 0 ]; then
  echo "transcribe_new_take: failed"
  exit 1
fi
echo "transcribe_new_take: ok"
