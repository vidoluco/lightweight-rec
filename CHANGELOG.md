# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `RECORD_AI` takes a model server as well as a CLI: `ollama` and `lmstudio`
  on this Mac, `openai`, `anthropic`, `gemini` and `openrouter` out on the
  network, and `custom` for anything else that speaks the same
  `/chat/completions` protocol. `record` builds the request itself and curl
  sends it; the screen frames travel in the body as base64 images. The note,
  and everything else in the pipeline, is unchanged.
- With `ollama` or `lmstudio` the tool has what it never had before: the
  title, the tags, the summary and the description of what was on screen, with
  the frames and the transcript never leaving the Mac, no account and no bill.
  It is the setting to use if `RECORD_AI=0` was only ever about egress.
- `RECORD_AI_URL` points any backend at another endpoint: a second Mac on the
  network, a gateway, a server on a port of its own. Required by `custom`.
- `RECORD_AI_KEY`, read from the config file or from the provider's usual
  variable (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
  `OPENROUTER_API_KEY`). It reaches curl through a config file written `600` in
  the run's scratch directory, never on the command line, where `ps` would
  show it to anything running as you.
- `RECORD_AI_FRAMES` (8) caps how many of the extracted frames one HTTP screen
  call carries, evenly spread over the hour: a chat request holds every image
  it names, and thirty of them is what makes a local model fall over. The CLIs
  read the frames off disk themselves and ignore it. `RECORD_AI_TIMEOUT` (600)
  is how long curl waits, which a small model on a laptop needs.
- Left with no model to ask for, a local backend asks the server which models
  it has and takes the first, so a one-model Ollama needs no model line at all.
  That request is also how a server that is not running is caught: the run says
  nothing answered at the address, the note says it too, and not one frame is
  extracted.
- Two more reasons a note can arrive without a summary, each said in the note
  in its own words rather than looking like a deliberate off switch: no API key
  for a hosted backend, and an endpoint that refused the model, whose own error
  is kept in `.transcribe.log`.

### Changed

- The message for an unknown `RECORD_AI` lists every name that works, CLI and
  server alike, instead of naming the three CLIs.
- `README`, `SECURITY.md` and `config.example` are explicit about which
  backends are egress and which are not, and the `any-cli.svg` drawing now
  cycles through the local and hosted servers too.

## [0.3.0] - 2026-09-09

Verified end to end on Apple Silicon, macOS 26: a real take with the
microphone pinned to a silent device and speech played through the speakers
came back transcribed, so the words could only have arrived through the new
path; the output device stayed selected and the volume keys kept working.

### Changed

- System audio is captured natively. `record-audio` now asks ScreenCaptureKit
  for what the Mac is playing and streams it into a FIFO that ffmpeg reads as
  a second input, mixed with the microphone at the same balance as before.
  BlackHole, the two aggregate devices (`Record-In`, `Record-Out`) and the
  output switch are gone: no driver, no admin password at install, the output
  device is never touched, and the volume keys work during a take.
- Requires macOS 13 or newer, where ScreenCaptureKit learned to capture audio.
  `install.sh` says so in preflight instead of failing in the compiler.
- `install.sh` no longer installs `switchaudio-osx` and accepts
  `--with-blackhole` only to say it is not needed any more. On a Mac that ran
  an earlier version it removes the leftover aggregates, restores the output
  the old state file names, and points out the BlackHole cask can go.
- The start line names the microphone it opened and whether system audio is
  mixed in; `record status` says the same while a take runs.

### Added

- `record mic`: the microphone the next start would open, resolved the way a
  start does it, and the state of the system audio switch. Read only.
- A start that cannot get system audio still starts, microphone only, and
  prints the helper's own reason, kept in `$RECORD_DIR/.sysaudio.log`.

### Removed

- `record-audio up` and `record-audio which`. `down` stays for the leftovers
  of older versions and takes the previous output's name to restore it.

## [0.2.0] - 2026-09-08

Verified end to end on Apple Silicon with all three CLIs on a real one-minute
recording before release.

### Added

- `RECORD_AI` picks the CLI that writes the title, tags, summary and screen
  description: `claude` (the default, unchanged), `cursor` (Cursor CLI,
  `cursor-agent`) or `copilot` (GitHub Copilot CLI). Each is driven in its own
  headless, read-only shape: Cursor in ask mode inside the scratch directory,
  Copilot with the frames as attachments and every tool off.
- `RECORD_AI_VISION_MODEL` and `RECORD_AI_META_MODEL` override the model of
  each call. Defaults: `sonnet` and `haiku` on claude, `cursor-grok-4.6-high`
  on cursor, `gemini-3.8-flash` on copilot.
- The note now says why a summary is missing in every case: the switch is
  off, the name is not a known CLI, the CLI is not installed, or it is
  installed and did not answer, with its own error kept in `.transcribe.log`.
- An animated README: header, pipeline, the plug-any-CLI diagram and the
  note as it is filed are SVGs under `docs/`, generated by `docs/gen-svg.py`.

### Changed

- The off switch is `RECORD_AI=0`. `RECORD_CLAUDE=0` still means off.
- The AI CLI's stderr is no longer discarded: it lands in `.transcribe.log`.

### Fixed

- whisper.cpp 1.9 prints backend banners on stderr; they were captured with
  the transcript and opened every transcript section in the note.
- Copilot wraps its output at 100 columns, which cut a summary to its first
  line. Continuation lines are folded back onto their field for every CLI.

## [0.1.0] - 2026-08-27

First public release. macOS only, Apple Silicon.

### Added

- `record`, one bash entry point (`start`, `stop`, `status`, `toggle`,
  `screens`, `transcribe`), bound to Option+R through skhd.
- Capture: one display at 1 fps plus the microphone, hardware HEVC, around
  110 MB per hour, one mp4 per hour, and a red dot on the display being recorded.
- Full call audio when BlackHole 2ch is installed, built around whatever audio
  output is current and restored afterwards. Without it, the microphone alone.
- Devices resolved by name on every start, so a plugged in iPhone cannot shift
  an index. `RECORD_MIC` pins an input on every path, the BlackHole one
  included, where it names the microphone inside `Record-In`; left empty, the
  resolver finds a real microphone and never a loopback or a virtual one.
- On stop: whisper.cpp transcribes locally, then a Markdown note is filed in
  your vault. The optional `claude` CLI adds the title, tags, summary and a
  description of the screen; without it the note is still written. Videos stay
  on the Mac and are referenced by path.
- A video that cannot be decoded, which is what an interrupted recording leaves
  behind, costs that file alone: it is skipped, the rest of the session is still
  transcribed and filed, and the note lists what was dropped under
  **Not transcribed**.
- The skhd binding is written with the path quoted, so a home directory whose
  name contains a space still fires the hotkey. `install.sh` and
  `scripts/uninstall.sh` recognise both that form and the older unquoted one, so
  an existing install is detected and cleaned up either way.
- Retention: every start deletes this tool's own videos older than
  `RECORD_DAYS` (14), matching only the timestamped names it writes itself.
- `install.sh`, plus `scripts/uninstall.sh`, which removes only what the
  installer wrote, never a recording, a note or someone else's skhd binding.
- Settings in `~/.config/record/config` (see `config.example`), tests under
  `test/`, CI, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, MIT `LICENSE`.
