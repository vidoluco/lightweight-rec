#!/bin/bash
# Break this would catch: RECORD_AI naming a model server and record calling
# the wrong endpoint, sending the wrong model, sending no images, putting the
# API key on the command line, or going quiet about a server that is not there.
#
# Besides the three CLIs, RECORD_AI can name something that speaks the
# /chat/completions protocol: ollama and lmstudio on this Mac, openai,
# anthropic, gemini and openrouter out on the network, custom for anything
# else. That path is record's own code rather than a vendor's CLI: it builds
# the JSON, base64s the frames into it, and reads one string back. Every one
# of those steps is invisible when it goes wrong. A request that carries no
# image still comes back with a plausible-looking description, and a note that
# lost its summary because nothing was listening on localhost reads exactly
# like a note whose model was merely slow. So the stub curl keeps every
# request body and every curl config file, and this test reads them back.
#
# Nothing real is touched and nothing reaches the network: a throwaway HOME
# under TMPDIR, `env -i` so the caller's RECORD_* variables and
# ~/.config/record/config cannot reach the run, and stubs that refuse any path
# under the real HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"
# The tool's own JSON reader, used here to prove the requests it writes are
# valid JSON and say what they are supposed to say.
# shellcheck source=../record-lib.sh
. "$ROOT/record-lib.sh"

BASE=$(sandbox_base ai-http)
trap 'rm -rf "$BASE"' EXIT

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# One sandbox per case. Prints nothing; sets sb, dir, vault, notes, bin, tmp,
# argv, http for the caller.
prepare() {
  local label="$1"
  sb="$BASE/$label"
  dir="$sb/Recordings"
  vault="$sb/Documents/Notebook"
  notes="$vault/Recordings"
  bin="$sb/bin"
  tmp="$sb/tmp"
  argv="$sb/argv.txt"
  http="$sb/http"
  sandbox_guard "$sb"    "$BASE" "the sandbox HOME"
  sandbox_guard "$dir"   "$BASE" "RECORD_DIR"
  sandbox_guard "$notes" "$BASE" "RECORD_NOTES"
  mkdir -p "$dir" "$vault/.obsidian" "$notes" "$tmp" "$http"
  make_stubs "$bin"
  seed_recordings "$dir"
}

the_note() {
  find "$1" -maxdepth 1 -name '*.md' | head -1
}

# Reading a pipeline with grep, never with `grep -q`. `-q` makes grep exit on
# its first match, the cat feeding it dies of SIGPIPE writing the file after
# that, and `set -o pipefail` turns the whole thing into a failed assertion
# about a line that was there all along. It is a race, so it passed here and
# failed on the macOS runner, where cat still had three files to open when
# grep was already gone. Letting grep read to the end costs nothing on input
# this size and cannot lie.
has_line() { grep -x -- "$1" >/dev/null; }
has()      { grep -E -- "$1" >/dev/null; }

# The request bodies the run produced, by kind: the screen calls are the ones
# carrying images, the metadata call is the one that does not.
vision_requests() { grep -l 'image_url' "$http"/request-*.json 2>/dev/null | sort; }
meta_requests()   { grep -L 'image_url' "$http"/request-*.json 2>/dev/null | sort; }
urls()            { cat "$http"/request-*.url 2>/dev/null; }

# The text the model was actually asked, read out of the request the way the
# endpoint would read it. Fails loudly if the body is not valid JSON, which is
# the failure a transcript full of quotes and backslashes would cause.
prompt_text() {
  json_get 'messages.0.content.0.text' < "$1" 2>/dev/null \
    || json_get 'messages.0.content' < "$1" 2>/dev/null
}

# ------------------------------------------------------------------ ollama
# Nothing configured but the backend name: the endpoint is ollama's own, the
# model is whatever the server lists first, and the note is the same note the
# CLIs produce.
prepare ollama
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=ollama RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { bad "ollama: record transcribe exited $rc"; printf '%s\n' "$out" | sed 's/^/      /'; }
note=$(the_note "$notes")
[ -n "$note" ] || bad "ollama: no note written"

# One model listing, one screen call per clip, one metadata call.
urls | has_line 'http://localhost:11434/v1/models' || bad "ollama: the models endpoint was not asked: $(urls | tr '\n' ' ')"
[ "$(urls | grep -c 'http://localhost:11434/v1/chat/completions')" -eq 3 ] \
  || bad "ollama: expected 3 chat calls, got $(urls | grep -c 'chat/completions')"
