#!/bin/bash
# requires: ffmpeg ffprobe
#
# Break this would catch: one unreadable segment throwing away a whole day of
# transcription and writing no note at all.
#
# A forced shutdown, a dead battery or a pulled power cable leaves the last mp4
# without its moov atom: ffmpeg cannot open it. That call sat unguarded inside
# the transcribe loop, under `set -euo pipefail`, so the failure ended the
# background run on the spot. Every hour already transcribed went with it, the
# vault got nothing, and the only trace was a single "moov atom not found" line
# in .transcribe.log, a file the README never asks anybody to open. The user
# saw a recording on disk and no note, with no way to connect the two.
#
# The fixtures are real, because a stub ffmpeg cannot fail the way ffmpeg
# fails: one genuinely encoded mp4, and one truncated to its first bytes, which
# is the exact shape an interrupted recording leaves behind. whisper-cli and
# claude stay stubbed: the real ones load a multi-gigabyte model and bill an
# Anthropic account.
#
# Both orders are exercised. Bad file second proves the skip; bad file FIRST is
# the case that used to lose everything, and there the assertion that matters
# is that the good hour still reaches the note.
#
# Nothing real is touched: a throwaway HOME under TMPDIR, `env -i` so the
# caller's RECORD_* variables and ~/.config/record/config cannot reach the run,
# and a hard stop before the first byte is written if any path is not inside
# the sandbox.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

for tool in ffmpeg ffprobe; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FAIL: $tool is not on PATH, and this test needs the real one: a stub"
    echo "      cannot reproduce the decode failure it is about."
    exit 1
  }
done

BASE=$(sandbox_base bad-segment)
trap 'rm -rf "$BASE"' EXIT

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# A second of real video and real audio in a real container. Small, but every
# box ffmpeg needs is there, so the good clip is decoded by the same code path
# that decodes an hour of a meeting.
make_good_clip() {
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "testsrc=size=64x48:rate=5:duration=1" \
    -f lavfi -i "sine=frequency=440:duration=1" \
    -c:v mpeg4 -c:a aac -shortest "$1"
}

# What a recording interrupted mid-write looks like: the header is there, the
# moov atom the player needs is not.
make_bad_clip() {
  local src="$1" out="$2"
  head -c 200 "$src" > "$out"
  printf 'interrupted before the moov atom was written\n' >> "$out"
}

