# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
