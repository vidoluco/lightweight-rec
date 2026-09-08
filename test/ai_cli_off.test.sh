#!/bin/bash
# Break this would catch: a note without a summary that does not say why, or
# an off switch that still makes a call.
#
# Four different things can leave a note with the generic title, and the reader
# has to be able to tell them apart from the note alone: RECORD_AI=0 (a
# choice), a value that names no known CLI (a typo), a CLI that is not
# installed, and a CLI that is installed and answered nothing, typically
# because it was asked for a model it does not carry. The first three must
# make no call at all; the last must leave what the CLI said in the log.
# RECORD_CLAUDE=0, the switch's old name, has to keep meaning off: a config
# written for an earlier release must not start uploading frames on upgrade.
#
# Nothing real is touched: a throwaway HOME under TMPDIR, `env -i` so the
# caller's RECORD_* variables and ~/.config/record/config cannot reach the run,
# and stubs that refuse any path under the real HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base ai-off)
trap 'rm -rf "$BASE"' EXIT

fail=0
bad() { echo "FAIL: $1"; fail=1; }

prepare() {
  local label="$1"
  sb="$BASE/$label"
  dir="$sb/Recordings"
  vault="$sb/Documents/Notebook"
  notes="$vault/Recordings"
  bin="$sb/bin"
  tmp="$sb/tmp"
  argv="$sb/argv.txt"
  sandbox_guard "$sb"    "$BASE" "the sandbox HOME"
  sandbox_guard "$dir"   "$BASE" "RECORD_DIR"
  sandbox_guard "$notes" "$BASE" "RECORD_NOTES"
  mkdir -p "$dir" "$vault/.obsidian" "$notes" "$tmp"
  make_stubs "$bin"
  seed_recordings "$dir"
}

the_note() {
  find "$1" -maxdepth 1 -name '*.md' | head -1
}

# What every case below has in common: the run succeeds, one note exists,
# it carries the generic title and no screen section, and the stubs were not
# called. $1 is the label, $2 the phrase the note must use to say why.
expect_raw_note() {
  local label="$1" why="$2"
  [ "$rc" -eq 0 ] || { bad "$label: record transcribe exited $rc"; printf '%s\n' "$out" | sed 's/^/      /'; }
  note=$(the_note "$notes")
  [ -n "$note" ] || { bad "$label: no note written"; return; }
  grep -q '^# Recorded session' "$note" || bad "$label: the note has a title it should not have"
  if grep -q '^## What was on screen' "$note"; then
    bad "$label: the note has a screen section"
  fi
  grep -qF -- "$why" "$note" || bad "$label: the note does not say '$why'"
  grep -q 'Stub transcript for the test suite' "$note" || bad "$label: the transcript is missing from the note"
}

# ---------------------------------------------------------------- RECORD_AI=0
prepare off
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=0 RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
expect_raw_note off 'RECORD_AI is off'
[ ! -e "$argv" ] || bad "off: a CLI was called with RECORD_AI=0"
# Off means no frames either: nothing of the screen is written even to scratch.
printf '%s\n' "$out" | grep -q 'RECORD_AI is off' || bad "off: the run does not say the switch is off"

# ------------------------------------------------------- RECORD_CLAUDE=0 alias
prepare alias
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_CLAUDE=0 RECORD_AI=cursor RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
expect_raw_note alias 'RECORD_AI is off'
[ ! -e "$argv" ] || bad "alias: RECORD_CLAUDE=0 no longer turns the call off"

# --------------------------------------------------------------- unknown name
prepare bogus
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=bogus RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
expect_raw_note bogus 'not claude, cursor or copilot'
grep -qF '`bogus`' "$note" || bad "bogus: the note does not quote the value that was set"
[ ! -e "$argv" ] || bad "bogus: a CLI was called for an unknown name"
printf '%s\n' "$out" | grep -q 'RECORD_AI is "bogus"' || bad "bogus: the run does not name the bad value"

# ------------------------------------------------------------- not installed
prepare missing
rm -f "$bin/copilot"
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=copilot RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
expect_raw_note missing 'the `copilot` CLI'
grep -q 'is not installed' "$note" || bad "missing: the note does not say the CLI is not installed"
[ ! -e "$argv" ] || bad "missing: something was called although the binary is absent"

# ---------------------------------------------------- installed, no answer
# The CLI exists, is asked for a model it does not have, prints one line on
# stderr and nothing on stdout. That line has to survive into the run's
# output, which is .transcribe.log in real use, and the note has to point
# the reader at it rather than looking like a deliberate off.
prepare silent
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=cursor RECORD_TEST_AI_FAIL=cursor-grok-4.6-high RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
expect_raw_note silent 'did not answer'
grep -qF 'cursor-grok-4.6-high' "$note" || bad "silent: the note does not name the model that was asked for"
grep -qF '.transcribe.log' "$note" || bad "silent: the note does not point at the log"
if grep -q 'RECORD_AI is off' "$note"; then
  bad "silent: a CLI that failed is reported as a deliberate off"
fi
printf '%s\n' "$out" | grep -q 'unknown model: cursor-grok-4.6-high' \
  || bad "silent: the CLI's own error line did not reach the log"
[ -e "$argv" ] || bad "silent: the CLI was never called"

if [ "$fail" -ne 0 ]; then
  echo "ai_cli_off: failed"
  exit 1
fi
echo "ai_cli_off: ok"