[ "$(vision_requests | wc -l | tr -d ' ')" -eq 2 ] || bad "ollama: expected 2 screen calls, got $(vision_requests | wc -l | tr -d ' ')"
[ "$(meta_requests | wc -l | tr -d ' ')" -eq 1 ] || bad "ollama: expected 1 metadata call, got $(meta_requests | wc -l | tr -d ' ')"

# The model came from the server's own listing, on every call.
for f in "$http"/request-*.json; do
  [ "$(json_get model < "$f")" = "stub-model" ] || bad "ollama: $(basename "$f") does not carry the model the server listed"
done

# The frames are in the body, as data URLs, one per frame the stub ffmpeg
# wrote. A screen call that reaches the model with no image at all is the
# silent failure this whole test exists for.
first_vision=$(vision_requests | head -1)
n_img=$(grep -o 'data:image/jpeg;base64,' "$first_vision" | wc -l | tr -d ' ')
[ "$n_img" -eq 2 ] || bad "ollama: expected 2 images in the screen call, got $n_img"
# Every request is valid JSON and the prompt survived the escaping.
prompt_text "$first_vision" | has 'screen frames in order' \
  || bad "ollama: the screen prompt is missing or the body is not valid JSON"
prompt_text "$first_vision" | has 'at 0:00 from start' \
  || bad "ollama: the screen prompt does not say when each frame was taken"
prompt_text "$(meta_requests | head -1)" | has 'Stub transcript for the test suite' \
  || bad "ollama: the transcript did not reach the metadata call"

# No key, so no Authorization header at all.
grep -h -q 'Authorization' "$http"/request-*.curlrc 2>/dev/null \
  && bad "ollama: a local call carried an Authorization header"

grep -q '^# Stub session' "$note" || bad "ollama: the note did not take the stubbed title"
grep -q '^## What was on screen' "$note" || bad "ollama: the note has no screen section"
printf '%s\n' "$out" | grep -q 'AI: ollama (http://localhost:11434/v1), screen frames with stub-model' \
  || bad "ollama: the run does not announce the endpoint and the model: $(printf '%s\n' "$out" | grep 'AI:' || echo none)"

# ---------------------------------------------------------------- lmstudio
# Same protocol, LM Studio's own port, and RECORD_AI_FRAMES caps how many of
# the extracted frames one request carries: a chat request holds every image
# it names, and thirty of them is what makes a local model fall over.
prepare lmstudio
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=lmstudio RECORD_AI_FRAMES=1 RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "lmstudio: record transcribe exited $rc"
urls | has_line 'http://localhost:1234/v1/models' || bad "lmstudio: not called on LM Studio's port"
n_img=$(grep -o 'data:image/jpeg;base64,' "$(vision_requests | head -1)" | wc -l | tr -d ' ')
[ "$n_img" -eq 1 ] || bad "lmstudio: RECORD_AI_FRAMES=1 sent $n_img images"

# ----------------------------------------------------------- openai, no key
# A hosted backend with no key must make no call at all, and the note has to
# name the variable to set rather than look like a model that went quiet.
prepare nokey
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=openai RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "nokey: record transcribe exited $rc"
note=$(the_note "$notes")
[ -n "$note" ] || bad "nokey: no note written"
[ ! -e "$argv" ] || bad "nokey: a call was made without an API key"
grep -q 'OPENAI_API_KEY' "$note" || bad "nokey: the note does not name the variable to set"
grep -q '^# Recorded session' "$note" || bad "nokey: the note has a title it should not have"
grep -q 'Stub transcript for the test suite' "$note" || bad "nokey: the transcript is missing from the note"

# --------------------------------------------------------- openai, with key
# The key goes in curl's config file, mode 600, and never on the command line:
# arguments are readable in `ps` by anything running as this user.
prepare withkey
secret="sk-test-not-a-real-key"
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=openai RECORD_AI_KEY="$secret" RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "withkey: record transcribe exited $rc"
urls | has_line 'https://api.openai.com/v1/chat/completions' || bad "withkey: OpenAI's endpoint was not called"
grep -h -q "Authorization: Bearer $secret" "$http"/request-*.curlrc || bad "withkey: the key did not reach curl's config"
grep -q -F "$secret" "$argv" && bad "withkey: the API key was passed on the command line"
# A hosted backend has a model of its own and must not ask the endpoint for one.
urls | has '/models$' && bad "withkey: a hosted backend asked for a model listing"
grep -q '^# Stub session' "$(the_note "$notes")" || bad "withkey: the note did not take the stubbed title"

