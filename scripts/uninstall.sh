#!/bin/bash
# Undo install.sh on this Mac. The mirror of the installer and nothing more.
#
#   scripts/uninstall.sh         print the plan, then ask before removing
#   scripts/uninstall.sh --yes   do not ask
#
# Removed: the four files install.sh put in ~/bin, the skhd fragment holding
# the Option+R binding, and the single .load line the installer appended to
# your own skhd config.
#
# Never removed: your recordings, your notes, your Obsidian vault, the whisper
# model, your machine config, your other hotkeys, and the Homebrew packages.
# Their paths and the commands to remove them by hand are printed at the end.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1"; echo "Usage: uninstall.sh [--yes]"; exit 1 ;;
  esac
  shift
done

# Same resolution order as install.sh and record: the machine config decides
# where the videos and the notes live, so read it before naming any path.
CONFIG="${RECORD_CONFIG:-$HOME/.config/record/config}"
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi
DIR="${RECORD_DIR:-$HOME/Recordings}"
VAULT="${RECORD_VAULT:-$HOME/Documents/Obsidian}"
NOTES="${RECORD_NOTES:-$VAULT/Recordings}"
MODEL="$DIR/.whisper/ggml-large-v3-turbo-q5_0.bin"
BIN="$HOME/bin"
SKHD_DIR="$HOME/.config/skhd"
SKHDRC="$SKHD_DIR/skhdrc"
FRAGMENT="$SKHD_DIR/lightweight-rec.skhdrc"
# install.sh writes this line with the path spelled out, because skhd reads
# the .load argument literally and expands neither $HOME nor a tilde. The
# uninstaller has to look for the same absolute string.
LOAD_LINE=".load \"$FRAGMENT\""
# Recognises the Option+R binding in either form: the current fragment quotes
# the path ("$HOME/bin/record" toggle) so a home directory with a space does
# not word split, and installs from before that change wrote it bare
# ($HOME/bin/record toggle). Both must be detected, or an uninstall would
# leave a legacy binding behind pointing at a deleted file.
BINDING_RE='record"?[[:space:]]+toggle'
PATH_LINE='export PATH="$HOME/bin:$PATH"'

# True when a path is narrow enough that printing "rm -rf" for it is honest.
# Nothing in this script ever runs the command, it only offers the text, and
# the text is the dangerous part.
offer_rm_rf() {
  case "$1" in
    ""|/|"$HOME"|"$HOME/"|"$VAULT"|"$VAULT/") return 1 ;;
  esac
  return 0
}

# A live recording holds an unfinished mp4 and an unwritten note. Removing the
# binaries now would leave both behind with no way to finish them.
if { [ -f "$DIR/.record.pid" ] && kill -0 "$(cat "$DIR/.record.pid" 2>/dev/null)" 2>/dev/null; } \
  || pgrep -f "avfoundation.*$DIR" >/dev/null 2>&1; then
  echo "A recording is running."
  echo "Run 'record stop' first: it closes the video cleanly and files the note."
  exit 1
fi

# ------------------------------------------------------------------- skhd
# Two layouts exist in the wild and both have to be undone correctly.
#
# The current installer keeps the binding in its own fragment and adds one
# .load line to the user's skhdrc, so the undo is: delete the fragment, delete
# that one line, and leave every other line of their keymap where it is.
#
# An older installer copied its own skhdrc straight over the user's. A file
# whose only binding is ours is still that copy, so it is removed whole; a
# file that also holds somebody else's hotkeys never is.
SKHD_OURS=0          # the whole skhdrc is ours, the legacy layout
SKHD_HAS_BINDING=0   # it binds the key inline, the old way
SKHD_LOADS=0         # it carries our .load line
SKHD_FRAGMENT=0      # the fragment file is on this Mac
SKHD_OTHER=""

