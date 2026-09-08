#!/bin/bash
# Break this would catch: a RECORD_DIR whose name contains a space silently
# producing no note. The transcribe path used to walk its file list with an
# unquoted `for f in $FILES`, so "/Users/you/My Recordings/2026-01-02_09-00.mp4"
# arrived at ffmpeg as two nonexistent paths. ffmpeg exited non-zero, `set -e`
# ended the run, and nothing was ever written to the vault. The recording was
# on disk the whole time and the user had no way to know why the note never
# appeared. "Documents/Screen Recordings" is an ordinary thing to configure.
#
# The assertion is deliberately on the full paths in the finished note, not
# just on the note existing: a list of video files that were split in half
# points at files nobody can open.
#
# Nothing real is touched. A throwaway HOME under TMPDIR, a stub for every
# external program, and `env -i` so the caller's own RECORD_* variables and
# ~/.config/record/config cannot reach the run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base space)
trap 'rm -rf "$BASE"' EXIT

SB="$BASE/home"
DIR="$SB/Screen Recordings 2026"
VAULT="$SB/Documents/Notebook"
NOTES="$VAULT/Recordings"
BIN="$BASE/bin"
TMP="$BASE/tmp"

# The fixture is the test. A sandbox whose name lost its space would pass
# while proving nothing, so say so instead of going green.
case "$DIR" in
  *" "*) ;;
  *) echo "FAIL: the sandbox RECORD_DIR '$DIR' has no space in it"; exit 1 ;;
esac

sandbox_guard "$SB"    "$BASE" "the sandbox HOME"
sandbox_guard "$DIR"   "$BASE" "RECORD_DIR"
sandbox_guard "$NOTES" "$BASE" "RECORD_NOTES"

mkdir -p "$SB" "$DIR" "$VAULT/.obsidian" "$NOTES" "$TMP"
seed_recordings "$DIR"
make_stubs "$BIN"

out=$(run_transcribe "$ROOT" "$SB" "$BIN" "$TMP" "$DIR" "$VAULT" "$NOTES") && rc=0 || rc=$?

fail=0
bad() { echo "FAIL: $1"; fail=1; }

if [ "$rc" -ne 0 ]; then
  bad "record transcribe exited $rc against a RECORD_DIR containing a space"
fi

notes=$(find "$NOTES" -maxdepth 1 -name '*.md' | sort)
count=$(printf '%s' "$notes" | grep -c . || true)
if [ "$count" -ne 1 ]; then
  bad "expected exactly one note in $NOTES, found $count"
  printf '%s\n' "$out" | sed 's/^/      /'
else
  note="$notes"

  # The video list has to name the files that exist, in full. This is the
  # assertion the old bug fails: it wrote four half paths instead of two.
  for clip in "2026-01-02_09-00" "2026-01-02_10-00"; do
    line="- \`$DIR/$clip.mp4\`"
    grep -qF -e "$line" "$note" || bad "the note does not list $DIR/$clip.mp4 intact"
  done

  # Every listed video must be a file that is really there. A path that got
  # split shows up here even if the exact-line check above is ever relaxed.
  while IFS= read -r listed; do
    [ -f "$listed" ] || bad "the note lists '$listed', which does not exist"
  done < <(sed -n 's/^- `\(.*\)`$/\1/p' "$note")

  # Both clips went through the transcription loop, not just the first.
  for section in "2026-01-02 09-00" "2026-01-02 10-00"; do
    grep -qF "## $section" "$note" || bad "the note has no transcript section for $section"
  done

  grep -q 'Stub transcript for the test suite' "$note" \
    || bad "the note carries no transcript text"
fi

# A finished transcription clears its session marker, otherwise the next stop
# transcribes the same hours again.
[ -e "$DIR/.session" ] && bad "the session marker survived a successful transcription"

if [ "$fail" -ne 0 ]; then
  echo "transcribe_space_path: failed"
  exit 1
fi
echo "transcribe_space_path: ok"
