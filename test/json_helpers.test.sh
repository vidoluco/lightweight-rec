#!/bin/bash
# Break this would catch: a transcript that quietly costs the note its summary.
#
# The HTTP backends send the transcript and the screen frames as one JSON
# request that `record` builds by hand, so `json_escape` is the only thing
# standing between whisper's output and a body the endpoint refuses. One raw
# control byte, one unescaped quote, and the whole request is rejected: the
# model never answers, and the note loses its title, tags and summary while
# looking exactly like a note whose model was merely slow. That is the failure
# this file exists to keep out.
#
# It was not covered before. The suite's stub whisper prints one clean
# sentence with no quote, no backslash, no tab and no control character in it,
# so every other test drives the escaping with input that could not break it.
# The nasty input was only ever exercised by hand, on Linux, before merge.
#
# `json_get` is the other half of the same round trip, and on a Mac it runs
# through plutil, a branch no Linux run can reach at all.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../record-lib.sh
. "$ROOT/record-lib.sh"

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# A string goes through json_escape into a JSON document, and comes back out
# through a reader that is not the one being tested. Round tripping is the
# point: asserting on the escaped bytes would only restate the implementation.
roundtrip() {
  local body
  body=$(printf '%s' "$1" | json_escape)
  # A body that will not parse is the failure this file is about, so it comes
  # back as a value the assertion can print. Letting json.load raise here would
  # end the run under set -e with a Python traceback instead of a FAIL line
  # naming the input that broke it.
  printf '{"t":"%s"}' "$body" | python3 -c '
import json, sys
try:
    sys.stdout.write(json.load(sys.stdin)["t"])
except Exception as exc:
    sys.stdout.write("INVALID JSON (%s)" % exc)
'
}

# Quotes and backslashes are the two bytes that end a JSON string early.
got=$(roundtrip 'He said "hi" and \escaped\ it')
[ "$got" = 'He said "hi" and \escaped\ it' ] \
  || bad "quotes and backslashes did not survive: $got"

# A Windows path is the shape that turns one unescaped backslash into four.
got=$(roundtrip 'C:\Users\test\file.txt')
[ "$got" = 'C:\Users\test\file.txt' ] || bad "backslash run mangled: $got"

# Newlines have to become \n rather than a raw byte, and the last line must
# not gain one it never had.
got=$(roundtrip "$(printf 'one\ntwo\nthree')")
[ "$got" = "$(printf 'one\ntwo\nthree')" ] || bad "newlines did not survive as \\n: $(printf '%s' "$got" | od -c | head -2)"

# Control characters are dropped on purpose: a raw one is a parse error at the
# other end, and nothing in a transcript needs one. Tab included, which the
# comment in record-lib.sh says out loud and the PR description got wrong.
got=$(roundtrip "$(printf 'a\tb\007c')")
[ "$got" = "abc" ] || bad "control characters were not dropped: $(printf '%s' "$got" | od -c | head -1)"

# The bytes whisper.cpp actually emits, all at once. If this one is valid JSON
# the escaping holds for anything a real session produces.
nasty='[00:00:01.000 --> 00:00:04.000]  He said "it'"'"'s a \path\ thing"'
got=$(roundtrip "$nasty")
[ "$got" = "$nasty" ] || bad "a realistic transcript line did not survive: $got"

# An empty transcript must still produce a valid JSON string, not a broken body.
got=$(printf '%s' "" | json_escape)
[ -z "$got" ] || bad "empty input produced '$got'"
printf '{"t":"%s"}' "$got" | python3 -c 'import json,sys; json.load(sys.stdin)' \
  || bad "empty input produced a body that is not valid JSON"

# --------------------------------------------------------------- json_get
# The reader the answer comes back through. On a Mac this is plutil, which no
# Linux CI run exercises.
reader=$(json_reader)
[ -n "$reader" ] || bad "json_reader named no reader on a machine that has one"

answer='{"choices":[{"message":{"role":"assistant","content":"TITLE: A note"}}]}'
got=$(printf '%s' "$answer" | json_get 'choices.0.message.content') \
  || bad "json_get failed on a well-formed answer (reader: $reader)"
[ "$got" = "TITLE: A note" ] || bad "json_get read '$got' (reader: $reader)"

# An error body is how record tells a refusal from an answer, so the miss has
# to fail rather than print something.
got=$(printf '%s' '{"error":{"message":"unknown model"}}' | json_get 'choices.0.message.content') && rc=0 || rc=$?
[ "$rc" -ne 0 ] || bad "json_get succeeded on an error body, printing '$got'"
got=$(printf '%s' '{"error":{"message":"unknown model"}}' | json_get 'error.message') \
  || bad "json_get could not read the error message record quotes back"
[ "$got" = "unknown model" ] || bad "json_get read the error as '$got'"

# Not JSON at all: a proxy's HTML page, or an empty body from a dead socket.
printf '%s' '<html>502 Bad Gateway</html>' | json_get 'choices.0.message.content' >/dev/null 2>&1 \
  && bad "json_get accepted an HTML error page as an answer"
printf '%s' '' | json_get 'choices.0.message.content' >/dev/null 2>&1 \
  && bad "json_get accepted an empty body as an answer"

if [ "$fail" -ne 0 ]; then
  echo "json_helpers: failed"
  exit 1
fi
echo "json_helpers: ok"
