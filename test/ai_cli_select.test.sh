#!/bin/bash
# Break this would catch: RECORD_AI naming one CLI and record driving another,
# or driving the right one with the wrong flags.
#
# Three CLIs can write the title, tags, summary and screen description, and
# each has its own headless grammar: claude reads the frames with its Read
# tool, cursor-agent opens them itself in ask mode inside a scratch workspace,
# copilot takes them as attachments with every tool switched off. A flag that
# drifts is not a visible failure: the CLI still answers something, the note
# still lands, and the only symptom is a bill for a call that read nothing, or
# an agent granted a shell it did not need. So the stubs write down every
# argument they were handed and this test reads the exact shape back.
#
# Nothing real is touched: a throwaway HOME under TMPDIR, `env -i` so the
# caller's RECORD_* variables and ~/.config/record/config cannot reach the run,
# and stubs that refuse any path under the real HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base ai-select)
trap 'rm -rf "$BASE"' EXIT

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# One sandbox per case. Prints nothing; sets sb, dir, vault, notes, bin, tmp,
# argv for the caller.
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

# The one note a run wrote, or an empty string.
the_note() {
  find "$1" -maxdepth 1 -name '*.md' | head -1
}

# How many calls a given stub saw.
calls_to() {
  grep -c -x -- "--- $1" "$2" 2>/dev/null || true
}

# True when the argument right after every `--model` in the file is $2.
model_is() {
  local file="$1" want="$2" got
  got=$(grep -A1 -x -- '--model' "$file" | grep -v -x -e '--model' -e '--' | sort -u)
  [ "$got" = "$want" ]
}

# ---------------------------------------------------------------- cursor
prepare cursor
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=cursor RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { bad "cursor: record transcribe exited $rc"; printf '%s\n' "$out" | sed 's/^/      /'; }
note=$(the_note "$notes")
[ -n "$note" ] || bad "cursor: no note written"

# Two clips, one screen call each, plus one metadata call: three, all to
# cursor-agent and none to anybody else.
[ "$(calls_to cursor-agent "$argv")" -eq 3 ] || bad "cursor: expected 3 cursor-agent calls, got $(calls_to cursor-agent "$argv")"
[ "$(calls_to copilot "$argv")" -eq 0 ] || bad "cursor: copilot was called"
# Read-only, in a workspace that is the scratch directory, with the default
# model. A cursor-agent without --mode ask has write and shell tools in print
# mode, which is exactly what a describe-the-screen call must never be given.
grep -A1 -x -- '--mode' "$argv" | grep -q -x -- 'ask' \
  || bad "cursor: the calls do not run in --mode ask"
grep -q -x -- '--workspace' "$argv" || bad "cursor: no --workspace given"
# The workspace is record's own scratch directory (macOS mktemp puts it under
# /var/folders whatever TMPDIR says), never the home or the recordings folder:
# ask mode can read anything inside it, so it must hold the frames and nothing
# else.
ws=$(grep -A1 -x -- '--workspace' "$argv" | grep -v -x -e '--workspace' -e '--' | head -1)
case "$ws" in
  */record-work.*/frames) ;;
  *) bad "cursor: the screen call's workspace '$ws' is not the frames scratch directory" ;;
