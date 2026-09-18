#!/bin/bash
# Shared scaffolding for the tests that drive `record transcribe`.
#
# Transcribing is the one command that can be exercised end to end without
# recording anything: it reads files off disk, shells out to four external
# programs and writes a note. All four are replaced by stubs here, because the
# real ones would decode video, load a multi-gigabyte Whisper model and bill
# the user's Anthropic account for every test run.
#
# Everything happens under a throwaway HOME in TMPDIR. The tests launch record
# with `env -i`, so the caller's own RECORD_* variables and config file cannot
# reach it, and every stub refuses any argument that points inside the real
# HOME. A test that escapes the sandbox stops on the first stub, loudly.
#
# Source it, do not run it:
#   . "$ROOT/test/lib/transcribe-sandbox.sh"

# The home this machine really has, captured before any test moves HOME.
REAL_HOME="$HOME"

# A sandbox root that is provably not the real home. Prints its path.
sandbox_base() {
  local label="$1" base
  base=$(mktemp -d "${TMPDIR:-/tmp}/record-$label-XXXXXX")
  case "$base" in
    ""|/|"$REAL_HOME"|"$REAL_HOME"/*)
      echo "FAIL: refusing to run, the sandbox root '$base' is inside the real HOME" >&2
      exit 1 ;;
  esac
  printf '%s\n' "$base"
}

# Abort unless a path is inside a sandbox root. Called before anything is
# written, so a mistake in a test cannot reach the user's own recordings.
sandbox_guard() {
  local path="$1" base="$2" what="$3"
  case "$path" in
    "$base"/*) ;;
    *)
      echo "FAIL: $what is '$path', which is outside the sandbox '$base'" >&2
      exit 1 ;;
  esac
  case "$path" in
    "$REAL_HOME"|"$REAL_HOME"/*)
      echo "FAIL: $what is '$path', which is inside the real HOME" >&2
      exit 1 ;;
  esac
}

# Stand-ins for ffmpeg, ffprobe, whisper-cli, the three AI CLIs and curl,
# written into $1.
# Each one starts by refusing any argument under the real HOME: that check is
# the sandbox's last line of defence and it runs before the stub does anything.
make_stubs() {
  local bin="$1"
  mkdir -p "$bin"

  cat > "$bin/ffmpeg" <<'EOF'
#!/bin/bash
# Stub ffmpeg: decodes nothing, records which paths it was handed.
set -euo pipefail

input=""
prev=""
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub ffmpeg: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
  [ "$prev" = "-i" ] && input="$a"
  prev="$a"
done

# The real ffmpeg exits non-zero when the input file does not exist, and that
# is the behaviour worth keeping: a caller that splits a path on its spaces
# must die here, exactly as it does on a user's machine.
if [ -n "$input" ] && [ ! -f "$input" ]; then
  echo "stub ffmpeg: no such input file: $input" >&2
  exit 1
fi

args=("$@")
out=""
[ "${#args[@]}" -gt 0 ] && out="${args[$(( ${#args[@]} - 1 ))]}"
case "$out" in
  *%03d.jpg)
    mkdir -p "$(dirname "$out")"
    : > "$(dirname "$out")/k001.jpg"
    : > "$(dirname "$out")/k002.jpg" ;;
  *.wav)
    : > "$out" ;;
esac
EOF

  cat > "$bin/ffprobe" <<'EOF'
#!/bin/bash
# Stub ffprobe: one fixed duration, so the frame count is deterministic.
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub ffprobe: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
done
echo 300.000000
EOF

  cat > "$bin/whisper-cli" <<'EOF'
#!/bin/bash
# Stub whisper-cli: the real one loads a multi-gigabyte model.
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub whisper-cli: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
done
echo '[00:00:00.000 --> 00:00:04.000]  Stub transcript for the test suite.'
EOF

  cat > "$bin/claude" <<'EOF'
#!/bin/bash
# Stub claude: the real CLI uploads the transcript and screen frames to
# Anthropic and charges the user's plan. A test that reaches it has failed.
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub claude: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
done

if printf '%s\n' "$@" | grep -q 'haiku'; then
  # record pipes the transcript in. Read it so the writer never sees EPIPE.
  cat >/dev/null
  printf 'TITLE: Stub session\n'
  printf 'TAGS: stub test\n'
  printf 'SUMMARY: A stubbed session written by the test suite. Nothing was transcribed.\n'
else
  # Longer than the 60 characters record needs before it keeps a description.
  printf 'The frames showed a stubbed listing written by the test suite, with no readable text of its own to copy.\n'
fi
EOF

  # The two other CLIs record can drive. Same refusal guard, and every call
  # appends its full argument list to $RECORD_TEST_ARGV when the test sets
  # one, so a test can assert on the exact flags record passed: the model, the
  # read-only mode, one --attachment per frame. Which of the two answers a
  # call wants is read off the prompt itself: the metadata prompt is the only
  # one that spells out the TITLE: line it expects back.
  for cli in cursor-agent copilot; do
    cat > "$bin/$cli" <<'EOF'
#!/bin/bash
# Stub AI CLI: the real one uploads the transcript and screen frames to its
# vendor and charges the user's plan. A test that reaches it has failed.
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub $(basename "$0"): refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
done
if [ -n "${RECORD_TEST_ARGV:-}" ]; then
  { printf -- '--- %s\n' "$(basename "$0")"; printf '%s\n' "$@"; } >> "$RECORD_TEST_ARGV"
fi
# A stub told to fail behaves like a CLI asked for a model it does not have:
# one line on stderr, nothing on stdout, exit 1.
if [ -n "${RECORD_TEST_AI_FAIL:-}" ]; then
  echo "error: unknown model: $RECORD_TEST_AI_FAIL" >&2
  exit 1
fi
if printf '%s\n' "$@" | grep -q '^TITLE:'; then
  printf 'TITLE: Stub session\n'
  printf 'TAGS: stub test\n'
  printf 'SUMMARY: A stubbed session written by the test suite. Nothing was transcribed.\n'
else
  # Longer than the 60 characters record needs before it keeps a description.
  printf 'The frames showed a stubbed listing written by the test suite, with no readable text of its own to copy.\n'
fi
EOF
  done

  # The server backends all go out through curl, so one stub covers ollama,
  # lmstudio and the four hosted APIs. It answers the two endpoints record
  # knows, /models and /chat/completions, and it keeps a copy of everything it
  # was handed under $RECORD_TEST_HTTP: the request body, so a test can read
  # back the model, the prompt and the base64 images, and the curl config file,
  # which is where the API key has to be and the command line must not be.
  #   RECORD_TEST_HTTP_DOWN=1   nothing is listening: curl exits 7, no body
  #   RECORD_TEST_AI_FAIL=name  the endpoint refuses that model, as an API does
  #   RECORD_TEST_AI_BARE=1     the three values with the labels dropped, which
  #                             is what a small local model actually answers
  #   RECORD_TEST_AI_PROSE=1    a paragraph with no label and no three lines
  cat > "$bin/curl" <<'EOF'
#!/bin/bash
# Stub curl: the real one would send the screen frames and the transcript to
# whatever endpoint the config names. A test that reaches the network has failed.
set -euo pipefail
for a in "$@"; do
  case "$a" in
    "$RECORD_TEST_REAL_HOME"|"$RECORD_TEST_REAL_HOME"/*)
      echo "stub curl: refusing an argument inside the real HOME: $a" >&2
      exit 90 ;;
  esac
done
if [ -n "${RECORD_TEST_ARGV:-}" ]; then
  { printf -- '--- %s\n' curl; printf '%s\n' "$@"; } >> "$RECORD_TEST_ARGV"
fi

url=""; body=""; out=""; config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --config) config="$2"; shift 2 ;;
    --output) out="$2"; shift 2 ;;
    --data-binary) body="${2#@}"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -n "${RECORD_TEST_HTTP:-}" ]; then
  mkdir -p "$RECORD_TEST_HTTP"
  n=$(find "$RECORD_TEST_HTTP" -maxdepth 1 -name 'request-*' | wc -l | tr -d ' ')
  printf '%s\n' "$url" > "$RECORD_TEST_HTTP/request-$n.url"
  [ -n "$body" ] && [ -f "$body" ] && cp "$body" "$RECORD_TEST_HTTP/request-$n.json"
  [ -n "$config" ] && [ -f "$config" ] && cp "$config" "$RECORD_TEST_HTTP/request-$n.curlrc"
fi

say() { if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi }

# Nothing listening at all: what curl does for a server that is not running.
if [ -n "${RECORD_TEST_HTTP_DOWN:-}" ]; then
  echo "stub curl: (7) Failed to connect to ${url}" >&2
  exit 7
fi

# An endpoint that refuses the model, body and all, the way --fail-with-body
# hands a 404 back to the caller.
if [ -n "${RECORD_TEST_AI_FAIL:-}" ]; then
  say "{\"error\":{\"message\":\"unknown model: $RECORD_TEST_AI_FAIL\"}}"
  echo "stub curl: (22) The requested URL returned error: 404" >&2
  exit 22
fi

case "$url" in
  */models)
    say '{"object":"list","data":[{"id":"stub-model","object":"model"}]}' ;;
  */chat/completions)
    if [ -n "$body" ] && grep -q 'TITLE:' "$body"; then
      if [ -n "${RECORD_TEST_AI_BARE:-}" ]; then
        say '{"choices":[{"message":{"role":"assistant","content":"Bare stub session\nbare stub test\nA stubbed session whose model dropped the labels. Nothing was transcribed."}}]}'
      elif [ -n "${RECORD_TEST_AI_PROSE:-}" ]; then
        say '{"choices":[{"message":{"role":"assistant","content":"Sure! Here is a summary of the session you asked about, written as a paragraph because that is how I felt like answering it today."}}]}'
      else
        say '{"choices":[{"message":{"role":"assistant","content":"TITLE: Stub session\nTAGS: stub test\nSUMMARY: A stubbed session written by the test suite. Nothing was transcribed."}}]}'
      fi
    else
      say '{"choices":[{"message":{"role":"assistant","content":"The frames showed a stubbed listing written by the test suite, with no readable text of its own to copy."}}]}'
    fi ;;
  *)
    echo "stub curl: no route for $url" >&2
    exit 6 ;;