# ------------------------------------------------------------- anthropic
# The two models are separate everywhere: the frames go to the vision model,
# the title and summary to the metadata one, and neither leaks into the other.
prepare anthropic
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=anthropic RECORD_AI_KEY=k RECORD_AI_VISION_MODEL=see-this \
  RECORD_AI_META_MODEL=name-this RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "anthropic: record transcribe exited $rc"
urls | has_line 'https://api.anthropic.com/v1/chat/completions' || bad "anthropic: wrong endpoint"
for f in $(vision_requests); do
  [ "$(json_get model < "$f")" = "see-this" ] || bad "anthropic: a screen call did not use the vision model"
done
[ "$(json_get model < "$(meta_requests | head -1)")" = "name-this" ] \
  || bad "anthropic: the metadata call did not use the metadata model"

# ------------------------------------------------------------ nothing there
# The commonest local failure by far: the backend is named, the server is not
# running. It has to be found before a single frame is extracted, and the note
# has to say where nothing answered.
prepare down
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=ollama RECORD_TEST_HTTP_DOWN=1 RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "down: record transcribe exited $rc"
note=$(the_note "$notes")
[ -n "$note" ] || bad "down: no note written"
grep -qF 'http://localhost:11434/v1' "$note" || bad "down: the note does not say where nothing answered"
grep -q 'Stub transcript for the test suite' "$note" || bad "down: the transcript is missing from the note"
if grep -q '^## What was on screen' "$note"; then bad "down: the note has a screen section"; fi
[ "$(urls | grep -c 'chat/completions')" -eq 0 ] || bad "down: a chat call was made although the server is not there"
printf '%s\n' "$out" | grep -q 'Nothing answered at' || bad "down: the run does not say the server is not answering"

# ------------------------------------------------------- model refused
# The server is up and refuses the model. That is not an off switch and must
# not read like one: the endpoint's own words belong in .transcribe.log and
# the note has to point there.
prepare refused
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=ollama RECORD_AI_VISION_MODEL=not-pulled RECORD_AI_META_MODEL=not-pulled \
  RECORD_TEST_AI_FAIL=not-pulled RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "refused: record transcribe exited $rc"
note=$(the_note "$notes")
grep -q 'did not answer' "$note" || bad "refused: the note does not say the model went quiet"
grep -qF 'not-pulled' "$note" || bad "refused: the note does not name the model that was asked for"
grep -qF '.transcribe.log' "$note" || bad "refused: the note does not point at the log"
if grep -q 'RECORD_AI is off' "$note"; then bad "refused: a refused model is reported as a deliberate off"; fi
printf '%s\n' "$out" | grep -q 'unknown model: not-pulled' || bad "refused: the endpoint's error did not reach the log"
# Pinned models mean no listing call: the endpoint is asked for exactly what
# the config named.
urls | has '/models$' && bad "refused: a model listing was fetched although both models are pinned"

# --------------------------------------------------------- custom, no URL
prepare nourl
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=custom RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "nourl: record transcribe exited $rc"
grep -q 'RECORD_AI_URL' "$(the_note "$notes")" || bad "nourl: the note does not say which variable is missing"
[ ! -e "$argv" ] || bad "nourl: a call was made with no endpoint configured"

# -------------------------------------------------------- custom, with URL
# Anything that speaks the protocol: a gateway, another Mac on the LAN, a
# server on a port of its own.
prepare custom
out=$(run_transcribe "$ROOT" "$sb" "$bin" "$tmp" "$dir" "$vault" "$notes" \
  RECORD_AI=custom RECORD_AI_URL=http://studio.local:1234/v1 \
  RECORD_TEST_ARGV="$argv" RECORD_TEST_HTTP="$http") && rc=0 || rc=$?
[ "$rc" -eq 0 ] || bad "custom: record transcribe exited $rc"
urls | has_line 'http://studio.local:1234/v1/chat/completions' || bad "custom: RECORD_AI_URL was not used: $(urls | tr '\n' ' ')"
grep -q '^# Stub session' "$(the_note "$notes")" || bad "custom: the note did not take the stubbed title"

if [ "$fail" -ne 0 ]; then
  echo "ai_http_backend: failed"
  exit 1
fi
echo "ai_http_backend: ok"
