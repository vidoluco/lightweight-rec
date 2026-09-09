#!/bin/bash
# Rebuild the toolchain on a new Mac. Idempotent: running it again is safe.
#
#   ./install.sh                  everything this tool needs, and nothing else
#   ./install.sh --with-handy     also add Handy, an optional dictation app
#   ./install.sh --help           print this header
#
# The rule this script holds to: never overwrite a file it does not own, and
# never install something the tool can run without unless you asked for it. The
# Option+R binding goes into its own fragment and is wired into your skhd
# config with one .load line, and an existing skhdrc is copied to a timestamped
# .bak before a byte of it changes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_HANDY="${RECORD_INSTALL_HANDY:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --with-handy) WITH_HANDY=1 ;;
    # Accepted and ignored, so a note or a script written for 0.2 still runs:
    # since 0.3 the other side of a call is captured natively and there is no
    # driver to install.
    --with-blackhole) echo "BlackHole is no longer used: system audio is captured natively. Ignoring --with-blackhole." ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1"; echo "Usage: install.sh [--with-handy]"; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------- preflight
# Everything below assumes macOS, Homebrew, a Swift compiler and a writable
# ~/bin. Checking them here costs a second and turns four confusing late
# failures into one readable early one.
echo "== preflight =="
PREFLIGHT_OK=1
preflight_fail() {
  PREFLIGHT_OK=0
  echo "  FAIL: $1"
  shift
  for line in "$@"; do
    echo "        $line"
  done
}

ok_line() { printf '  %-10s %s\n' "$1" "$2"; }

if [ "$(uname -s)" = "Darwin" ]; then
  MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 0)"
  ok_line macOS "$MACOS_VERSION"
  # System audio comes from ScreenCaptureKit, which learned to capture audio
  # in macOS 13. record-audio.swift will not compile against an older SDK,
  # so say it here rather than as a compiler error halfway through.
  if [ "${MACOS_VERSION%%.*}" -lt 13 ] 2>/dev/null; then
    preflight_fail "macOS 13 or newer is needed: the system audio helper is built on ScreenCaptureKit." \
      "This Mac runs $MACOS_VERSION. Update macOS, then run this script again."
  fi
else
  preflight_fail "this tool is macOS only: it is built on avfoundation, CoreAudio and skhd." \
    "uname says $(uname -s). There is nothing here that runs on it."
fi

if command -v brew >/dev/null 2>&1; then
  ok_line brew "$(command -v brew)"
else
  preflight_fail "Homebrew is not on PATH: every dependency comes from it." \
    "Get it from https://brew.sh, then open a new shell so that" \
    "/opt/homebrew/bin (Apple silicon) or /usr/local/bin (Intel) is" \
    "on PATH, and run this script again."
fi

if command -v swiftc >/dev/null 2>&1; then
  ok_line swiftc "$(command -v swiftc)"
else
  preflight_fail "swiftc is missing: the red dot and the audio helper are Swift and get compiled here." \
    "Install the Xcode Command Line Tools, wait for them to finish," \
    "then run this script again:" \
    "  xcode-select --install"
fi

for tool in curl shasum; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok_line "$tool" "$(command -v "$tool")"
  else
    preflight_fail "$tool is missing: it ships with macOS, so something has been removed from PATH." \
      "The whisper model is fetched with curl and checked with shasum."
  fi
done

# Read-only test on purpose: preflight is allowed to fail, and a failing
# preflight must leave the disk exactly as it found it. ~/bin is created later.
if [ -d "$HOME/bin" ]; then
  if [ -w "$HOME/bin" ]; then
    ok_line bin "$HOME/bin (writable)"
  else
    preflight_fail "cannot write to $HOME/bin: the four executables live there." \
      "Fix its owner and permissions, then run this script again."
  fi
elif [ -w "$HOME" ]; then
  ok_line bin "$HOME/bin (will be created)"
else
  preflight_fail "cannot create $HOME/bin: $HOME itself is not writable." \
    "Fix its owner and permissions, then run this script again."
fi

if [ "$PREFLIGHT_OK" -ne 1 ]; then
  echo
  echo "Nothing was installed. Fix the lines above and run ./install.sh again."
  exit 1
fi

CONFIG="${RECORD_CONFIG:-$HOME/.config/record/config}"
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi
DIR="${RECORD_DIR:-$HOME/Recordings}"
VAULT="${RECORD_VAULT:-$HOME/Documents/Obsidian}"
NOTES="${RECORD_NOTES:-$VAULT/Recordings}"

# ------------------------------------------------------------ dependencies
echo "== brew dependencies =="
brew list ffmpeg      >/dev/null 2>&1 || brew install ffmpeg
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
brew list skhd        >/dev/null 2>&1 || brew install koekeishiya/formulae/skhd