esac
EOF

  cat > "$bin/osascript" <<'EOF'
#!/bin/bash
# Stub osascript: record's notify() posts a Notification Centre banner, and a
# test run has no business putting one on the screen of whoever is running it.
set -euo pipefail
exit 0
EOF

  chmod +x "$bin/ffmpeg" "$bin/ffprobe" "$bin/whisper-cli" "$bin/claude" \
    "$bin/cursor-agent" "$bin/copilot" "$bin/curl" "$bin/osascript"

  # record reads a model server's answer with plutil, which every macOS has,
  # and with python3 anywhere else. The sandbox PATH is /usr/bin and /bin only,
  # so on a machine whose python3 lives elsewhere (a Linux dev box, Homebrew)
  # the real one is linked in. It is used as a JSON parser and nothing else.
  if ! command -v plutil >/dev/null 2>&1; then
    local py
    if py=$(command -v python3 2>/dev/null); then
      ln -sf "$py" "$bin/python3"
    fi
  fi

  # `record` creates its scratch directory the BSD way, `mktemp -d -t
  # record-work`, because it runs on macOS. GNU mktemp reads -t as a template
  # that has to end in X's and refuses the call, which would take down every
  # test that transcribes, on a Linux dev box and in a Linux container alike,
  # for a reason that has nothing to do with the code under test. Where the
  # real mktemp does not understand the flag, a shim that translates it goes on
  # the sandbox PATH; on macOS nothing is written and the real one is used.
  if ! mktemp -d -u -t record-probe >/dev/null 2>&1; then
    cat > "$bin/mktemp" <<'EOF'