# Whitespace is ignored around the line, its text is not: a .load pointing at
# some other file is not ours and must survive.
has_load_line() {
  awk -v want="$LOAD_LINE" '
    { t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
      if (t == want) { found = 1; exit } }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# The user's skhdrc without our .load line and without the comment block the
# installer wrote directly above it. Every other line is passed through byte
# for byte, comments included: that file is theirs.
strip_load_line() {
  awk -v want="$LOAD_LINE" '
    function flush_held(   i) {
      for (i = 1; i <= n; i++) print held[i]
      n = 0
    }
    {
      t = $0
      sub(/^[[:space:]]+/, "", t)
      sub(/[[:space:]]+$/, "", t)
      if (t == want) { n = 0; next }
      if (t ~ /^#/ && (n > 0 || t ~ /lightweight-rec/)) { held[++n] = $0; next }
      flush_held()
      print
    }
    END { flush_held() }
  ' "$1"
}

if [ -f "$FRAGMENT" ]; then
  SKHD_FRAGMENT=1
fi
if [ -f "$SKHDRC" ]; then
  if grep -qE "$BINDING_RE" "$SKHDRC"; then
    SKHD_HAS_BINDING=1
  fi
  if has_load_line "$SKHDRC"; then
    SKHD_LOADS=1
  fi
  SKHD_OTHER=$(grep -vE '^[[:space:]]*(#|$)' "$SKHDRC" | grep -vE "$BINDING_RE" \
    | grep -vF "$LOAD_LINE" || true)
  # Ours needs both halves to be true: the file carries the Option+R binding
  # inline, and it carries nothing else. Absence of other bindings is not
  # enough. A skhdrc holding only commented-out lines has no binding of ours
  # in it at all, it is somebody's keymap parked for later, and removing it
  # would be the one thing this script promises never to do.
  if [ "$SKHD_HAS_BINDING" -eq 1 ] && [ -z "$SKHD_OTHER" ]; then
    SKHD_OURS=1
  fi
fi

# Editing the user's own file is a separate act from removing ours, so it gets
# its own flag, its own line in the plan and its own backup.
SKHD_EDIT=0
if [ "$SKHD_LOADS" -eq 1 ] && [ "$SKHD_OURS" -eq 0 ]; then
  SKHD_EDIT=1
fi

REMOVE=()
for f in "$BIN/record" "$BIN/record-lib.sh" "$BIN/record-dot" "$BIN/record-audio"; do
  if [ -e "$f" ]; then
    REMOVE+=("$f")
  fi
done
if [ "$SKHD_FRAGMENT" -eq 1 ]; then
  REMOVE+=("$FRAGMENT")
fi
if [ "$SKHD_OURS" -eq 1 ]; then
  REMOVE+=("$SKHDRC")
fi

echo "== will be removed =="
if [ "${#REMOVE[@]}" -eq 0 ]; then
  echo "  nothing: none of the installed files is on this Mac"
else
  for f in "${REMOVE[@]}"; do
    echo "  $f"
  done
fi
if [ "$SKHD_FRAGMENT" -eq 1 ]; then
  echo "  (a copy of $FRAGMENT is kept next to it as .bak.<timestamp>)"
fi
if [ "$SKHD_OURS" -eq 1 ]; then
  echo "  (a copy of $SKHDRC is kept next to it as .bak.<timestamp>)"
  echo "  the skhd service is stopped, because that config was only ours"
fi

if [ "$SKHD_EDIT" -eq 1 ]; then
  echo
  echo "== will be edited =="
  echo "  $SKHDRC, one line only, the one install.sh appended:"
  echo "    $LOAD_LINE"
  echo "  Every other binding in that file stays, and a copy is kept next to"
  echo "  it as .bak.<timestamp> before the line goes."
fi

echo
echo "== will be kept =="
if [ -x "$BIN/record-audio" ]; then
  echo "  a Record-In or Record-Out device left by a version before 0.3 is"
  echo "  removed first, with '$BIN/record-audio down', so nothing stays in"
  echo "  Audio MIDI Setup"
fi
if [ -f "$SKHDRC" ] && [ "$SKHD_OURS" -eq 0 ]; then
  if [ "$SKHD_EDIT" -eq 1 ]; then
    echo "  $SKHDRC itself, and every hotkey in it except our load line"
  elif [ "$SKHD_HAS_BINDING" -eq 1 ]; then
    echo "  $SKHDRC: it has hotkeys that are not ours, so it stays untouched"
  else
    echo "  $SKHDRC: it carries nothing of ours, so it is not ours to touch"
  fi
fi
if [ -f "$CONFIG" ]; then
  echo "  $CONFIG (your paths: delete it by hand if you want)"
fi
echo "  every recording, note, vault and model listed at the end"

if [ "${#REMOVE[@]}" -gt 0 ] || [ "$SKHD_EDIT" -eq 1 ]; then
  if [ "$ASSUME_YES" -ne 1 ]; then
    if [ ! -t 0 ]; then
      echo
      echo "Not a terminal and --yes was not given. Nothing was removed."
      exit 1
    fi
    echo
    if [ "$SKHD_EDIT" -eq 1 ]; then
      printf 'Remove the %s file(s) above and drop that one line? [y/N] ' "${#REMOVE[@]}"
    else
      printf 'Remove the %s file(s) above? [y/N] ' "${#REMOVE[@]}"
    fi
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) echo "Nothing was removed."; exit 0 ;;
    esac
  fi

  echo
  # Order matters: the helper has to run before it is deleted, or an
  # aggregate device left by a version before 0.3 survives in the CoreAudio
  # config forever. Since 0.3 nothing is created, so on a current install
  # this finds nothing and says so.
  if [ -x "$BIN/record-audio" ]; then
    echo "== audio devices =="
    prev=""
    [ -f "$DIR/.previous-output" ] && prev=$(cat "$DIR/.previous-output")
    if [ -n "$prev" ]; then
      "$BIN/record-audio" down "$prev" 2>&1 | sed 's/^/  /' || true
      echo "  sound output asked back to $prev: check Sound settings if it is not"
    else
      "$BIN/record-audio" down 2>&1 | sed 's/^/  /' || true
    fi
    echo "  any Record-In or Record-Out from an older version is gone"
    rm -f "$DIR/.previous-output"
  fi

  if [ "${#REMOVE[@]}" -gt 0 ]; then
    echo "== files =="
    for f in "${REMOVE[@]}"; do
      # Config files get a copy first. The fragment is ours, but somebody may
      # have moved the hotkey to another key inside it, and that edit is worth
      # more than the file.
      if [ "$f" = "$SKHDRC" ] || [ "$f" = "$FRAGMENT" ]; then
        backup="$f.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$f" "$backup"
        echo "  copied $f to $backup"
      fi
      rm -f "$f"
      echo "  removed $f"
    done
  fi

  if [ "$SKHD_EDIT" -eq 1 ]; then
    echo "== your skhd config =="
    backup="$SKHDRC.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$SKHDRC" "$backup"
    echo "  copied $SKHDRC to $backup"
    tmp="$SKHDRC.uninstall.$$"
    strip_load_line "$SKHDRC" > "$tmp"
    if grep -qE '[^[:space:]]' "$tmp"; then
      # Written through the existing file, not moved over it, so the mode and
      # the inode the user set stay as they are.
      cat "$tmp" > "$SKHDRC"
      rm -f "$tmp"
      echo "  dropped the load line; the rest of your keymap is untouched"
    else
      # Nothing but our own line was ever in there: that file is the stub the
      # installer created on a Mac that had no skhd config, so it goes too.
      rm -f "$tmp" "$SKHDRC"
      echo "  removed $SKHDRC: our load line was the only thing in it"
    fi
  fi

  if [ "$SKHD_OURS" -eq 1 ]; then
    echo "== skhd service =="
    if command -v skhd >/dev/null 2>&1; then
      skhd --stop-service >/dev/null 2>&1 || true
      echo "  stopped: Option+R does nothing now"
    else
      echo "  skhd is not on PATH: stop it yourself with 'skhd --stop-service'"
    fi
  elif [ "$SKHD_EDIT" -eq 1 ] || [ "$SKHD_FRAGMENT" -eq 1 ]; then
    # Reloaded, never stopped: that config still holds hotkeys of theirs, and
    # stopping the service would take those down with ours.
    echo "== skhd service =="
    if command -v skhd >/dev/null 2>&1; then
      if skhd --reload >/dev/null 2>&1; then
        echo "  reloaded: Option+R is gone, your other hotkeys stayed up"
      else
        echo "  could not reload skhd. Do it yourself: skhd --restart-service"
      fi
    else
      echo "  skhd is not on PATH: reload it yourself with 'skhd --reload'"
    fi
  fi
fi

# Only worth printing when the file still points Option+R at a binary that has
# just been deleted. A skhdrc with no record binding needs nothing from the
# reader, so it gets no wall of text.
if [ "$SKHD_OURS" -eq 0 ] && [ "$SKHD_HAS_BINDING" -eq 1 ]; then
  echo
  echo "== read this: your skhd config was left alone =="
  echo "  $SKHDRC has bindings that install.sh did not write, so removing it"
  echo "  would take your own hotkeys with it. Option+R still points at a file"
  echo "  that no longer exists. Delete this line by hand:"
  grep -nE "$BINDING_RE" "$SKHDRC" | sed 's/^/    /'
  echo "  then reload with: skhd --restart-service"
fi

if [ -f "$HOME/.zshrc" ] && grep -qF "$PATH_LINE" "$HOME/.zshrc"; then
  echo
  echo "== read this: ~/.zshrc was left alone =="
  echo "  install.sh appended this line:"
  echo "    $PATH_LINE"
  left=0
  if [ -d "$BIN" ]; then
    left=$(find "$BIN" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  fi
  echo "  $BIN still holds $left file(s). Remove the line only if you put"
  echo "  nothing else in there: other tools of yours may live in it."
fi

echo
echo "== kept: your data, none of it was touched =="
if [ -d "$DIR" ]; then
  count=$(find "$DIR" -maxdepth 1 -name '*.mp4' | wc -l | tr -d ' ')
  size=$(du -sh "$DIR" 2>/dev/null | cut -f1)
  echo "  videos      $DIR  ($count mp4, $size in total)"
else
  echo "  videos      $DIR  (not on this Mac)"
fi
if [ -f "$MODEL" ]; then
  echo "  model       $MODEL  ($(du -h "$MODEL" | cut -f1))"
fi
echo "  notes       $NOTES"
echo "  vault       $VAULT"
if [ -f "$CONFIG" ]; then
  echo "  config      $CONFIG"
fi
echo
echo "  Those videos and notes carry the voice of everyone who was in a call"
echo "  with you. Review them, then remove them yourself:"
# A printed command is still a loaded gun, because somebody will paste it
# without reading it. Offer rm -rf only for a directory this tool owns on its
# own. RECORD_NOTES pointing straight at the vault root is a supported config
# and a common one, and there the command would take the entire vault with it.
if offer_rm_rf "$DIR"; then
  echo "    rm -rf \"$DIR\""
else
  echo "    (no rm -rf printed for the videos: $DIR is your home directory or"
  echo "     your vault, so delete the mp4 files inside it instead)"
fi
if offer_rm_rf "$NOTES"; then
  echo "    rm -rf \"$NOTES\"        # only if you keep nothing else in there"
else
  echo "    (no rm -rf printed for the notes: $NOTES is your vault root or your"
  echo "     home directory, so delete the note files inside it instead)"
fi
if [ -f "$CONFIG" ]; then
  echo "    rm -f  \"$CONFIG\""
fi

echo
echo "== kept: Homebrew packages, other tools may need them =="
echo "  ffmpeg  whisper-cpp  koekeishiya/formulae/skhd"
echo "  Remove them yourself, one at a time, if nothing else uses them:"
echo "    brew uninstall ffmpeg whisper-cpp koekeishiya/formulae/skhd"
echo "  Versions before 0.3 also installed switchaudio-osx and, on request, the"
echo "  blackhole-2ch cask. Neither is used any more:"
echo "    brew uninstall switchaudio-osx"
echo "    brew uninstall --cask blackhole-2ch   # audio driver: asks for your password"
echo "  Handy is not in that list: install.sh only installs it when you ask for"
echo "  it with --with-handy. If you did, 'brew uninstall --cask handy' removes"
echo "  it, and RECORD_LAUNCH_APP in your config is what used to open it."
echo "  The AI CLI (claude, cursor-agent or copilot) is left alone: install.sh"
echo "  never put it there."
echo
echo "Repo left in place at $ROOT. Delete the clone when you are done."