echo "== Handy, optional and off by default =="
if [ "$WITH_HANDY" = "1" ]; then
  brew list --cask handy >/dev/null 2>&1 || brew install --cask handy
  echo "  installed. Set RECORD_LAUNCH_APP=\"Handy\" in your config if you want"
  echo "  Option+R to bring it up with the recording."
else
  echo "  skipped. Handy is a separate push-to-talk dictation app by another"
  echo "  author: it captures, transcribes and files nothing for this tool, and"
  echo "  nothing here needs it. Add it with:"
  echo "    ./install.sh --with-handy      (or RECORD_INSTALL_HANDY=1 ./install.sh)"
fi

echo "== system audio helper (record-audio) =="
mkdir -p "$HOME/bin"
swiftc -O -o "$HOME/bin/record-audio" "$HERE/record-audio.swift" \
  -framework ScreenCaptureKit -framework CoreMedia -framework CoreAudio

# Versions up to 0.2 recorded system audio through BlackHole and two aggregate
# devices, Record-In and Record-Out, and could leave the Mac's output switched
# to one of them after a crash. One pass with the new helper removes both and
# puts the output back where the old state file says it was. Nothing to do on
# a fresh Mac, and it says nothing then.
PREVIOUS_OUTPUT=""
[ -f "$DIR/.previous-output" ] && PREVIOUS_OUTPUT="$(cat "$DIR/.previous-output")"
if [ -n "$PREVIOUS_OUTPUT" ]; then
  "$HOME/bin/record-audio" down "$PREVIOUS_OUTPUT" 2>&1 | sed 's/^/  /' || true
  echo "  sound output asked back to \"$PREVIOUS_OUTPUT\", where 0.2 left it"
else
  "$HOME/bin/record-audio" down 2>&1 | sed 's/^/  /' || true
fi
rm -f "$DIR/.previous-output"
if brew list --cask blackhole-2ch >/dev/null 2>&1; then
  echo "  BlackHole 2ch is installed and no longer used by this tool. If nothing"
  echo "  else needs it:  brew uninstall --cask blackhole-2ch"
fi

echo "== recording-dot overlay (record-dot) =="
swiftc -O -o "$HOME/bin/record-dot" "$HERE/record-dot.swift" -framework AppKit

echo "== scripts in ~/bin =="
cp "$HERE/record" "$HOME/bin/record"
cp "$HERE/record-lib.sh" "$HOME/bin/record-lib.sh"
chmod +x "$HOME/bin/record" "$HOME/bin/record-lib.sh"
grep -q 'HOME/bin' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"

echo "== local config =="
mkdir -p "$HOME/.config/record"
if [ ! -f "$CONFIG" ]; then
  cp "$HERE/config.example" "$CONFIG"
  echo "Wrote $CONFIG (edit it to point at your vault)."
else
  echo "Keeping existing $CONFIG"
fi

# ------------------------------------------------------------------- skhd
# skhd's dominant use is next to yabai, where ~/.config/skhd/skhdrc is a large
# hand-tuned keymap. Copying our file over it, which older versions of this
# script did, wipes every window-management hotkey the user has. So: our
# binding lives in its own fragment, and the only thing that ever reaches the
# user's skhdrc is one .load line, appended after a backup.
echo "== Option+R hotkey (skhd) =="
SKHD_DIR="$HOME/.config/skhd"
SKHDRC="$SKHD_DIR/skhdrc"
FRAGMENT="$SKHD_DIR/lightweight-rec.skhdrc"
# skhd reads the .load argument as a literal path. No shell runs over it, so
# neither $HOME nor ~ would expand: the absolute path has to be written out.
LOAD_LINE=".load \"$FRAGMENT\""
# Recognises the Option+R binding in either form: the current fragment quotes
# the path ("$HOME/bin/record" toggle) so a home directory with a space does
# not word split, and installs from before that change wrote it bare
# ($HOME/bin/record toggle). Both must be detected, or an uninstall would
# leave a legacy binding behind pointing at a deleted file.
BINDING_RE='record"?[[:space:]]+toggle'
mkdir -p "$SKHD_DIR"

timestamped_backup() {
  local target="$1"
  local backup
  backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$target" "$backup"
  echo "  backed up $target to $backup"
}

# Numbered lines of a config that bind alt - r, whatever else sits on them.
# A mode prefix ("default < alt - r") is stripped before matching; a line that
# also names another modifier ("cmd + alt - r") is a different hotkey and no
# clash at all, so it must not match. After the key skhd wants one of ':'
# (command), '[' (per-app), ';' (mode switch), optionally behind '->'.
alt_r_lines() {
  grep -nE '^[[:space:]]*([A-Za-z0-9_]+[[:space:]]*<[[:space:]]*)?(l|r)?alt[[:space:]]*-[[:space:]]*r[[:space:]]*(->[[:space:]]*)?(:|\[|;)' "$1" || true
}