# One end-to-end run. $1 a label, $2 the stamp of the clip that decodes, $3 the
# stamp of the clip that does not. Ordering is by filename, which is what
# `find | sort` gives record, so the stamps decide who comes first.
run_case() {
  local label="$1" good_stamp="$2" bad_stamp="$3"
  local sb dir vault notes bin tmp out rc note notes_found count

  sb="$BASE/$label"
  dir="$sb/Recordings"
  vault="$sb/Documents/Notebook"
  notes="$vault/Recordings"
  bin="$sb/bin"
  tmp="$sb/tmp"

  # Before anything is created, let alone deleted. HOME and RECORD_DIR are the
  # two the run writes through, so both are proved to be inside the sandbox and
  # outside the real home, and the whole test dies if either is not.
  sandbox_guard "$sb"    "$BASE" "the sandbox HOME"
  sandbox_guard "$dir"   "$BASE" "RECORD_DIR"
  sandbox_guard "$notes" "$BASE" "RECORD_NOTES"

  mkdir -p "$dir/.whisper" "$vault/.obsidian" "$notes" "$tmp"
  printf 'not a real whisper model\n' > "$dir/.whisper/ggml-large-v3-turbo-q5_0.bin"

  make_good_clip "$dir/$good_stamp.mp4"
  make_bad_clip  "$dir/$good_stamp.mp4" "$dir/$bad_stamp.mp4"

  # The fixtures are the test. A "bad" clip that ffmpeg happens to decode, or a
  # "good" one it does not, would turn this file green while proving nothing.
  if ! ffmpeg -y -hide_banner -loglevel error -i "$dir/$good_stamp.mp4" \
       -ar 16000 -ac 1 "$tmp/probe.wav" >/dev/null 2>&1; then
    echo "FAIL: $label: the fixture meant to decode does not decode"; exit 1
  fi
  rm -f "$tmp/probe.wav"
  if ffmpeg -y -hide_banner -loglevel error -i "$dir/$bad_stamp.mp4" \
       -ar 16000 -ac 1 "$tmp/probe.wav" >/dev/null 2>&1; then
    echo "FAIL: $label: the fixture meant to be undecodable decoded fine"; exit 1
  fi
  rm -f "$tmp/probe.wav"

  # Older than both clips: `find -newer` is how record picks up the session.
  touch -t 202601010000 "$dir/.session"

  # whisper-cli, claude and osascript stubbed; ffmpeg and ffprobe are the real
  # ones, because the whole point is a real decode failure.
  make_stubs "$bin"
  rm -f "$bin/ffmpeg" "$bin/ffprobe"
  ln -s "$(command -v ffmpeg)"  "$bin/ffmpeg"
  ln -s "$(command -v ffprobe)" "$bin/ffprobe"

  out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes") && rc=0 || rc=$?

  # 1. The run survives the bad file. This is the regression itself: it used to
  #    exit non-zero here, from set -e, with nothing written.
  if [ "$rc" -ne 0 ]; then
    bad "$label: record transcribe exited $rc on an undecodable segment"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi

  # 2. A note exists at all. The old failure wrote none.
  notes_found=$(find "$notes" -maxdepth 1 -name '*.md' | sort)
  count=$(printf '%s' "$notes_found" | grep -c . || true)
  if [ "$count" -ne 1 ]; then
    bad "$label: expected exactly one note in $notes, found $count"
    printf '%s\n' "$out" | sed 's/^/      /'
    return
  fi
  note="$notes_found"

  # 3. The hour that could be transcribed is in the note, with its text. When
  #    the bad file comes first this is the assertion that used to be
  #    impossible: everything after the failure was thrown away.
  grep -qF "## $(printf '%s' "$good_stamp" | tr '_' ' ')" "$note" \
    || bad "$label: the note has no transcript section for the readable clip $good_stamp"
  grep -q 'Stub transcript for the test suite' "$note" \
    || bad "$label: the note carries no transcript text for the readable clip"

  # 4. The hour that could not be transcribed is named, not silently dropped.
  #    A note that is missing an hour without saying so is worse than no note.
  grep -qF '**Not transcribed**' "$note" \
    || bad "$label: the note has no 'Not transcribed' section"
  grep -qF "$dir/$bad_stamp.mp4" "$note" \
    || bad "$label: the 'Not transcribed' section does not name $bad_stamp.mp4"

  # 5. And it is named there rather than pretending to have a transcript.
  if grep -qF "## $(printf '%s' "$bad_stamp" | tr '_' ' ')" "$note"; then
    bad "$label: the undecodable clip got a transcript section of its own"
  fi

  # 6. Both clips are still listed as video on disk: the file is unreadable,
  #    it has not stopped existing.
  for stamp in "$good_stamp" "$bad_stamp"; do
    grep -qF -e "- \`$dir/$stamp.mp4\`" "$note" \
      || bad "$label: the note does not list $dir/$stamp.mp4"
  done

  # 7. The run says out loud which file it skipped, so .transcribe.log is
  #    readable by whoever goes looking.
  printf '%s\n' "$out" | grep -qF "Skipped $bad_stamp.mp4" \
    || bad "$label: the output does not report skipping $bad_stamp.mp4"

  # 8. A finished transcription clears its marker. Leaving it would transcribe
  #    the same hours, and fail on the same file, on every later stop.
  if [ -e "$dir/.session" ]; then
    bad "$label: the session marker survived the run"
  fi
}

# The bad hour comes last: the skip is visible and everything before it was
# already in hand.
run_case bad-second 2026-01-02_09-00 2026-01-02_10-00

# The bad hour comes first, which is the real-world case (the interrupted
# segment is usually the newest, but a machine that dies twice reorders that)
# and the one the old code could not survive: it died before the readable hour
# was ever opened.
run_case bad-first 2026-01-02_09-00 2026-01-02_08-00

if [ "$fail" -ne 0 ]; then
  echo "transcribe_bad_segment: failed"
  exit 1
fi
echo "transcribe_bad_segment: ok"
