#!/bin/bash
# Break this would catch: Option+R dying, with nothing on screen and nothing in
# any log the README names, on a Mac whose home directory has a space in it.
#
# skhd does not exec the right-hand side of a binding itself: it hands the
# whole command to a shell. So `alt - r : $HOME/bin/record toggle` word split
# on a home directory whose name has a space in it: the shell tried to run the
# half of the path in front of the space, found nothing there, and the hotkey
# was dead. The fragment quotes the path for exactly that reason, and
# the two scripts that have to recognise the binding were taught to match both
# the quoted form and the bare one older installs left behind.
#
# Three things are asserted here, and the second is what keeps the first
# honest:
#   a. the shipped binding survives the shell, against a HOME with a space
#   b. the same expansion with the OLD unquoted line fails, so (a) is not
#      passing for some accidental reason
#   c. BINDING_RE, in install.sh and in scripts/uninstall.sh, matches the
#      current binding AND the legacy one, and does not match a stranger's
#      hotkey. The pattern is read out of the two files rather than copied
#      here: a regression that edits one of them must fail this test, not slip
#      past a duplicate that was never updated.
#
# Nothing real is touched: no skhd is started, reloaded or read, the real HOME
# is never passed to anything, and the only thing the expansion can reach is a
# stub inside a throwaway directory under TMPDIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAGMENT="$ROOT/skhdrc"
REAL_HOME="$HOME"

fail=0
bad() { echo "FAIL: $1"; fail=1; }

[ -f "$FRAGMENT" ] || { echo "FAIL: $FRAGMENT is missing"; exit 1; }