# Lines of a config that are neither blank, nor a comment, nor our binding.
# Same test scripts/uninstall.sh uses to decide whether a skhdrc is ours.
foreign_lines() {
  grep -vE '^[[:space:]]*(#|$)' "$1" | grep -vE "$BINDING_RE" || true
}

# The fragment carries our name, so it is ours to overwrite, but an edited one
# is still somebody's work: keep a copy before replacing it.
if [ -f "$FRAGMENT" ] && ! cmp -s "$HERE/skhdrc" "$FRAGMENT"; then
  timestamped_backup "$FRAGMENT"
fi
cp "$HERE/skhdrc" "$FRAGMENT"
echo "  binding written to $FRAGMENT"

CLASH=""
OURS_INLINE=""
if [ -f "$SKHDRC" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *) if printf '%s' "$line" | grep -qE "$BINDING_RE"; then
           OURS_INLINE="$OURS_INLINE$line"$'\n'
         else
           CLASH="$CLASH$line"$'\n'
         fi ;;
    esac
  done < <(alt_r_lines "$SKHDRC")
fi

if [ ! -f "$SKHDRC" ]; then
  {
    echo "# skhd config."
    echo "#"
    echo "# Yours to fill. lightweight-rec keeps its own hotkey in the file"
    echo "# named on the load line below, so that whatever you add here stays"
    echo "# yours and an upgrade never rewrites it."
    echo
    echo "$LOAD_LINE"
  } > "$SKHDRC"
  echo "  wrote $SKHDRC, which loads the fragment"

elif grep -qxF "$LOAD_LINE" "$SKHDRC"; then
  echo "  $SKHDRC already loads the fragment: nothing to change"
  if [ -n "$CLASH" ]; then
    # Both configs bind alt - r, so skhd honours one of them and the other is
    # dead. Saying "nothing to change" and stopping there would leave somebody
    # hunting a hotkey that quietly does the wrong thing.
    echo "  WARNING: it also binds alt - r itself, which shadows ours:"
    printf '%s' "$CLASH" | sed 's/^/    /'
    echo "  Remove one of the two, then: skhd --reload"
  fi

elif [ -n "$CLASH" ]; then
  echo "  WARNING: alt - r is already bound in $SKHDRC, to something that is not ours:"
  printf '%s' "$CLASH" | sed 's/^/    /'
  echo "  Left alone. Silently stealing a key you bound yourself would be worse"
  echo "  than shipping without a hotkey. Two ways out, both one edit long:"
  echo "    a. free alt - r in $SKHDRC, then append this line to it:"
  echo "         $LOAD_LINE"
  echo "    b. change the key in $FRAGMENT, then append the same line."
  echo "  Reload afterwards with: skhd --reload"
  echo "  Until then, start and stop from a terminal with: record toggle"

elif [ -n "$OURS_INLINE" ]; then
  # An older version of this script copied its skhdrc straight over the user's.
  # The binding it left behind still works, so nothing here is urgent.
  if [ -z "$(foreign_lines "$SKHDRC")" ]; then
    timestamped_backup "$SKHDRC"
    {
      echo "# skhd config."
      echo "#"
      echo "# The Option+R binding moved out of this file and into the fragment"
      echo "# named below, so that anything you add here survives an upgrade."
      echo
      echo "$LOAD_LINE"
    } > "$SKHDRC"
    echo "  migrated $SKHDRC: the inline binding became the load line above"
  else
    echo "  NOTE: $SKHDRC binds alt - r to this tool inline, the old way:"
    printf '%s' "$OURS_INLINE" | sed 's/^/    /'
    echo "  Option+R keeps working, so this is left as it is: the rest of that"
    echo "  file is your own keymap. To move to the fragment, delete that line"
    echo "  and append:"
    echo "    $LOAD_LINE"
  fi

else
  timestamped_backup "$SKHDRC"
  {
    echo
    echo "# lightweight-rec: Option+R toggles recording. The binding itself is"
    echo "# in the file below, not in here."
    echo "$LOAD_LINE"
  } >> "$SKHDRC"
  echo "  appended the load line to $SKHDRC"
fi

