# lightweight-rec

1 fps screen + mic, all local, ~110 MB/hour. Option+R starts it, the same
key stops it, a red dot shows which display is in the take. On stop,
transcription runs on its own and a note lands in the Obsidian vault.

The command on the machine is still `registra`.

## How it works

```
Option+R ──► red dot on Capture screen N (default 0 = built-in)
             ffmpeg: 1 fps screen + microphone, hardware HEVC
                 │        one file per hour in ~/Registrazioni  (~110 MB/hour)
                 │        videos older than 14 days delete themselves
Option+R ──► stop │
                 ▼
             whisper-cli (large-v3-turbo, local) transcribes with timestamps
                 ▼
             claude -p (haiku) picks title, tags and summary
             claude -p (sonnet) reads evenly spaced frames of the screen
                 ▼
             note in the Obsidian vault, folder Registrazioni/
             (text only: videos stay out of iCloud)
```

Timestamps in the transcript are relative to that hour's video file: from
the note you open the video and jump to the right minute.

## This machine (defaults)

These are the values `install.sh` writes and that Option+R uses today.

| What | Value |
|---|---|
| Hotkey | Option+R (`skhd` → `~/bin/registra toggle`) |
| Dictation | Option+A, configured inside [Handy](https://github.com/cjpais/handy) v0.9.5, Whisper Large V3 |
| Videos | `~/Registrazioni` (`REGISTRA_DIR`), HEVC 1 fps, ~110 MB/hour, 14-day buffer |
| Notes | `KB-Ludovico-C98/Registrazioni` (`REGISTRA_VAULT`) |
| Whisper model | `~/Registrazioni/.whisper/ggml-large-v3-turbo-q5_0.bin` |
| Default display | `REGISTRA_SCREEN=0` → Built-in Retina Display |
| Second display | `REGISTRA_SCREEN=1` → HP E233 (1920×1080, above the laptop) |
| Recording indicator | red pulsing dot, top-right of the captured display |
| Full-call audio | BlackHole 2ch + aggregates `Registra-In` / `Registra-Out` |

Override any of it without editing the script:

```bash
export REGISTRA_SCREEN=1          # record the HP instead of the laptop
export REGISTRA_DIR="$HOME/Movies/registra"
export REGISTRA_VAULT="/path/to/vault"
```

`registra screens` prints both displays, the ffmpeg device index, and which
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
| `tail -f ~/Registrazioni/.trascrivi.log` | follow a transcription in progress |

Option+R ignores a second tap in the first 20 seconds (that tap meant
"start", not "stop"). To abort a take that just started: `registra stop`.

## Dual displays

ffmpeg sees `Capture screen 0` and `Capture screen 1`. They match
`CGGetActiveDisplayList` order. On this setup:

- **0** built-in Retina (main, 1512×982 points)
- **1** HP E233 (1920×1080, stacked above the laptop)

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
- Vault notes are written in Italian (the vault language). The tool itself
  is English.
- If you forget to stop and close the Mac: files already closed (one per
  hour) are safe; you lose at most the last hour. `registra stop` the next
  morning transcribes what is there.
