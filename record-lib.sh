#!/bin/bash
# Pure helpers for record. Sourced by the script and by tests.
# Do not mkdir, do not start processes.

device_index() {
  # $1 = ffmpeg -list_devices stderr
  # $2 = which of the two lists to search, "video" or "audio"
  # $3 = the device name, compared as a WHOLE and LITERAL string
  #
  # Prints that device's ffmpeg index, or prints nothing at all. Printing
  # nothing is the half that matters: the caller can say "no such device" only
  # if a near miss cannot come back looking like an answer.
  #
  # It used to be `sed "s/.*\[\([0-9]*\)\] $3/\1/p"`, which was neither whole
  # nor literal. The name was a prefix, so RECORD_MIC="MacBook Pro Mic" matched
  # "[1] MacBook Pro Microphone" and sed printed the index followed by the tail
  # sed had not consumed: the index "1rophone", handed straight to ffmpeg as
  # -i "5:1rophone". The user got "Did not start" and nothing anywhere named
  # the typo. The name was also a regex, so a "." in it matched any character
  # and a stray "*" or "[" changed the pattern altogether.
  #
  # The section is not optional: the video and audio lists are numbered
  # independently and both start at 0, so an index means nothing without it.
  # Last match wins, as the old `tail -1` did, for the case of two identical
  # devices carrying the same name.
  printf '%s\n' "$1" | RECORD_LIB_SECTION="$2" RECORD_LIB_WANT="$3" awk '
    BEGIN {
      section = ENVIRON["RECORD_LIB_SECTION"]
      want = ENVIRON["RECORD_LIB_WANT"]
      # A config file written by hand carries stray whitespace around the
      # value often enough to be worth forgiving, and record-audio already
      # forgives it (RECORD_MIC is trimmed there too). The two must agree on
      # what a name is, or one of them records a device the other refused.
      sub(/^[[:space:]]+/, "", want)
      sub(/[[:space:]]+$/, "", want)
    }
    /AVFoundation video devices:/ { here = "video"; next }
    /AVFoundation audio devices:/ { here = "audio"; next }
    here != section { next }
    match($0, /\[[0-9]+\] /) {
      name = substr($0, RSTART + RLENGTH)
      sub(/^[[:space:]]+/, "", name)
      sub(/[[:space:]]+$/, "", name)
      if (name != "" && name == want) { found = substr($0, RSTART + 1, RLENGTH - 3); have = 1 }
    }
    END { if (have) print found }
  '
}

parse_capture_index() {
  # $1 = ffmpeg -list_devices stderr, $2 = the N of "Capture screen N"
  # Screen 1 must never answer for screen 10, and a camera must never answer
  # for a screen: both are what an unanchored match used to allow.
  device_index "$1" video "Capture screen $2"
}

parse_audio_index() {
  # $1 = ffmpeg -list_devices stderr, $2 = exact device name
  # Empty means "this Mac has no audio input by that name", and the caller is
  # expected to say so with the name in hand.
  device_index "$1" audio "$2"
}

resolve_audio_index() {
  # $1 = ffmpeg -list_devices stderr.
  # Prints the index of the input to record from when no device name is
  # configured. Every Mac names its built-in microphone after the model
  # ("MacBook Air Microphone", "Mac mini Microphone"...), so a fixed string
  # only ever works on one machine. Order of preference:
  #   1. a built-in microphone, whatever the model calls it
  #   2. any other real microphone (an external USB or interface one)
  #   3. the first remaining input
  # Loopback drivers (BlackHole and friends), meeting-app virtual devices and
  # the Record-In / Record-Out aggregates versions up to 0.2 of this tool
  # created are never picked: on their own they carry no voice. Prints
  # nothing when there is no input.
  printf '%s\n' "$1" | awk '
    /AVFoundation video devices:/ { audio = 0; next }
    /AVFoundation audio devices:/ { audio = 1; next }
    !audio { next }
    match($0, /\[[0-9]+\] /) {
      idx = substr($0, RSTART + 1, RLENGTH - 3)
      name = substr($0, RSTART + RLENGTH)
      sub(/[[:space:]]+$/, "", name)
      if (name == "") next
      if (name ~ /BlackHole|Soundflower|Loopback|Record-In|Record-Out|Aggregate|Multi-Output|ZoomAudioDevice|Teams Audio|VB-Cable|Krisp/) next
      if (!have_builtin && name ~ /^(MacBook Pro|MacBook Air|MacBook|iMac Pro|iMac|Mac mini|Mac Studio|Mac Pro|Studio Display|Built-in|Built-In|Internal) Microphone$/) {
        builtin = idx; have_builtin = 1
      }
      if (!have_mic && name ~ /[Mm]icrophone/ && name !~ /iPhone|iPad|Apple Watch/) {
        mic = idx; have_mic = 1
      }
      if (!have_first) { first = idx; have_first = 1 }
    }
    END {
      if (have_builtin) print builtin
      else if (have_mic) print mic
      else if (have_first) print first
    }
  '
}