# ------------------------------------------------------------ whisper model
echo "== whisper model (large-v3-turbo, ~574 MB) =="
MODEL="$DIR/.whisper/ggml-large-v3-turbo-q5_0.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
MODEL_BYTES=574041195
# SHA-256 of that exact file. Neither invented nor copied off a blog: read on
# 2026-08-27 from the HuggingFace repo metadata for ggerganov/whisper.cpp
# (api/models/ggerganov/whisper.cpp?blobs=true, field siblings[].lfs.sha256,
# the digest git-lfs stores for the blob) and independently recomputed with
# shasum -a 256 over a copy downloaded earlier. The two agreed, byte count
# included. If upstream ever republishes the file, refresh this constant the
# same way, from both sources, never from one.
MODEL_SHA256=394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2

file_bytes() {
  stat -f%z "$1" 2>/dev/null || echo 0
}

if [ -f "$MODEL" ]; then
  have=$(file_bytes "$MODEL")
  if [ "$have" = "$MODEL_BYTES" ]; then
    echo "  already there and the right size: $MODEL"
  else
    echo "  $MODEL is $have bytes, expected $MODEL_BYTES: an earlier download"
    echo "  was cut short. Fetching it again."
    rm -f "$MODEL"
  fi
fi

if [ ! -f "$MODEL" ]; then
  mkdir -p "$(dirname "$MODEL")"
  curl -L --fail --retry 3 --retry-delay 2 -o "$MODEL.part" "$MODEL_URL"
  got=$(file_bytes "$MODEL.part")
  if [ "$got" != "$MODEL_BYTES" ]; then
    rm -f "$MODEL.part"
    echo "FAIL: downloaded $got bytes, expected $MODEL_BYTES." >&2
    echo "      Nothing was put in place. Check the network and try again." >&2
    exit 1
  fi
  echo "  size ok, checking SHA-256 (a few seconds)"
  sum=$(shasum -a 256 "$MODEL.part" | awk '{print $1}')
  if [ "$sum" != "$MODEL_SHA256" ]; then
    rm -f "$MODEL.part"
    echo "FAIL: SHA-256 mismatch on the downloaded model." >&2
    echo "      expected $MODEL_SHA256" >&2
    echo "      got      $sum" >&2
    echo "      The file was deleted. Do not use it: either the download was" >&2
    echo "      tampered with in transit, or upstream republished the model and" >&2
    echo "      the constant in this script is stale." >&2
    exit 1
  fi
  mv "$MODEL.part" "$MODEL"
  echo "  verified and in place: $MODEL"
fi

# ---------------------------------------------------------------- skhd load
echo "== skhd service =="
SKHD_PID="/tmp/skhd_$(id -un).pid"
if [ -f "$SKHD_PID" ] && kill -0 "$(cat "$SKHD_PID" 2>/dev/null)" 2>/dev/null; then
  # Already running, possibly holding somebody's yabai keymap up. A reload
  # picks up the new load line without dropping a single other hotkey.
  if skhd --reload 2>/dev/null; then
    echo "  reloaded the running skhd: your other hotkeys never went down"
  else
    echo "  WARN: skhd is running but would not reload. Restart it yourself:"
    echo "        skhd --restart-service"
  fi
else
  if skhd --start-service 2>/dev/null; then
    echo "  started"
  else
    echo "  WARN: could not start the skhd service. Start it yourself:"
    echo "        skhd --start-service"
  fi
fi

echo
echo "Done. Remaining permissions, once (System Settings > Privacy and Security):"
echo "  1. Accessibility      -> $(command -v skhd || echo skhd)"
echo "  2. Screen Recording   -> skhd (macOS asks on the first Option+R; it also"
echo "                           covers the system audio capture, no extra grant)"
echo "  3. Microphone         -> skhd"
echo
echo "Defaults: videos in $DIR, notes in $NOTES"
echo "Edit $CONFIG to change paths, the display, the microphone, retention,"
echo "or the app Option+R brings up with the recording."
echo "The hotkey itself is in $FRAGMENT"
echo "List displays with: record screens"
echo "Check which microphone will be recorded with: record mic"

# The note is written whether or not a vault is there, and a folder full of
# Markdown that Obsidian never shows looks exactly like a tool that did not
# run. Obsidian marks a vault root with a .obsidian directory, so the check is
# cheap and certain. It is a warning, never a failure: plenty of people read
# these notes in a plain editor.
echo
if [ -d "$VAULT/.obsidian" ]; then
  echo "Obsidian vault found at $VAULT"
else
  echo "NOTE: $VAULT is not an Obsidian vault (no .obsidian directory in it)."
  echo "  Notes will still be written, to $NOTES, but Obsidian will not list"
  echo "  them until that folder sits inside a real vault. Point this tool at"
  echo "  yours by setting, in $CONFIG:"
  echo "    RECORD_VAULT=\"/path/to/your/vault\""
  echo "  Obsidian creates .obsidian in the vault root the first time it opens it."
fi
