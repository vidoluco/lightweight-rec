#!/bin/bash
# Break this would catch: the uninstaller deleting something it promised to
# keep. It is the only file in the repo that removes anything, it runs on a
# Mac that holds months of recordings, and one wrong path there is not
# recoverable from a backup nobody made.
#
# Everything happens inside a throwaway HOME under $TMPDIR. The real home is
# never passed to the script, and the run aborts before the first scenario if
# the sandbox is not clearly outside it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNINSTALL="$ROOT/scripts/uninstall.sh"
REAL_HOME="$HOME"

[ -x "$UNINSTALL" ] || { echo "FAIL: $UNINSTALL is missing or not executable"; exit 1; }

# The uninstaller stops the skhd service and switches the sound output when it
# finds those binaries. Handing it a PATH without them keeps a test run from
# touching the machine it runs on: it takes the "not on PATH" branch instead.
SAFE_PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Canary. If the real installation disappears during this run, something in
# here escaped the sandbox and the failure has to be loud.
REAL_BIN_BEFORE=0
if [ -e "$REAL_HOME/bin/record" ]; then REAL_BIN_BEFORE=1; fi

fail=0

# Every sandbox is a directory inside this one, so a single trap cleans them
# all up. Each is minted inside a command substitution, in a subshell whose
# variables never reach this one, which is why the list cannot be a variable.
BASE=$(mktemp -d "${TMPDIR:-/tmp}/record-uninstall-XXXXXX")
case "$BASE" in
  ""|/|"$REAL_HOME"|"$REAL_HOME"/*)
    echo "FAIL: refusing to run, the sandbox root '$BASE' is inside the real HOME"
    exit 1 ;;
esac
trap 'rm -rf "$BASE"' EXIT

bad() { echo "FAIL: $1"; fail=1; }

# A HOME with an installation in it, the data the uninstaller must not touch,
# and whatever skhdrc the scenario asks for.
make_sandbox() {
  local skhdrc_kind="$1" config="${2:-}"
  local sb
  sb=$(mktemp -d "$BASE/home-XXXXXX")

  # The one guard that matters: never run against the real home.
  case "$sb" in
    ""|/|"$REAL_HOME"|"$REAL_HOME"/*)
      echo "FAIL: refusing to run, the sandbox '$sb' is inside the real HOME"
      exit 1 ;;
  esac

  mkdir -p "$sb/bin" "$sb/Recordings" "$sb/Documents/Obsidian/Recordings" \
           "$sb/.config/skhd" "$sb/.config/record"
  # Installed files: what the uninstaller is allowed to remove. Not
  # record-audio, so it is never executed from a test.
  printf 'fake record\n'     > "$sb/bin/record"
  printf 'fake record-lib\n' > "$sb/bin/record-lib.sh"
  # Data: what it must keep.
  printf 'not a real mp4\n'  > "$sb/Recordings/2026-01-02-0900.mp4"
  printf '# a note\n'        > "$sb/Documents/Obsidian/Recordings/2026-01-02-0900.md"
  printf 'export PATH="$HOME/bin:$PATH"\n' > "$sb/.zshrc"

  case "$skhdrc_kind" in
    none) ;;
    comments-only)
      printf '# my keymap, parked for later\n#\n# alt - t : open -a Terminal\n' \
        > "$sb/.config/skhd/skhdrc" ;;
    foreign-only)
      printf 'alt - t : open -a Terminal\nalt - h : yabai -m window --focus west\n' \
        > "$sb/.config/skhd/skhdrc" ;;
    mixed)
      printf 'alt - t : open -a Terminal\nalt - r : $HOME/bin/record toggle\n' \
        > "$sb/.config/skhd/skhdrc" ;;
    ours-only)
      # A legacy installation: an older installer copied this file straight
      # over the user's skhdrc instead of loading it as a fragment.
      cp "$ROOT/skhdrc" "$sb/.config/skhd/skhdrc" ;;
    ours-only-legacy)
      # The same legacy installation, one generation older still: the binding
      # was written with the path unquoted, before a home directory with a
      # space in it was found to kill the hotkey. Those skhdrc files are on
      # real machines and nothing will ever rewrite them, so the uninstaller
      # has to keep recognising the old shape after the shipped one changed.
      sed 's|"$HOME/bin/record" toggle|$HOME/bin/record toggle|' "$ROOT/skhdrc" \
        > "$sb/.config/skhd/skhdrc"
      # The fixture is the test: a "legacy" file that quietly kept its quotes
      # would pass while proving nothing.
      grep -qE '^[[:space:]]*alt - r : \$HOME/bin/record toggle[[:space:]]*$' \
        "$sb/.config/skhd/skhdrc" \
        || { echo "FAIL: the legacy fixture is not in the old unquoted form" >&2; exit 1; } ;;
    load-line)
      # The layout install.sh writes now: our binding lives in its own
      # fragment and the user's own keymap only gains one .load line.
      cp "$ROOT/skhdrc" "$sb/.config/skhd/lightweight-rec.skhdrc"
      printf 'alt - h : yabai -m window --focus west\n.load "%s"\n' \
        "$sb/.config/skhd/lightweight-rec.skhdrc" > "$sb/.config/skhd/skhdrc" ;;
    *) echo "FAIL: unknown skhdrc kind '$skhdrc_kind'"; exit 1 ;;
  esac

  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$sb/.config/record/config"
  fi

  printf '%s' "$sb"
}

# Runs the uninstaller with the sandbox as its whole world. Output on stdout.
run_uninstall() {
  local sb="$1"
  case "$sb" in
    ""|/|"$REAL_HOME"|"$REAL_HOME"/*)
      echo "FAIL: refusing to run the uninstaller with HOME='$sb'"; exit 1 ;;
  esac
  env -i HOME="$sb" PATH="$SAFE_PATH" TMPDIR="${TMPDIR:-/tmp}" \
    bash "$UNINSTALL" --yes 2>&1
}

# No printed rm -rf may name the home directory or the vault root itself.
# Deeper paths are fine: those are the directories this tool owns.
assert_no_wide_rm() {
  local out="$1" sb="$2" vault="$3" scenario="$4" line arg
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    arg=${line#*rm -rf }
    arg=${arg%%#*}
    arg=$(printf '%s' "$arg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')
    case "$arg" in
      ""|/|"$sb"|"$sb/"|"$vault"|"$vault/")
        bad "$scenario: the output offers 'rm -rf' for '$arg'" ;;
    esac
  done <<< "$(printf '%s\n' "$out" | grep 'rm -rf' || true)"
}

# ---------------------------------------------------------------- scenarios

# 1. Recordings and notes survive, and the installed files really are removed
#    (without that second half the rest of this file would prove nothing).
sb=$(make_sandbox none)
out=$(run_uninstall "$sb") || bad "data: uninstaller exited non-zero"
[ -f "$sb/Recordings/2026-01-02-0900.mp4" ] \
  || bad "data: the recording was deleted"
[ -f "$sb/Documents/Obsidian/Recordings/2026-01-02-0900.md" ] \
  || bad "data: the note was deleted"
[ -d "$sb/Documents/Obsidian" ] || bad "data: the vault was deleted"
[ -f "$sb/.zshrc" ] || bad "data: ~/.zshrc was deleted"
if [ -e "$sb/bin/record" ]; then bad "data: the installed binary was left behind"; fi
if [ -e "$sb/bin/record-lib.sh" ]; then bad "data: the installed library was left behind"; fi
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "data"

# 2. A skhdrc with no binding of ours is not ours to touch, whether it holds
#    other people's hotkeys or nothing but comments.
for kind in comments-only foreign-only; do
  sb=$(make_sandbox "$kind")
  before=$(cat "$sb/.config/skhd/skhdrc")
  out=$(run_uninstall "$sb") || bad "$kind: uninstaller exited non-zero"
  [ -f "$sb/.config/skhd/skhdrc" ] || bad "$kind: skhdrc was removed"
  [ "$(cat "$sb/.config/skhd/skhdrc" 2>/dev/null || true)" = "$before" ] \
    || bad "$kind: skhdrc was modified"
  if ls "$sb/.config/skhd/"skhdrc.bak.* >/dev/null 2>&1; then
    bad "$kind: a backup was written for a config that was never removed"
  fi
  assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "$kind"
done

# 3. A skhdrc that carries our binding next to somebody else's stays, and the
#    reader is told which line to delete by hand.
sb=$(make_sandbox mixed)
before=$(cat "$sb/.config/skhd/skhdrc")
out=$(run_uninstall "$sb") || bad "mixed: uninstaller exited non-zero"
[ -f "$sb/.config/skhd/skhdrc" ] || bad "mixed: a foreign keymap was removed"
[ "$(cat "$sb/.config/skhd/skhdrc" 2>/dev/null || true)" = "$before" ] \
  || bad "mixed: a foreign keymap was modified"
printf '%s\n' "$out" | grep -q 'left alone' \
  || bad "mixed: the output does not say the skhd config was left alone"
printf '%s\n' "$out" | grep -q 'record toggle' \
  || bad "mixed: the output does not show the line to delete by hand"
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "mixed"

# 4. A skhdrc that holds nothing but our binding is ours: it goes, and a copy
#    stays next to it.
sb=$(make_sandbox ours-only)
before=$(cat "$sb/.config/skhd/skhdrc")
out=$(run_uninstall "$sb") || bad "ours-only: uninstaller exited non-zero"
if [ -e "$sb/.config/skhd/skhdrc" ]; then bad "ours-only: our own skhdrc was left behind"; fi
shopt -s nullglob
backups=("$sb/.config/skhd/"skhdrc.bak.*)
shopt -u nullglob
if [ "${#backups[@]}" -ne 1 ]; then
  bad "ours-only: expected exactly one .bak sibling, found ${#backups[@]}"
else
  [ "$(cat "${backups[0]}")" = "$before" ] \
    || bad "ours-only: the backup is not a copy of the removed file"
fi
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "ours-only"

# 5. The same file as scenario 4, written the way installs from before the
#    quoting fix wrote it: `alt - r : $HOME/bin/record toggle`, unquoted. The
#    shipped fragment no longer looks like that, and the pattern that finds it
#    was widened rather than moved, because an uninstaller that stops seeing
#    the old form leaves a dead hotkey pointing at a deleted binary.
sb=$(make_sandbox ours-only-legacy)
before=$(cat "$sb/.config/skhd/skhdrc")
out=$(run_uninstall "$sb") || bad "ours-only-legacy: uninstaller exited non-zero"
if [ -e "$sb/.config/skhd/skhdrc" ]; then
  bad "ours-only-legacy: an skhdrc holding only the old unquoted binding was left behind"
fi
shopt -s nullglob
backups=("$sb/.config/skhd/"skhdrc.bak.*)
shopt -u nullglob
if [ "${#backups[@]}" -ne 1 ]; then
  bad "ours-only-legacy: expected exactly one .bak sibling, found ${#backups[@]}"
else
  [ "$(cat "${backups[0]}")" = "$before" ] \
    || bad "ours-only-legacy: the backup is not a copy of the removed file"
fi
# Recognised as ours, so the reader is not sent off to edit a file that is
# already gone. Matched on the heading, not on the words "left alone": the
# report says that about the claude CLI too, in every run.
if printf '%s\n' "$out" | grep -qF 'your skhd config was left alone'; then
  bad "ours-only-legacy: the old binding was not recognised, the config was left alone"
fi
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "ours-only-legacy"

# 6. The dangerous configuration: recordings straight in the home directory and
#    notes straight in the vault root, both supported. No rm -rf may be printed
#    for either, or a reader pastes away their home or their whole vault.
sb=$(make_sandbox none 'RECORD_DIR="$HOME"
RECORD_VAULT="$HOME/Documents/Obsidian"
RECORD_NOTES="$HOME/Documents/Obsidian"')
out=$(run_uninstall "$sb") || bad "wide-paths: uninstaller exited non-zero"
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "wide-paths"
[ -f "$sb/Recordings/2026-01-02-0900.mp4" ] || bad "wide-paths: the recording was deleted"
[ -f "$sb/Documents/Obsidian/Recordings/2026-01-02-0900.md" ] || bad "wide-paths: the note was deleted"
printf '%s\n' "$out" | grep -q 'no rm -rf printed' \
  || bad "wide-paths: the safe fallback text is missing"

# 7. The layout the current installer writes: the user's keymap holds their
#    own hotkeys plus one .load line for our fragment. That file is theirs.
#    Only its survival and their hotkeys are asserted, not its exact bytes: an
#    uninstaller that learns to drop its own .load line is an improvement, one
#    that takes the whole keymap with it is the accident this file exists for.
sb=$(make_sandbox load-line)
out=$(run_uninstall "$sb") || bad "load-line: uninstaller exited non-zero"
[ -f "$sb/.config/skhd/skhdrc" ] || bad "load-line: the user's keymap was removed"
grep -q 'yabai' "$sb/.config/skhd/skhdrc" 2>/dev/null \
  || bad "load-line: the user's own hotkeys are gone from their keymap"
assert_no_wide_rm "$out" "$sb" "$sb/Documents/Obsidian" "load-line"

# ---------------------------------------------------------------- canary

if [ "$REAL_BIN_BEFORE" -eq 1 ] && [ ! -e "$REAL_HOME/bin/record" ]; then
  echo "FAIL: the real installation in $REAL_HOME/bin disappeared during this test"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "uninstall_safety: failed"
  exit 1
fi
echo "uninstall_safety: ok"