BASE=$(mktemp -d "${TMPDIR:-/tmp}/record-skhd-XXXXXX")
case "$BASE" in
  ""|/|"$REAL_HOME"|"$REAL_HOME"/*)
    echo "FAIL: refusing to run, the sandbox root '$BASE' is inside the real HOME"
    exit 1 ;;
esac
trap 'rm -rf "$BASE"' EXIT

# The fixture is half the test. A home directory whose name lost its space
# would pass while proving nothing, so it is checked before anything runs.
SB="$BASE/My Home Dir"
case "$SB" in
  *" "*) ;;
  *) echo "FAIL: the sandbox HOME '$SB' has no space in it"; exit 1 ;;
esac
ARGS="$BASE/args.txt"

mkdir -p "$SB/bin"
# Stands in for ~/bin/record. It records how many arguments it was handed and
# what they were, which is the only way to tell "ran with toggle" apart from
# "ran with two halves of a path and toggle".
cat > "$SB/bin/record" <<'STUB'
#!/bin/bash
set -euo pipefail
{
  printf 'argc=%s\n' "$#"
  for a in "$@"; do printf 'arg=%s\n' "$a"; done
} > "$RECORD_TEST_ARGS"
STUB
chmod +x "$SB/bin/record"

# The command half of an skhd binding: everything after the first colon.
# skhd hands that string to a shell, which is what `sh -c` reproduces here.
command_part() {
  local line="$1" cmd
  cmd=${line#*:}
  printf '%s' "$cmd" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Runs one binding's command the way skhd runs it. Prints nothing, returns the
# shell's exit status. env -i so that nothing of this machine, least of all the
# real HOME, reaches the expansion.
run_binding() {
  local cmd="$1"
  rm -f "$ARGS"
  env -i \
    HOME="$SB" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    RECORD_TEST_ARGS="$ARGS" \
    /bin/sh -c "$cmd" >/dev/null 2>&1
}

# What the stub saw, or empty if it never ran.
stub_saw() {
  [ -f "$ARGS" ] && cat "$ARGS"
}

# ------------------------------------------------ a. the shipped binding
# Read from the file that is actually installed, never retyped: a fragment
# that silently loses its quotes has to fail here.
BINDINGS=$(grep -cE '^[[:space:]]*alt[[:space:]]*-[[:space:]]*r[[:space:]]*:' "$FRAGMENT" || true)
if [ "$BINDINGS" != "1" ]; then
  echo "FAIL: expected exactly one 'alt - r' binding in $FRAGMENT, found $BINDINGS"
  exit 1
fi
SHIPPED=$(grep -E '^[[:space:]]*alt[[:space:]]*-[[:space:]]*r[[:space:]]*:' "$FRAGMENT")
SHIPPED_CMD=$(command_part "$SHIPPED")

if run_binding "$SHIPPED_CMD"; then
  saw=$(stub_saw)
  if [ -z "$saw" ]; then
    bad "the shipped binding exited 0 but ~/bin/record never ran"
  else
    [ "$(printf '%s\n' "$saw" | sed -n 's/^argc=//p')" = "1" ] \
      || bad "the shipped binding handed record $(printf '%s\n' "$saw" | sed -n 's/^argc=//p') arguments, expected 1"
    [ "$(printf '%s\n' "$saw" | sed -n 's/^arg=//p')" = "toggle" ] \
      || bad "the shipped binding handed record '$(printf '%s\n' "$saw" | sed -n 's/^arg=//p')', expected 'toggle'"
  fi
else
  bad "the shipped binding '$SHIPPED_CMD' failed under a HOME containing a space"
fi

# ------------------------------------------------ b. the old unquoted one
# The bug itself, reproduced. If this passes, the expansion above is not
# proving anything and neither is this file.
LEGACY_LINE='alt - r : $HOME/bin/record toggle'
LEGACY_CMD=$(command_part "$LEGACY_LINE")
if run_binding "$LEGACY_CMD"; then
  bad "the unquoted binding survived a HOME with a space: this test cannot detect the bug it exists for"
else
  [ -z "$(stub_saw)" ] \
    || bad "the unquoted binding failed, but ~/bin/record ran anyway: the failure is not the word split"
fi

# ------------------------------------------------ c. BINDING_RE, both files
# Extracted from the scripts, not restated here. A pattern that is edited in
# one file and not the other is a silent half-fix: an install would stop
# recognising what an uninstall still removes, or the other way round.
read_binding_re() {
  local file="$1" hits
  hits=$(grep -c "^BINDING_RE=" "$file" || true)
  if [ "$hits" != "1" ]; then
    echo "FAIL: expected exactly one BINDING_RE declaration in $file, found $hits" >&2
    exit 1
  fi
  sed -n "s/^BINDING_RE='\(.*\)'\$/\1/p" "$file"
}

RE_INSTALL=$(read_binding_re "$ROOT/install.sh")
RE_UNINSTALL=$(read_binding_re "$ROOT/scripts/uninstall.sh")

if [ -z "$RE_INSTALL" ]; then
  echo "FAIL: could not read BINDING_RE out of install.sh (is it still a single-quoted literal?)"
  exit 1
fi
if [ "$RE_INSTALL" != "$RE_UNINSTALL" ]; then
  echo "FAIL: install.sh and scripts/uninstall.sh declare different BINDING_RE patterns."
  echo "      install.sh:            $RE_INSTALL"
  echo "      scripts/uninstall.sh:  $RE_UNINSTALL"
  echo "      They gate the same decision from both ends and must stay identical."
  exit 1
fi

# Must match: the binding as shipped today, and the one older installs wrote.
# Must not match: somebody else's hotkey, which is the line the uninstaller
# refuses to delete.
matches() { printf '%s\n' "$2" | grep -qE "$1"; }

matches "$RE_INSTALL" "$SHIPPED" \
  || bad "BINDING_RE does not match the shipped binding: $SHIPPED"
matches "$RE_INSTALL" "$LEGACY_LINE" \
  || bad "BINDING_RE does not match the legacy binding: $LEGACY_LINE"
if matches "$RE_INSTALL" 'alt - t : open -a Terminal'; then
  bad "BINDING_RE matches a hotkey that is not ours: 'alt - t : open -a Terminal'"
fi

if [ "$fail" -ne 0 ]; then
  echo "skhd_binding: failed"
  exit 1
fi
echo "skhd_binding: ok"
