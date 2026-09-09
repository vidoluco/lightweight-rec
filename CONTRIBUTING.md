# Contributing

Read the scope first: the fastest way to waste an afternoon here is a good
patch for something this project has decided not to be.

## Scope

One hotkey and four moving parts: ffmpeg captures a display at 1 fps plus
audio, whisper.cpp transcribes it locally, an optional AI CLI (`claude`,
`cursor-agent` or `copilot`, picked by `RECORD_AI`) writes a title, tags and a
summary, and a Markdown note lands in your own vault. No
database, no index, no daemon, no UI, and it is meant to stay that way.

Welcome: correctness and robustness fixes, especially on hardware the author
does not own (Mac mini, Mac Studio, iMac, Intel, external displays); anything
that turns a silent failure into a visible one; safety work, meaning not
clobbering user files, scoping deletes, a clean uninstall; documentation that
stops overpromising; and tests for the pure helpers in `record-lib.sh`.

Declined even when the code is good: a search index, a database, OCR or
embeddings over past sessions; a GUI, menu bar app or dashboard; Linux or
Windows, since the whole thing is AVFoundation, CoreAudio, AppKit and skhd; a
daemon that records without being asked; a plugin system or a provider
abstraction; moving video into the vault, or uploading anything anywhere.

More than a bugfix? Open an issue first. Small and boring lands quickly.

## Tests

```bash
./test/run.sh
```

Each test is an executable `test/*.test.sh` that prints `<name>: ok` and exits
0, or a `FAIL:` line and exits non-zero. `run.sh` globs that one directory, so
a new test needs no wiring: follow the shape of the existing ones, starting
with a comment saying what breakage it would catch. That comment is the point
of the test. Shared helpers live in `test/lib/` and are not picked up as tests.

A test that calls `swiftc` builds a helper and opens a window, so `run.sh`
skips it when there is no Swift toolchain, no graphical session, or no display
that is actually awake. That last check is its own small CoreGraphics probe
rather than the binary under test, so a broken overlay cannot turn its own
failure into a skip. `RECORD_TEST_STRICT=1` makes every skip a failure,
`RECORD_TEST_VERBOSE=1` prints the output of passing tests.

## shellcheck

The CI gate is severity `warning` over every shell file in the tree. CI
discovers that set (every `*.sh`, plus every file whose first line is a `sh`
or `bash` shebang) so a new script cannot ship unlinted. Locally:

```bash
shellcheck -x -S warning record $(find . -name '*.sh' -not -path './.git/*')
```

Per-code exceptions live in `.shellcheckrc`, each next to its reason, so a
local run behaves like the CI one. Anything else needs a narrow
`# shellcheck disable=SCxxxx` on the line, plus a comment saying why.

## Style

- bash, `set -euo pipefail`, quoted variables, `$HERE` from
  `${BASH_SOURCE[0]}` so a script works from the clone and from `~/bin`
- comments explain WHY. A comment restating the line below it is noise.
- English everywhere, and no em dash or en dash: use a comma, a colon or
  parentheses. Nothing enforces this one. No test and no CI job looks for it,
  it is read off the diff by hand, so a miss earns a review comment and not a
  red build.
- no personal paths, machine names or vault names in the tree. Defaults go in
  `config.example`, real values in `~/.config/record/config`.
- prefer failing loudly to failing quietly. The wrong microphone recorded, a
  note filed where nobody looks, or no note written at all are the failures
  that make a stranger decide the tool does not work and never open an issue.
  Every `|| true` needs a comment saying why that failure is acceptable.

## Working on it without wrecking your own recordings

`record start` deletes its own old videos, switches your system audio output,
and opens whatever `RECORD_LAUNCH_APP` names. Give it a scratch home:

```bash
mkdir -p /tmp/rec-dev/notes
cat > /tmp/rec-dev/config <<'CONF'
RECORD_DIR="/tmp/rec-dev"
RECORD_NOTES="/tmp/rec-dev/notes"
CONF
export RECORD_CONFIG=/tmp/rec-dev/config
./record status
```

`record` sources `$RECORD_CONFIG` before it reads `RECORD_DIR` and friends, so
the config file wins over the environment: put your test values in the file.
The model path follows `RECORD_DIR`, so symlink your real `.whisper` directory
in rather than downloading it twice. Run `./record` from the clone, not
`record` from your PATH: until you re-run `./install.sh`, the file you edited
and the file Option+R runs are two different ones.

## Shooting the demo

The README has a demo slot, currently an empty HTML comment, and the picture
that belongs in it is the biggest thing still missing from the page. Capture
one of the two below, drop the file in `docs/`, and uncomment the image line
under the comment. That is the whole job.

Before you record anything, point the tool at a scratch vault for one take.
Whatever is in that frame is published forever, including the meeting name,
the client name, a real transcript, and your vault path in the Obsidian window
title. Set `RECORD_VAULT` and `RECORD_NOTES` to a throwaway folder, record
something you invented, then set them back.

**Option A, a short GIF.** The better one: the pitch is a gesture and a still
cannot show a gesture. Six to ten seconds, three cuts, no dead air and no
cursor hunting:

1. Option+R pressed, the red dot appearing on the captured display
2. hard cut, the same screen a while later, Option+R again
3. hard cut, the finished note open in Obsidian, scrolled once

Keep it under 10 MB or GitHub will not play it inline. Record with the
built-in screen recorder (Shift+Cmd+5), then:

```bash
ffmpeg -i take.mov -vf "fps=12,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" docs/demo.gif
```

If that comes out over 10 MB, drop `fps=12` to `fps=8`, or `1200` to `1000`.
Save it as `docs/demo.gif`, which is the name the README slot already carries.

**Option B, one screenshot.** Cheaper, still far better than nothing: a
generated note open in Obsidian in READING view, not the raw Markdown, the
window about 1400 px wide, with the title, the tags, the summary, the screen
section and the timestamped transcript all in one frame. Save it as
`docs/demo.png` and change `.gif` to `.png` on the README image line.

## What CI cannot prove

Screen Recording, Microphone and the Accessibility grant skhd needs are given
per binary, by hand, in System Settings. CI has none of them, and no
whisper model and none of the AI CLIs either, so it never
observes a real recording. The start, capture, stop, transcribe, note path is verified by
a human on real hardware or not at all.

That makes the pull request text load-bearing. Say what you exercised by hand
and on what machine (chip, macOS version, one display or several, headphones
or speakers), and what you did not try. Running only the pure tests is
fine, just say so, and never describe the manual path as verified when it was
not.

One concern per pull request, and a diff small enough to read in one sitting.
Explain the failure the change fixes, not the change itself: the diff already
shows what you did.
