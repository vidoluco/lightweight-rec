#!/bin/bash
# Break this would catch: a private identifier shipped in the published tree,
# such as somebody's home directory, iCloud vault, named device or bundle
# prefix left behind as a default or an example.
#
# It matches CLASSES of private data, never one person's values. A guard
# written as a list of real names is itself the leak it was meant to stop, and
# it protects nobody but the one person whose names are in it. This file is
# scanned like every other: a guard that excludes its own source cannot see
# what it carries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The right single quotation mark macOS puts in a device name, built from octal
# so this file stays pure ASCII and carries no typographic character of its own.
APOS=$(printf '\342\200\231')

# One class per entry. Every pattern is written so that it cannot match its own
# text in this file, which is what makes scanning this file possible.
PATTERNS=(
  # a home directory belonging to a named account
  "/Users/[A-Za-z0-9._-]{2,}"
  "/home/[A-Za-z0-9._-]{2,}"
  # iCloud Drive, its container folders and the app that owns them
  "Mobile[[:space:]]+Documents"
  "com~apple~[A-Za-z]"
  "iCloud~[A-Za-z]"
  # a knowledge vault or notebook named after its owner: a KB or PKM prefix
  # glued to a personal name is the usual shape
  "(KB|PKM|Zettelkasten|SecondBrain|Vault|Obsidian)-[A-Za-z0-9]{2,}"
  # a device named after its owner. The owner is capitalised, which keeps
  # ordinary prose about a stranger's Mac out of the results
  "[A-Z][A-Za-z]{1,}['${APOS}]s[[:space:]]+(iPhone|iPad|iMac|MacBook|Mac|Apple[[:space:]]+Watch|AirPods)"
  # one particular monitor, dock or drive model, which identifies a single desk
  "(HP|Dell|LG|BenQ|Acer|ASUS|Samsung|AOC|ViewSonic|Philips|Iiyama|Lenovo)[[:space:]]+[A-Z]{0,3}[0-9]{2,5}"
  # a reverse-DNS bundle prefix built from somebody's own name or domain
  "(^|[^A-Za-z0-9.-])(com|org|net|io|co|it|de|fr|es|nl|uk|us|ai|dev|app|me|eu)\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*"
)

# What the classes above are allowed to match, and why. Keep this list short:
# every entry is a hole in the guard.
#   app.lightweight-rec.*   the CoreAudio device UIDs this project owns
#   com.apple.*             Apple's own keys and bundle identifiers
#   /Users/you and friends  documentation placeholders, not an account
ALLOW='app\.lightweight-rec\.|com\.apple\.|/Users/(you|your|user|username|USER|name|NAME|<)'

fail=0
for pattern in "${PATTERNS[@]}"; do
  hits=$(grep -RInE "$pattern" "$ROOT" \
    --exclude-dir .git \
    --exclude-dir build \
    || true)
  hits=$(printf '%s' "$hits" | grep -vE "$ALLOW" || true)
  if [ -n "$hits" ]; then
    if [ "$fail" -eq 0 ]; then
      echo "FAIL: private identifiers in the published tree."
      echo "Replace them with a placeholder, or read them from config at run time."
    fi
    echo "  pattern: $pattern"
    # Printed relative to the repo, so a failure report does not itself carry
    # the home directory of whoever ran it.
    printf '%s\n' "$hits" | sed "s|^$ROOT/||" | sed 's/^/    /'
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "no_personal_paths: ok"
