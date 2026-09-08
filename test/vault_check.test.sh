#!/bin/bash
# Break this would catch: the note being filed somewhere Obsidian will never
# list it, with nothing said about it. RECORD_NOTES defaults to
# ~/Documents/Obsidian/Recordings, and mkdir -p is happy to invent that folder
# on a Mac that has no vault there at all. The run then reports success and the
# user goes looking in Obsidian for a note that is sitting in a plain folder.
#
# Two branches, both asserted, and the same invariant in both: the note is
# written. A vault check that ever refuses to write is worse than the bug it
# replaces, because the transcript is gone and the video is deleted in 14 days.
#   .obsidian present -> note, no warning
#   .obsidian absent  -> note, and a warning that names the problem
#
# The sandbox vault is called "Notebook" on purpose: a path containing the word
# vault or obsidian would satisfy the "no warning" check on its own.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base vcheck)
trap 'rm -rf "$BASE"' EXIT

# The "no warning" branch below asserts that nothing in the output mentions a
# vault, and record prints the note's path. A sandbox path carrying any of
# those words would make that assertion match itself and never fail again.
if printf '%s\n' "$BASE" | grep -qiE 'warning|vault|obsidian'; then
  echo "FAIL: the sandbox path '$BASE' contains a word this test greps for"
  exit 1
fi

fail=0
bad() { echo "FAIL: $1"; fail=1; }

OUT=""
NOTE=""
RC=0

# Builds a fresh sandbox, optionally marking the notes folder's ancestor as a
# vault, and runs a transcription in it. Sets OUT, RC and NOTE.
transcribe_into() {
  local label="$1" with_vault="$2"
  local sb dir vault notes bin tmp notes_found count

  sb="$BASE/$label"
  dir="$sb/Recordings"
  vault="$sb/Documents/Notebook"
  notes="$vault/Recordings"
  bin="$sb/bin"
  tmp="$sb/tmp"

  # Same reason as the guard on $BASE: a scenario name containing one of the
  # words the assertions grep for would defeat them.
  if printf '%s\n' "$sb" | grep -qiE 'warning|vault|obsidian'; then
    echo "FAIL: the scenario path '$sb' contains a word this test greps for"
    exit 1
  fi

  sandbox_guard "$sb"    "$BASE" "the sandbox HOME"
  sandbox_guard "$dir"   "$BASE" "RECORD_DIR"
  sandbox_guard "$notes" "$BASE" "RECORD_NOTES"

  mkdir -p "$sb" "$dir" "$notes" "$tmp"
  # The one difference between the two scenarios.
  [ "$with_vault" = "yes" ] && mkdir -p "$vault/.obsidian"

  seed_recordings "$dir"
  make_stubs "$bin"

  OUT=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes") && RC=0 || RC=$?

  NOTE=""
  notes_found=$(find "$notes" -maxdepth 1 -name '*.md' | sort)
  count=$(printf '%s' "$notes_found" | grep -c . || true)
  if [ "$count" -eq 1 ]; then
    NOTE="$notes_found"
  else
    bad "[$label] expected exactly one note in $notes, found $count"
  fi
}

# The invariant that outranks the warning: whatever the vault check decides,
# the transcription reaches disk in full.
assert_note_kept() {
  local label="$1"
  [ "$RC" -eq 0 ] || bad "[$label] record transcribe exited $RC"
  [ -n "$NOTE" ] || return 0
  grep -q 'Stub transcript for the test suite' "$NOTE" \
    || bad "[$label] the note was written without its transcript"
  grep -qF -e '- `' "$NOTE" \
    || bad "[$label] the note lists no video file"
}

# ---------------------------------------------------------------- a real vault
transcribe_into marked yes
assert_note_kept marked
if printf '%s\n' "$OUT" | grep -qiE 'warning|vault|obsidian'; then
  bad "a note filed inside a vault was warned about anyway:"
  printf '%s\n' "$OUT" | sed 's/^/      /'
fi

# ------------------------------------------------------------- no vault at all
transcribe_into unmarked no
assert_note_kept unmarked
# Deliberately a family of words, not one exact string. The message has to
# read as a complaint rather than a description, but nobody should have to
# come back here to reword it.
if ! printf '%s\n' "$OUT" | grep -qiE 'warn|outside|not inside'; then
  bad "a note filed outside any vault produced no warning:"
  printf '%s\n' "$OUT" | sed 's/^/      /'
fi
if ! printf '%s\n' "$OUT" | grep -qiE 'vault|obsidian'; then
  bad "the warning does not say what is wrong (no mention of a vault):"
  printf '%s\n' "$OUT" | sed 's/^/      /'
fi
# A warning that does not name the folder leaves the user hunting for the note.
if [ -n "$NOTE" ] && ! grep -qF -e "$(dirname "$NOTE")" <<< "$OUT"; then
  bad "the warning does not name the folder the note was written to:"
  printf '%s\n' "$OUT" | sed 's/^/      /'
fi

if [ "$fail" -ne 0 ]; then
  echo "vault_check: failed"
  exit 1
fi
echo "vault_check: ok"
