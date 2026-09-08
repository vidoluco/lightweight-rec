# Third-party software

This repository is original work. It does not vendor, fork or copy source
from the tools it can install. `install.sh` fetches them with Homebrew (and
one model file from Hugging Face) so they stay upstream projects with their
own licenses. Calling a binary as a subprocess does not make this code a
derivative of that binary.

Handy in particular is a separate dictation app by CJ Pais. The optional
`--with-handy` flag only runs `brew install --cask handy`. No Handy source
is in this tree, Option+R here is bound by skhd, and capture still works
if Handy is not installed.

| Project | Role here | License | How it arrives |
|---|---|---|---|
| [ffmpeg](https://ffmpeg.org) | screen and microphone capture, frame extract | LGPL 2.1+ / GPL 2+, depending on the Homebrew build | `brew install ffmpeg` |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | local transcription | MIT, The ggml authors | `brew install whisper-cpp` |
| [ggml-large-v3-turbo-q5_0.bin](https://huggingface.co/ggerganov/whisper.cpp) | the whisper model file | same MIT as whisper.cpp | curl from Hugging Face, size and SHA-256 pinned in `install.sh` |
| [skhd](https://github.com/koekeishiya/skhd) | Option+R hotkey | MIT, Åsmund Vikane | `brew install koekeishiya/formulae/skhd` |
| [switchaudio-osx](https://github.com/deweller/switchaudio-osx) | restore the previous audio output | MIT, Devon Weller and Christian Zuckschwerdt | `brew install switchaudio-osx` |
| [BlackHole](https://github.com/ExistentialAudio/BlackHole) | optional loopback for the other side of a call | GPL-3.0 for source. Official binaries and the BlackHole name are copyright Existential Audio Inc. | `brew install --cask blackhole-2ch`, only with `--with-blackhole` |
| [Handy](https://github.com/cjpais/handy) | optional push-to-talk dictation, unrelated to capture | MIT, CJ Pais | `brew install --cask handy`, only with `--with-handy` |

The AI CLI named by `RECORD_AI` is optional and proprietary: `claude`
(Anthropic), `cursor-agent` (Cursor) or `copilot` (GitHub). None of them is
open source, none is installed by this project, and `RECORD_AI=0` turns the
call off.

This project's own code is MIT, see [LICENSE](LICENSE).
