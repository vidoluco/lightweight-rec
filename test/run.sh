#!/bin/bash
# Run every test/*.test.sh and report one line per test.
#
#   ./test/run.sh          from the repo root
#   test/run.sh            from anywhere: the root comes from BASH_SOURCE
#
# A test passes when it exits 0. Its output is shown only when it fails, so a
# green run stays readable. Exit status is 1 if any test failed.
#
# Machine-dependent tests are skipped, not failed. dot_onoff and dot_screens
# compile record-dot.swift and open an AppKit overlay: they need the Swift
# toolchain, a logged-in graphical session (WindowServer) and a display that is
# actually awake. On a headless CI box none of that exists, and a red build
# there would say nothing about the code.
#
# A test that needs an external program the tool itself depends on, such as the
# real ffmpeg, says so in a line of its own near the top:
#
#     # requires: ffmpeg ffprobe
#
# and is skipped where that program is absent. The runner reads the line; it
# never learns any test's name.
#
# Set RECORD_TEST_STRICT=1 to turn a skip into a failure.
# Set RECORD_TEST_VERBOSE=1 to print the output of passing tests too.
# Set RECORD_TEST_DISPLAY_PROBE to another program that prints a count of
#   active displays, to exercise both sides of the display gate on a machine
#   whose own screen will not cooperate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STRICT="${RECORD_TEST_STRICT:-0}"
VERBOSE="${RECORD_TEST_VERBOSE:-0}"

# Counts the displays CoreGraphics calls active. Its own tiny Swift probe, not
# the record-dot binary the overlay tests are checking: if the thing under test
# answered this question, a broken record-dot would report "no display" and
# skip the tests that exist to catch it.
DISPLAY_PROBE="${RECORD_TEST_DISPLAY_PROBE:-$ROOT/test/lib/active-displays.sh}"

# Why a test cannot run here. Empty output means it can.
skip_reason() {
  local file="$1" active req tool
  # Declared dependencies first: cheap, and unlike the display probe below it
  # needs nothing of the machine but PATH.
  req=$(sed -n 's/^#[[:space:]]*requires:[[:space:]]*//p' "$file" | head -1)
  if [ -n "$req" ]; then
    # Deliberate word split: the line is a space-separated list of programs.
    # shellcheck disable=SC2086
    for tool in $req; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool is not on PATH"
        return 0
      fi
    done
  fi
  # Only the tests that build a Swift binary need a toolchain and a GUI.
  # Detecting that from the file keeps the runner out of the business of
  # knowing test names.
  if grep -q 'swiftc' "$file"; then
    command -v swiftc >/dev/null 2>&1 || { echo "swiftc not found (Xcode command line tools)"; return 0; }
    if [ "$(uname -s)" != "Darwin" ]; then
      echo "needs macOS AppKit"
      return 0
    fi
    if [ "$(launchctl managername 2>/dev/null || echo unknown)" != "Aqua" ]; then
      echo "no graphical session (launchctl managername is not Aqua)"
      return 0
    fi
    # managername stays Aqua with the lid shut and the screen asleep, and no
    # overlay can be drawn then: CGGetActiveDisplayList returns 0 for a display
    # that is merely online. That state used to be reported as two failing
    # tests on a machine whose code was fine, which is the same lie as a silent
    # pass. Ask CoreGraphics rather than infer.
    if active=$("$DISPLAY_PROBE" 2>/dev/null) && [ "$active" = "0" ]; then
      echo "no active display (every display is asleep or detached)"
      return 0
    fi
    # A probe that could not answer is not a reason to skip. The test runs and
    # is allowed to fail out loud: unknown must never be read as "no display",
    # or a real overlay bug would hide behind a SKIP forever.
  fi
  echo ""
}

shopt -s nullglob
tests=(test/*.test.sh)
shopt -u nullglob

if [ "${#tests[@]}" -eq 0 ]; then
  echo "No test found in $ROOT/test"
  exit 1
fi

passed=0
failed=0
skipped=0
failed_names=()

for t in "${tests[@]}"; do
  name="$(basename "$t")"
  reason="$(skip_reason "$t")"

  if [ -n "$reason" ] && [ "$STRICT" != "1" ]; then
    printf 'SKIP  %-28s %s\n' "$name" "$reason"
    skipped=$((skipped + 1))
    continue
  fi

  start=$SECONDS
  if out=$(bash "$t" 2>&1); then
    printf 'PASS  %-28s %ss\n' "$name" "$((SECONDS - start))"
    passed=$((passed + 1))
    if [ "$VERBOSE" = "1" ] && [ -n "$out" ]; then
      printf '%s\n' "$out" | sed 's/^/      /'
    fi
  else
    rc=$?
    printf 'FAIL  %-28s exit %s\n' "$name" "$rc"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/      /'
    failed=$((failed + 1))
    failed_names+=("$name")
  fi
done

echo
echo "${#tests[@]} tests: $passed passed, $failed failed, $skipped skipped"

if [ "$failed" -ne 0 ]; then
  echo "Failed: ${failed_names[*]}"
  exit 1
fi
