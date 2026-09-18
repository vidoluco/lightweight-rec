<img src="docs/header.svg" alt="lightweight-rec. One shortcut records the screen at one frame per second with the microphone, transcribes on the Mac, and files a Markdown note in your vault." width="100%">

Press Option+R. One display is recorded at 1 frame per second, with your
microphone and what the Mac is playing, all locally. Press it again: a Markdown
note with the transcript lands in the Obsidian vault you already use. Title,
tags and summary come from a coding CLI you already have signed in (Claude
Code, Cursor or Copilot), from a model running on the Mac itself through Ollama
or LM Studio, from an API, or from none of them.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%20(Apple%20Silicon)-lightgrey.svg)](#requirements)
[![CI](https://github.com/vidoluco/lightweight-rec/actions/workflows/ci.yml/badge.svg)](https://github.com/vidoluco/lightweight-rec/actions/workflows/ci.yml)

<!-- Demo slot: drop a real capture in as docs/demo.gif and uncomment the line below.
     How to shoot it: CONTRIBUTING.md, "Shooting the demo". Until then, the drawing
     of the note stands in. -->
<!-- ![Option+R, a red dot on the captured display, and the note it files in Obsidian](docs/demo.gif) -->

The note is the product. This one was filed as
`2026-05-14 1132 Retry Budget For The Ingest Worker.md`:

<img src="docs/note.svg" alt="The Markdown note lightweight-rec files: frontmatter with tags and date, a title, a summary, the path of the video, what was on screen with timestamps, and the transcript." width="100%">

<details>
<summary>The same note as Markdown</summary>

```markdown
---
tags: [meeting,backend,retry-policy]
date: 2026-05-14
type: recording
---

# Retry Budget For The Ingest Worker

The pair walked through the ingest worker's retry path and agreed the fixed
5-attempt loop is what produces Monday's duplicate rows. They settled on
exponential backoff with a dead-letter queue after the third failure, and left
the alert threshold for a follow-up.

**Video** (on the Mac, deleted after 14 days):
- `/Users/you/Recordings/2026-05-14_09-30.mp4`

*Timestamps in the transcript are relative to the matching hour's video:*
*each section below is named after its file.*

## What was on screen

### 2026-05-14 09-30
- (at 0:00) A terminal on a branch named feature/ingest-retry. The prompt shows
  a failing test run: 2 failed, 41 passed.
- (at 12:40) A browser tab titled "Ingest worker dashboard" shows a table with
  the headers attempt, status, duration_ms. Three rows read 5, error, 30000.

## Transcript

## 2026-05-14 09-30
[00:00:00.000 --> 00:00:06.400]  So the duplicates all come from the same worker, every one of them on the fifth attempt.
[00:00:06.400 --> 00:00:14.200]  Right, and we never mark the row as consumed, so the retry writes it again.
```

</details>

## How it works

One mp4 per hour, a red dot on the captured display while a take runs, and
transcript sections named after their video file, so the note takes you to the
right minute of the right hour.

<img src="docs/rec-flow.svg" alt="Option R, then capture at one frame per second with the microphone, whisper on the Mac, an optional pass through the CLI or model server named in RECORD_AI for title, tags and summary, and a Markdown note in your vault. The grey dot is the path with RECORD_AI=0." width="100%">

<details>
<summary>The same pipeline as text</summary>

```
Option+R ──► red dot on the captured display (Capture screen N, default 0)
             ffmpeg: 1 fps screen + microphone, hardware HEVC
             record-audio: what the Mac plays, captured natively, mixed in
                 │        one mp4 per hour in ~/Recordings  (~110 MB/hour)
                 │        each start deletes this tool's own mp4 files in that
                 │        folder older than RECORD_DAYS (14 by default)
Option+R ──► stop │
                 ▼
             whisper-cli (large-v3-turbo q5_0, local) transcribes with timestamps
                 ▼
             what RECORD_AI names reads the evenly spaced screen      optional:
             frames, then picks title, tags and summary               a CLI, an
                 │                                                    API, or a
                 │                                                    local model
                 │        RECORD_AI=0 skips both calls and extracts no frames:
                 │        nothing leaves the Mac and the note is still written
                 │        RECORD_AI=ollama keeps it all here too, with the note
                 │        complete: the model runs on this Mac
                 ▼
             note in the Obsidian vault, folder Recordings/  (text only)
```

</details>

## Why it exists

Rewind shut down in December 2025. Screenpipe, OpenRecall, LUCI and Trace
share one architecture: periodic screenshots, OCR, a database, a daemon and a
search UI over your timeline. This goes the other way.

- **1 fps video, not screenshots plus OCR.** One HEVC file per hour is cheaper
  than a screenshot corpus, and it plays back.
- **No daemon, no index.** Nothing runs until you press Option+R. Nothing
  survives the stop but the mp4 files and the note.
- **The note lives in your vault.** Search is whatever your vault already does.

It is a written record of a work session, not a searchable timeline of your
day. So, deliberately: no background capture, no OCR or full-text index, no
timeline browser or menu bar app, no cloud, no account, no telemetry, no
redaction or app exclusion list. macOS 13 or newer, Apple Silicon only.

## Plug any CLI, or a model of your own

<img src="docs/any-cli.svg" alt="One config line, RECORD_AI, picks what writes the title, tags, summary and screen description: Claude Code, Cursor CLI, Copilot CLI, or any model server that speaks the chat completions protocol, Ollama and LM Studio on this Mac included. The note is the same either way." width="100%">

One line in `~/.config/record/config` picks what writes the title, tags,
summary and screen description. Nothing else changes, the note included.

A CLI you already have signed in, driven in its own headless mode:

| `RECORD_AI` | Binary | Default models | How the frames reach it |
|---|---|---|---|
| `claude` (default) | `claude` | `sonnet` frames, `haiku` metadata | by path, `Read` tool only |
| `cursor` | `cursor-agent` | `cursor-grok-4.6-high` | read-only ask mode, workspace limited to the scratch directory |
| `copilot` | `copilot` | `gemini-3.8-flash` | as attachments, every tool off |

Or a model server, called over HTTP in the `/chat/completions` shape all of
them speak. `record` writes the request itself and curl sends it; the frames
travel inside it as base64 images:

| `RECORD_AI` | Endpoint | API key | Default models |
|---|---|---|---|
| `ollama` | `http://localhost:11434/v1` | none | the first model the server lists |
| `lmstudio` | `http://localhost:1234/v1` | none | the first model the server lists |
| `openai` | `https://api.openai.com/v1` | `OPENAI_API_KEY` | `gpt-5.4-mini` |
| `anthropic` | `https://api.anthropic.com/v1` | `ANTHROPIC_API_KEY` | `claude-sonnet-5` frames, `claude-haiku-4-5` metadata |
| `gemini` | `.../v1beta/openai` | `GEMINI_API_KEY` | `gemini-3.8-flash` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | `google/gemini-3.8-flash` |
| `custom` | `RECORD_AI_URL` | `RECORD_AI_KEY`, if it wants one | none: name the model |

```bash
RECORD_AI=ollama                    # or lmstudio, openai, claude, ... or 0 for no call
RECORD_AI_VISION_MODEL=qwen3-vl:8b  # optional: the model that reads the frames
RECORD_AI_META_MODEL=qwen3-vl:8b    # optional: the model that writes title, tags, summary
RECORD_AI_FRAMES=8                  # optional: frames one screen call carries
```

**`ollama` and `lmstudio` are the setting to know about.** They are the only
way to have the whole thing: a title, tags, a summary and a description of what
was on screen, with the frames and the transcript never leaving the Mac, no
account, no key and no bill. Pull a vision model first (`ollama pull
qwen3-vl:8b`, or load one in LM Studio) and start the server; a model that
cannot see images will write the summary and say nothing useful about the
screen. With one model installed the config needs no model line at all: `record`
asks the server what it has. With several, name the one you want, because the
first one listed is whatever sorts first, not whatever is best.

`RECORD_AI_URL` overrides the endpoint of any of them, which is how a second
Mac on the network (`http://studio.local:11434/v1`), a gateway, or any other
server that speaks the same protocol gets used without a name of its own here.
The key is never passed on the command line: curl reads it from a file written
`600` in the run's scratch directory and deleted with it.

Model ids are the ones the backend lists itself. `install.sh` installs and
checks none of this. A model that is not there makes the call fail and the note
says so, with the endpoint's own words in `.transcribe.log`; it never falls back
to another model silently. Neither does a server that is not running: the note
names the address nothing answered at.

## Requirements

| Item | Detail |
|---|---|
| OS | macOS 13 or newer, Apple Silicon. Hardware HEVC for the video, ScreenCaptureKit for the system audio. Intel untested. |
| Homebrew, Xcode CLT | Dependencies come from brew, the two Swift helpers are built with `swiftc`. `install.sh` checks both before writing anything. |
| Disk | 574 MB once for the whisper model, then about 110 MB per recorded hour. See [Cost and footprint](#cost-and-footprint). |
| Microphone | Any. Resolved on every start (built-in first, then any real microphone, never a loopback or meeting-app device), or pinned with `RECORD_MIC`. |
| System audio | Nothing to install: no driver, no admin password, output device and volume keys untouched. See [Full call audio](#full-call-audio). |
| An AI CLI, an API key, or a local model server | Optional, and the only piece that is ever paid or off-machine. Ollama or LM Studio on this Mac is neither. Without any of them the note still lands with the full transcript and a generic title. |

## Quickstart

```bash
git clone https://github.com/vidoluco/lightweight-rec.git
cd lightweight-rec
./install.sh
```

The installer puts four files in `~/bin`, adds it to `PATH` in `~/.zshrc`,
writes `~/.config/record/config` from `config.example` if absent, fetches the
whisper model (verified by size and SHA-256) and wires the hotkey. Open a new
terminal afterwards. `--with-handy` adds Handy, an unrelated dictation app; it
is the only extra and it is off by default.

**Your skhd config is safe.** The binding lives in its own file,
`~/.config/skhd/lightweight-rec.skhdrc`; your `skhdrc` gets one `.load` line,
after a timestamped backup, and is left alone entirely if it already binds
`alt - r`. A running skhd is reloaded, never restarted.

Then, once, in System Settings, Privacy and Security: **Accessibility**,
**Screen Recording** and **Microphone** for skhd (`/opt/homebrew/bin/skhd`).
Screen Recording also covers the system audio capture.

## Usage

| Command | Effect |
|---|---|
| `Option+R` | start or stop, with a notification. A second tap within 20 s is ignored: it meant start, not stop |
| `record status` | running or idle, which screen, which audio, disk used by the videos |
| `record screens` | displays, their ffmpeg index, which one is recorded |
| `record mic` | the microphone the next start would open, and the system audio switch. Read only |
| `record stop` | force stop, inside the 20 s window too |
| `record transcribe` | file the note for a session that was never filed |

Closed the lid without stopping? The hours already written are intact and
`record stop` the next morning transcribes them. A segment left unreadable is
skipped and named in the note; the rest still becomes the note.

## Configuration

Machine-specific settings go in `~/.config/record/config`, the one file
Option+R reads (skhd does not load your shell rc). `config.example` lists
every key.

| Variable | Default | What it controls |
|---|---|---|
| `RECORD_DIR` | `~/Recordings` | mp4 files, logs, pid files, `.whisper/` with the model |
| `RECORD_VAULT` | `~/Documents/Obsidian` | vault root, the base for `RECORD_NOTES` |
| `RECORD_NOTES` | `$RECORD_VAULT/Recordings` | folder the note is written to |
| `RECORD_SCREEN` | `0` | which `Capture screen N` is recorded; `record screens` lists them |
| `RECORD_MIC` | empty | microphone by name, exactly as ffmpeg lists it; empty resolves one on every start |
| `RECORD_SYSTEM_AUDIO` | `1` | `0` records the microphone alone: on headphones, only your own voice |
| `RECORD_AI` | `claude` | `claude`, `cursor`, `copilot`, `ollama`, `lmstudio`, `openai`, `anthropic`, `gemini`, `openrouter`, `custom`, or `0` for no call and no egress |
| `RECORD_AI_VISION_MODEL` | empty | model that reads the frames; empty is the backend's default |
| `RECORD_AI_META_MODEL` | empty | model that writes title, tags and summary; empty is the backend's default |
| `RECORD_AI_URL` | empty | endpoint of the model server, ending at `/v1`; empty is the default of the backend named above, and it is required by `custom` |
| `RECORD_AI_KEY` | empty | API key, when the provider's usual variable is not set; local servers need none |
| `RECORD_AI_FRAMES` | `8` | frames one HTTP screen call carries, evenly spread; the CLIs read the frames themselves and ignore it |
| `RECORD_AI_TIMEOUT` | `600` | seconds one HTTP call may take before curl gives up |
| `RECORD_CLAUDE` | `1` | the old name of the off switch; `0` still means off |
| `RECORD_DAYS` | `14` | this tool's own mp4 files older than this are deleted on the next start |
| `RECORD_LAUNCH_APP` | empty | an app to open once the capture is up |
| `RECORD_DOT`, `RECORD_AUDIO` | `~/bin/record-dot`, `~/bin/record-audio` | the two helpers, if you moved them |
| `RECORD_CONFIG` | `~/.config/record/config` | the config file itself, read from the environment only |

Switches turn off on `0`, `no`, `off` or `false`; anything else, a typo
included, leaves the feature on. `RECORD_AI` is the exception: an unknown name
makes no call and the note says which name it found, next to the list of the
names that work.

The cleanup on start is bounded to the top level of `RECORD_DIR` and to files
named the way ffmpeg writes them, `2026-05-14_09-30.mp4`. Give it a directory
of its own anyway.

## Full call audio

On headphones the microphone hears only you. So every start also captures what
the Mac is playing and mixes it into the same mono track at half the
microphone's level. `record-audio`, one of the two Swift helpers, gets it from
ScreenCaptureKit and streams it to ffmpeg over a FIFO: no loopback driver, no
aggregate device, your output stays selected and the volume keys keep working.
The audio is taken before the output mixer, so a muted headset still records
the call.

`RECORD_SYSTEM_AUDIO=0` turns it off. If the capture cannot start, the take
still starts with the microphone only and prints the helper's reason, kept in
`$RECORD_DIR/.sysaudio.log`. The usual cause is a missing Screen Recording
grant for whatever launched the start, skhd or your terminal.

## Privacy and consent

Read this before you record a meeting.

- **Captured:** one display at 1 fps, whatever is on it, plus the microphone
  and the system audio for the whole take. No exclusion list, no pause.
- **Stays on the Mac:** the mp4 files and the transcription. Videos never
  enter the vault, so they never reach iCloud.
- **Leaves the Mac:** only the optional AI call, and only when `RECORD_AI`
  names something off this machine. Per mp4, the screen frames (8 to 30 for a
  CLI, `RECORD_AI_FRAMES` of them for an API); per session, the first 30000
  bytes of the transcript. They go to that vendor and on to its model
  provider. `RECORD_AI=0` removes it entirely: no call, no frames extracted.
  `RECORD_AI=ollama` or `lmstudio` keeps the call and sends it to a model on
  this Mac, so nothing leaves either. Details in [SECURITY.md](SECURITY.md).
- **Retention:** this tool's own mp4 files older than `RECORD_DAYS` go on the
  next start. Notes are never deleted.
- **Other people:** the recording holds everyone on the call and what they
  shared. Consent rules differ by jurisdiction and employer, and the tool has
  no compliance features. Say you are recording, or stop.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Option+R does nothing | `skhd --restart-service`. Then the Accessibility grant for skhd, or another binding on `alt - r` that the installer reported and left alone |
| "Did not start" | The reason is in `$RECORD_DIR/.record.log`. A `command not found` means skhd's `PATH` lacks `/opt/homebrew/bin`: export it in `~/.config/record/config` |
| Wrong microphone recorded | Every start prints the microphone it opened. Pin `RECORD_MIC` to the exact name from `ffmpeg -f avfoundation -list_devices true -i ""` and check with `record mic` |
| "Cannot find the audio input named ..." | `RECORD_MIC` is compared whole, literally and case-sensitively. Copy the name from the device list |
| "Cannot find Capture screen N" | Usually a monitor was unplugged. `record screens` lists what is there |
| "System audio unavailable" | The helper could not start; its reason is in `$RECORD_DIR/.sysaudio.log`. Almost always the Screen Recording grant for skhd or your terminal. The take still runs, microphone only |
| No red dot, recording running | `record status` is the reliable answer. The overlay runs detached and can give up silently after a wake on an external monitor |
| No note appeared | The log is `$RECORD_DIR/.transcribe.log`. `Whisper model missing` means re-run `./install.sh`. A note titled `Recorded session` says in its first lines why the summary is missing |
| "Nothing answered at http://localhost:11434/v1" | The local model server is not running, or is on another port. Start Ollama or LM Studio's server, or point `RECORD_AI_URL` at it |
| Summary fine, screen section empty or useless | The model cannot see: pull a vision model (`ollama pull qwen3-vl:8b`) and name it in `RECORD_AI_VISION_MODEL`. The endpoint's own error, if there was one, is in `.transcribe.log` |
| Note exists, Obsidian does not show it | `RECORD_NOTES` is outside any vault (no `.obsidian` above it). The stop said so and printed the path; set `RECORD_VAULT` |
| Output stuck on `Record-Out` | Only after upgrading from a version before 0.3: `~/bin/record-audio down`, then pick your output in Sound settings |

## Uninstall

```bash
record stop
./scripts/uninstall.sh
```

It prints the plan and asks before removing anything (`--yes` skips the
question), and refuses to run while a take is live. It removes the four files
from `~/bin`, the skhd fragment and the single `.load` line it appended to your
skhdrc, after timestamped backups, and any Record-In or Record-Out device a
version before 0.3 left. Videos, notes, vault, whisper model, config, the
`PATH` line and the Homebrew packages stay; the script lists them and prints a
removal command only for the paths it is safe to name.

## Cost and footprint

| Item | Number | Where it comes from |
|---|---|---|
| Video bitrate | 200 kbit/s video, 48 kbit/s audio | `-b:v 200k -b:a 48k` in `record` |
| Per recorded hour | about 110 MB | 248 kbit/s over 3600 s |
| An 8-hour day | about 0.9 GB | estimate |
| Steady state at 14 days | about 12 GB | estimate, 8-hour days, default retention |
| Whisper model | 574 MB, once | `ggml-large-v3-turbo-q5_0.bin` |
| CPU while recording | near zero, encoding is on the video hardware | `hevc_videotoolbox` |
| AI calls per session | 1 per mp4 for the frames, 1 for the metadata, 0 with `RECORD_AI=0` | `record`, transcribe path |
| Frames sent per mp4 | 8 to 30, spread over the file, 1400 px wide, to a CLI | `FRAME_MIN`, `FRAME_MAX` |
| Frames sent per mp4 | `RECORD_AI_FRAMES` of those, 8 by default, to a model server | `ai_pick_frames` in `record` |
| Transcript sent | first 30000 bytes | `head -c 30000` before the metadata call |

The AI calls are billed by the CLI's own plan, or by the API key's. On
Anthropic API credit the frames dominate and land between a few cents and
roughly twenty cents per recorded hour; a Flash-class model through Copilot,
Cursor or Gemini is cheaper. These are estimates. `RECORD_AI=0` makes it zero,
and so does `ollama` or `lmstudio`: the cost there is the electricity and the
minute or two your Mac spends on the frames.

## Components

| Piece | Role |
|---|---|
| `record` (this repo) | orchestrates capture, overlay, transcript and note |
| `record-lib.sh` (this repo) | device-list parsing, mic resolution, vault detection; covered by the tests |
| `record-dot` (this repo) | red recording dot on the captured display |
| `record-audio` (this repo) | system audio via ScreenCaptureKit, streamed to ffmpeg over a FIFO; `down` cleans up after versions before 0.3 |
| [ffmpeg](https://ffmpeg.org) | screen and microphone capture, the audio mix, frame extraction |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | local transcription |
| [skhd](https://github.com/koekeishiya/skhd) | binds Option+R |
| [Handy](https://github.com/cjpais/handy) | unrelated dictation app, installed only with `--with-handy` |
| `claude`, `cursor-agent` or `copilot` | title, tags, summary, screen description, through a CLI you already pay for |
| [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai) | the same four, from a model running on this Mac: no key, no bill, no egress. Neither is installed or required by this repo |
| `curl` | carries every `RECORD_AI` that is a server rather than a CLI, local or hosted |
| `docs/gen-svg.py` (this repo) | regenerates the SVGs above: `python3 docs/gen-svg.py docs` |

## Contributing and license

Scope, the test suite, the shellcheck gate and what must be exercised by hand
on a real Mac are in [CONTRIBUTING.md](CONTRIBUTING.md); released changes in
[CHANGELOG.md](CHANGELOG.md). MIT, see [LICENSE](LICENSE). ffmpeg,
whisper.cpp, skhd and Handy are separate upstream projects, not vendored here;
their licenses are in [THIRD_PARTY.md](THIRD_PARTY.md).