esac
case "$ws" in
  "$REAL_HOME"|"$REAL_HOME"/*|"$dir"|"$dir"/*) bad "cursor: the workspace '$ws' reaches outside scratch" ;;
esac
model_is "$argv" cursor-grok-4.6-high || bad "cursor: default model is not cursor-grok-4.6-high on every call"
# The frames reach the prompt by path, in order, and the answer reaches the note.
grep -q 'k001.jpg' "$argv" || bad "cursor: the screen prompt does not name the frames"
grep -q '^# Stub session' "$note" || bad "cursor: the note did not take the stubbed title"
grep -q '^## What was on screen' "$note" || bad "cursor: the note has no screen section"
printf '%s\n' "$out" | grep -q 'AI: cursor (cursor-agent)' || bad "cursor: the run does not announce which CLI it uses"

# ---------------------------------------------------------------- copilot
prepare copilot
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=copilot RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { bad "copilot: record transcribe exited $rc"; printf '%s\n' "$out" | sed 's/^/      /'; }
note=$(the_note "$notes")
[ -n "$note" ] || bad "copilot: no note written"

[ "$(calls_to copilot "$argv")" -eq 3 ] || bad "copilot: expected 3 copilot calls, got $(calls_to copilot "$argv")"
[ "$(calls_to cursor-agent "$argv")" -eq 0 ] || bad "copilot: cursor-agent was called"
# The stub ffmpeg writes two frames per clip, so two clips are four
# attachments: one per frame, every frame, nothing else.
n_attach=$(grep -c -x -- '--attachment' "$argv" || true)
[ "$n_attach" -eq 4 ] || bad "copilot: expected 4 --attachment flags, got $n_attach"
grep -A1 -x -- '--attachment' "$argv" | grep -q 'k002.jpg' || bad "copilot: the attachments do not name the frames"
# No tools at all, no prompt for a human, no per-repo instructions, response only.
grep -q -x -- '--available-tools=' "$argv" || bad "copilot: tools were not switched off"
grep -q -x -- '--no-ask-user' "$argv" || bad "copilot: --no-ask-user missing"
grep -q -x -- '--no-custom-instructions' "$argv" || bad "copilot: --no-custom-instructions missing"
grep -q -x -- '-s' "$argv" || bad "copilot: -s (response only) missing"
model_is "$argv" gemini-3.8-flash || bad "copilot: default model is not gemini-3.8-flash on every call"
grep -q '^# Stub session' "$note" || bad "copilot: the note did not take the stubbed title"
grep -q '^## What was on screen' "$note" || bad "copilot: the note has no screen section"

# ---------------------------------------------------------------- overrides
# RECORD_AI_VISION_MODEL drives the screen calls, RECORD_AI_META_MODEL the one
# metadata call, and neither leaks into the other.
prepare override
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=copilot RECORD_AI_VISION_MODEL=see-this RECORD_AI_META_MODEL=name-this \
  RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "override: record transcribe exited $rc"
n_see=$(grep -c -x -- 'see-this' "$argv" || true)
n_name=$(grep -c -x -- 'name-this' "$argv" || true)
[ "$n_see" -eq 2 ] || bad "override: expected the vision model on 2 calls, saw it on $n_see"
[ "$n_name" -eq 1 ] || bad "override: expected the meta model on 1 call, saw it on $n_name"
# The call that carries the vision model is the one carrying attachments.
awk 'BEGIN{RS="--- copilot\n"} /see-this/ && !/--attachment/ {bad=1} END{exit bad}' "$argv" \
  || bad "override: the vision model was used on a call without attachments"

# ---------------------------------------------------------------- claude
# Nothing set: claude, sonnet for the frames, haiku for the metadata, exactly
# as before RECORD_AI existed. The claude stub records nothing, so the proof
# is the announcement line plus a note that took the stubbed answers.
prepare claude
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_TEST_ARGV="$argv") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "claude: record transcribe exited $rc"
note=$(the_note "$notes")
printf '%s\n' "$out" | grep -q 'AI: claude (claude), screen frames with sonnet, title and summary with haiku' \
  || bad "claude: the default announcement is wrong: $(printf '%s\n' "$out" | grep 'AI:' || echo none)"
[ ! -e "$argv" ] || bad "claude: another CLI was called: $(grep -- '^---' "$argv" | sort -u | tr '\n' ' ')"
grep -q '^# Stub session' "$note" || bad "claude: the note did not take the stubbed title"

if [ "$fail" -ne 0 ]; then
  echo "ai_cli_select: failed"
  exit 1
fi
echo "ai_cli_select: ok"
