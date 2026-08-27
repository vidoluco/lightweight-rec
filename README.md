# lightweight-rec

1 fps screen + mic, all local, ~110 MB/hour. Option+R starts it, the same
key stops it, a red dot shows which display is in the take. On stop,
transcription runs on its own and a note lands in the Obsidian vault.

The command on the machine is still `registra`.

## How it works

```
Option+R ──► red dot on Capture screen N (default 0)
             ffmpeg: 1 fps screen + microphone, hardware HEVC
                 │        one file per hour in ~/Recordings  (~110 MB/hour)
                 │        videos older than 14 days delete themselves
Option+R ──► stop │
                 ▼
             whisper-cli (large-v3-turbo, local) transcribes with timestamps
                 ▼
             claude -p (haiku) picks title, tags and summary
             claude -p (sonnet) reads evenly spaced frames of the screen
                 ▼
             note in the Obsidian vault, folder Recordings/
             (text only: videos stay out of iCloud)
```

Timestamps in the transcript are relative to that hour's video file: from
the note you open the video and jump to the right minute.

## Defaults

| What | Default | Override |
|---|---|---|
| Hotkey | Option+R (`skhd` → `~/bin/registra toggle`) | `~/.config/skhd/skhdrc` |
| Dictation | Option+A, configured inside [Handy](https://github.com/cjpais/handy) | Handy settings |
| Videos | `~/Recordings` | `REGISTRA_DIR` |
| Notes | `~/Documents/Obsidian/Recordings` | `REGISTRA_VAULT` and `REGISTRA_NOTES` |
| Whisper model | `$REGISTRA_DIR/.whisper/ggml-large-v3-turbo-q5_0.bin` | follows `REGISTRA_DIR` |
| Display | `Capture screen 0` | `REGISTRA_SCREEN` |
| Recording indicator | red pulsing dot, top-right of the captured display | |
| Full-call audio | BlackHole 2ch + aggregates `Registra-In` / `Registra-Out` | |

Machine-specific paths (a different vault, a second monitor) go in
`~/.config/registra/config`. skhd does not load your shell rc, so that
file is the override that Option+R actually sees. Copy `config.example`.

```bash
REGISTRA_DIR="$HOME/Recordings"
REGISTRA_VAULT="$HOME/Documents/Obsidian"
REGISTRA_NOTES="$HOME/Documents/Obsidian/Recordings"
REGISTRA_SCREEN=0
```

`registra screens` prints the displays, the ffmpeg device index, and which
one currently has the red dot.

## Components, all free and open source

| Piece | Role |
|---|---|
| `registra` (command in this repo) | orchestrates capture, overlay, transcript, note |
| [ffmpeg](https://ffmpeg.org) | captures screen and microphone |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | local transcription |
| [skhd](https://github.com/koekeishiya/skhd) | binds Option+R to the script |
| [Handy](https://github.com/cjpais/handy) | push-to-talk dictation, independent, launched alongside |
| `registra-dot` | red recording dot on the captured display |
| `registra-audio` | CoreAudio aggregates for mic + system audio |
| `claude` CLI | title, tags, summary, and screen-frame description (the only non-local piece) |

## Install on a new Mac

```bash
git clone https://github.com/vidoluco/lightweight-rec.git
cd lightweight-rec
./install.sh
```

Then three permissions, once, in System Settings → Privacy and Security:

1. **Accessibility** → add `/opt/homebrew/bin/skhd`
2. **Screen Recording** → skhd (macOS asks on the first Option+R)
3. **Microphone** → skhd

After each permission the service restarts itself; if it does not,
`skhd --restart-service`.

## Usage

| Gesture | Effect |
|---|---|
| `Option+R` | start or stop, with a notification |
| `Option+A` (Handy) | dictation, hold to talk |
| `registra status` | running? which screen? how much disk? |
| `registra screens` | list displays and which one would be recorded |
| `registra stop` | force stop even inside the 20s double-tap window |
| `tail -f ~/Recordings/.transcribe.log` | follow a transcription in progress |

Option+R ignores a second tap in the first 20 seconds (that tap meant
"start", not "stop"). To abort a take that just started: `registra stop`.

## Dual displays

ffmpeg sees `Capture screen 0` and `Capture screen 1`. They match
`CGGetActiveDisplayList` order. Default is screen 0 (usually the built-in
panel). Set `REGISTRA_SCREEN=1` in `~/.config/registra/config` to record
the other one.

The red dot is the ground truth: it is drawn on the display that ffmpeg
is capturing, and it is excluded from the capture so it does not end up
in the video. No dot on a monitor means that monitor is not being recorded.

## Full audio on a call (BlackHole)

With headphones, the microphone hears only you: other voices come out of
the headphones and never hit the mic. If BlackHole is installed, every
start creates two virtual devices on the fly:

- **Registra-Out** = current output (AirPods, speakers, whatever is
  selected right now) + BlackHole: you hear everything as before, and a
  copy goes down the "cable"
- **Registra-In** = microphone + BlackHole: ffmpeg records this, so both
  voices

On stop, output returns to what it was and the devices disappear. Without
BlackHole everything still works, but on headphones only your voice is
recorded. Side effect while recording: the volume keys do not drive the
multi-output device; volume is adjusted from the call app.

## Known and intended

- **The microphone records other people too.** On a call, say so or stop.
- If you forget to stop and close the Mac: files already closed (one per
  hour) are safe; you lose at most the last hour. `registra stop` the next
  morning transcribes what is there.
