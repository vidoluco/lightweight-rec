#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/transcribe-sandbox.sh
. "$ROOT/test/lib/transcribe-sandbox.sh"

BASE=$(sandbox_base hallucination)
trap 'rm -rf "$BASE"' EXIT
DIR="$BASE/Recordings"
VAULT="$BASE/Documents/Notebook"
NOTES="$VAULT/Recordings"
BIN="$BASE/bin"
TMP="$BASE/tmp"
for path in "$DIR" "$VAULT" "$NOTES" "$BIN" "$TMP"; do
  sandbox_guard "$path" "$BASE" "test fixture"
  mkdir -p "$path"
done
seed_recordings "$DIR"
rm "$DIR/2026-01-02_10-00.mp4"
make_stubs "$BIN"

cat > "$BIN/ffprobe" <<'EOF'
#!/bin/bash
echo 660
EOF
cat > "$BIN/whisper-cli" <<'EOF'
#!/bin/bash
set -euo pipefail
file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f) file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$file" in
  "$RECORD_TEST_REAL_HOME"/*) exit 90 ;;
esac
case "$(basename "$file")" in
  minute-300.wav)
    echo '[00:00:01.000 --> 00:00:03.000]   Recovered speech at five minutes with enough actual words to trust.' ;;
  minute-360.wav)
    for i in $(seq 1 20); do
      printf '[00:00:01.000 --> 00:00:03.000]   Let us go on a little bit.\n'
    done ;;
  minute-480.wav)
    echo '[00:00:00.000 --> 00:00:59.000]   Thank you.' ;;
  chunk-600.wav)
    echo '[00:00:00.000 --> 00:00:04.000]   The final minute is not omitted from the recorded workshop.'
    for i in $(seq 1 7); do
      echo "[00:00:10.000 --> 00:00:11.000]   I don't know."
    done ;;
  minute-600.wav)
    echo '[00:00:00.000 --> 00:00:04.000]   The final minute is not omitted from the recorded workshop.' ;;
  chunk-0.wav)
    echo '[00:00:00.000 --> 00:00:04.000]   The first five minutes are intact and contain enough words to trust.' ;;
  chunk-300.wav)
    for i in $(seq 1 20); do
      printf '[00:00:01.000 --> 00:00:03.000]   Let us go on a little bit.\n'
    done ;;
  *)
    echo '[00:00:01.000 --> 00:00:03.000]   Another recoverable minute.' ;;
esac
EOF
chmod +x "$BIN/ffprobe" "$BIN/whisper-cli"

out=$(run_transcribe "$ROOT" "$BASE" "$BIN" "$TMP" "$DIR" "$VAULT" "$NOTES" RECORD_AI=0)
note=$(find "$NOTES" -maxdepth 1 -name '*.md' -print)
[ -n "$note" ] || { echo "FAIL: no note: $out"; exit 1; }
grep -qF '[00:00:00.000 --> 00:00:04.000]   The first five minutes are intact and contain enough words to trust.' "$note" \
  || { echo "FAIL: transcript was not segmented into five-minute chunks"; exit 1; }
grep -qF '[00:05:01.000 --> 00:05:03.000]   Recovered speech at five minutes with enough actual words to trust.' "$note" \
  || { echo "FAIL: repeated five-minute chunk was not retried with its original timestamps"; exit 1; }
grep -qF '[00:06:00.000 --> 00:07:00.000]   [Unreliable transcription' "$note" \
  || { echo "FAIL: unrecoverable minute not identified"; exit 1; }
grep -qF '[00:08:00.000 --> 00:09:00.000]   [Unreliable transcription' "$note" \
  || { echo "FAIL: short, untrustworthy output presented as speech"; exit 1; }
grep -qF 'Some audio intervals could not be transcribed reliably' "$note" \
  || { echo "FAIL: note does not alert the reader to unreliable transcript spans"; exit 1; }
grep -qF '[00:10:00.000 --> 00:10:04.000]   The final minute is not omitted from the recorded workshop.' "$note" \
  || { echo "FAIL: final partial chunk was dropped"; tail -15 "$note"; exit 1; }
if grep -qF 'Let us go on a little bit.' "$note"; then
  echo "FAIL: hallucinated repetitions reached the note"
  exit 1
fi
if grep -qF "I don't know." "$note"; then
  echo "FAIL: brief repeated hallucinations mixed with real speech reached the note"
  exit 1
fi
echo "transcribe_hallucination: ok"