#!/bin/bash
# Shim mktemp: turns the BSD `-t prefix` form into the GNU template form.
set -euo pipefail
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -t) args+=(--tmpdir "${2}.XXXXXX"); shift 2 ;;
    *)  args+=("$1"); shift ;;
  esac
done
exec /usr/bin/mktemp "${args[@]}"
EOF
    chmod +x "$bin/mktemp"
  fi
}

# A directory that looks like somewhere record can transcribe from: the whisper
# model it checks for, a session marker dated in the past, and two hourly clips
# newer than it. $1 is RECORD_DIR, which the caller has already guarded.
seed_recordings() {
  local dir="$1"
  mkdir -p "$dir/.whisper"
  printf 'not a real whisper model\n' > "$dir/.whisper/ggml-large-v3-turbo-q5_0.bin"
  # Dated in the past so the clips created next are unambiguously newer, which
  # is what `find -newer` selects on.
  touch -t 202601010000 "$dir/.session"
  printf 'not a real mp4\n' > "$dir/2026-01-02_09-00.mp4"
  printf 'not a real mp4\n' > "$dir/2026-01-02_10-00.mp4"
}

# Run `record transcribe` against a sandbox. env -i is the point: none of the
# caller's RECORD_* variables, and none of the real config file, can reach it.
#   $1 repo root, $2 sandbox HOME, $3 stub bin, $4 TMPDIR,
#   $5 RECORD_DIR, $6 RECORD_VAULT, $7 RECORD_NOTES,
#   then any number of NAME=value pairs the test wants record to see, the
#   RECORD_AI family and the stubs' own RECORD_TEST_* knobs included.
run_transcribe() {
  env -i \
    PATH="$3:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$2" \
    TMPDIR="$4" \
    RECORD_TEST_REAL_HOME="$REAL_HOME" \
    RECORD_CONFIG="$2/.config/record/config-that-does-not-exist" \
    RECORD_DIR="$5" \
    RECORD_VAULT="$6" \
    RECORD_NOTES="$7" \
    "${@:8}" \
    bash "$1/record" transcribe 2>&1
}