audio_name_at() {
  # $1 = ffmpeg -list_devices stderr, $2 = an index in the audio list
  # Prints the name ffmpeg lists at that index, the inverse of
  # parse_audio_index, so a start can say which microphone it opened instead
  # of a bare number. Prints nothing for an index that is not in the list.
  printf '%s\n' "$1" | RECORD_LIB_WANT="$2" awk '
    BEGIN { want = ENVIRON["RECORD_LIB_WANT"] }
    /AVFoundation video devices:/ { audio = 0; next }
    /AVFoundation audio devices:/ { audio = 1; next }
    !audio { next }
    match($0, /\[[0-9]+\] /) {
      idx = substr($0, RSTART + 1, RLENGTH - 3)
      if (idx == want) {
        name = substr($0, RSTART + RLENGTH)
        sub(/^[[:space:]]+/, "", name)
        sub(/[[:space:]]+$/, "", name)
        print name
        exit
      }
    }
  '
}

is_off() {
  # $1 = the raw value of a config switch that defaults to on.
  # True when the user has explicitly turned it off, in any of the spellings a
  # person actually types. Anything else, an unset or empty value included,
  # leaves the feature on: a typo must never silently disable something.
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    0|no|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

vault_root() {
  # $1 = the directory a note is about to be written into.
  # Prints the root of the Obsidian vault that contains it, found by walking up
  # to the first ancestor holding a .obsidian directory, which is the one thing
  # every vault has and nothing else does. Prints nothing when the path is in
  # no vault, which is the case worth shouting about: the note lands somewhere
  # the user will never open.
  # Read only. It stats directories and creates nothing, so a test can call it
  # on a sandbox tree, and it works on a folder that does not exist yet.
  local dir="$1"
  local up
  while [ -n "$dir" ] && [ "$dir" != "." ]; do
    if [ -d "$dir/.obsidian" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    up=$(dirname "$dir")
    [ "$up" = "$dir" ] && break
    dir="$up"
  done
  return 0
}

# --- JSON, the little of it an HTTP model API needs ------------------------
#
# With RECORD_AI naming a server rather than a CLI, `record` speaks the
# OpenAI-shaped /chat/completions protocol itself: it writes one JSON request
# and reads one string back. That is the whole of its JSON needs, and it is
# not worth a jq on the dependency list.
#
# Reading is done by whatever the machine already has. plutil ships with every
# macOS and cannot be removed; python3 covers CI and a Linux dev box. plutil is
# tried first on purpose: on a Mac without the Xcode command line tools
# /usr/bin/python3 is a stub that opens an install dialog, and a tool started
# by a hotkey, with no terminal attached, must never put one on the screen.

json_reader() {
  # The name of the program that will parse the answer, or nothing at all,
  # which is the caller's cue to make no call rather than one it cannot read.
  if command -v plutil >/dev/null 2>&1; then
    echo plutil
  elif command -v python3 >/dev/null 2>&1; then
    echo python3
  else
    echo ""
  fi
}

json_get() {
  # $1 = a dotted path, array indices included: choices.0.message.content.
  # The document arrives on stdin. Prints the value, or prints nothing and
  # fails, which is how the caller tells an answer from an error body.
  local path="$1"
  case "$(json_reader)" in
    plutil)
      plutil -extract "$path" raw -o - -- - 2>/dev/null ;;
    python3)
      RECORD_JSON_PATH="$path" python3 -c '
import json, os, sys
try:
    node = json.load(sys.stdin)
    for key in os.environ["RECORD_JSON_PATH"].split("."):
        node = node[int(key)] if isinstance(node, list) else node[key]
except Exception:
    sys.exit(1)
sys.stdout.write(node if isinstance(node, str) else json.dumps(node))
' 2>/dev/null ;;
    *)
      return 2 ;;
  esac
}

json_escape() {
  # Text on stdin, the body of a JSON string on stdout: no surrounding quotes,
  # every backslash and every quote escaped, every newline turned into \n.
  #
  # Control characters are dropped rather than escaped, tab included. Nothing
  # in a transcript or in a prompt needs one, and a raw control character in a
  # JSON string is a parse error at the other end: the whole request would be
  # rejected for a byte whisper.cpp happened to emit.
  #
  # sed does the two escapes and never sees \t or \n as such: BSD sed reads
  # "\t" in a pattern as the letter t, which would have replaced every t in
  # the transcript. The newlines are joined by awk instead, which is also what
  # keeps the last line from producing a trailing \n that was never there.
  LC_ALL=C tr -d '\000-\011\013-\037\177' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | LC_ALL=C awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}
