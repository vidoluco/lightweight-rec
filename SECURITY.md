# Security and privacy

This tool records a screen and a microphone continuously and writes the audio
out as plaintext. That deserves a page of plain description rather than a badge.
Read this before you run it near anyone else.

## It can run with zero egress

Exactly one component ever leaves the machine, the optional AI pass named by
`RECORD_AI`, and one line in `~/.config/record/config` removes it:

```bash
RECORD_AI=0
```

With that set, `record` makes no network request at all. It invokes no CLI and
opens no socket, and it does not even extract the JPEG frames that call would
have read, so no still of your screen is written anywhere, not even to the
scratch directory. `RECORD_CLAUDE=0`, the switch's name in earlier releases,
still means the same thing. ffmpeg still captures and whisper.cpp still transcribes, both
locally, and the note is still written with the complete transcript. What you
give up is the title, the tags, the summary and the description of what was on
screen; the note says so in place of the summary, so a reader is never left
guessing whether the summary was lost or never asked for.

**There is a second way to have no egress, and this one keeps the summary.**
`RECORD_AI=ollama` or `RECORD_AI=lmstudio` sends the frames and the transcript
to a model server on this Mac, over the loopback interface, and nothing crosses
the network card:

```bash
RECORD_AI=ollama
RECORD_AI_VISION_MODEL=qwen3-vl:8b   # a model you have pulled yourself
```

What that is worth saying precisely: the request still leaves `record`, and it
still carries the screen frames and the transcript. It goes to a process
running as you on this machine, one you installed and can stop. Whatever that
server logs, it logs here. Point `RECORD_AI_URL` at another machine and this
paragraph stops applying: it is then a normal network request to that host,
over plain HTTP unless the URL says otherwise, and it is on you to know who
runs it. The rest of this file treats every backend that is not the local two
as egress, which is what it is.

The switch turns off on `0`, `no`, `off` or `false`, in any case. Anything else,
including a typo, leaves it on: a misspelling must not silently disable a
feature, and here it would silently *enable* egress, which is worse.

To be exact about "zero": this is about `record`, the thing that runs when you
press Option+R. `install.sh` does use the network, once, before any recording
exists: Homebrew fetches ffmpeg, whisper.cpp and skhd, and the
574 MB whisper model is downloaded from HuggingFace and checked against a byte
count and a SHA-256 pinned in the script. Nothing of yours goes out in either
direction, and nothing repeats it afterwards.

Everything below applies either way, because none of it is about the network.

## What is captured

**Video.** One display, the one selected by `RECORD_SCREEN` (default `Capture
screen 0`), at 1 frame per second, with the mouse cursor drawn in. Everything
visible on that display is in the file: password manager windows, private
messages, a colleague's shared screen, whatever a browser tab happens to be
showing. Other displays are not captured, and there is no per-application
exclusion and no pause. The only control is stopping.

**Audio.** The microphone, for the whole take, plus what the Mac is playing,
unless `RECORD_SYSTEM_AUDIO` is turned off. The system audio comes from
ScreenCaptureKit, under the same Screen Recording grant the screen capture
needs: no driver, no aggregate device, no change to the output device. It is
mixed with the microphone down to mono. On a call that means the other
participants are recorded, including the ones wearing headphones on the far end,
and this is the intended behaviour of that feature, not a leak in it.
`RECORD_SYSTEM_AUDIO=0` gives it up and records the microphone alone.

**Which microphone.** `RECORD_MIC` names the input, exactly as ffmpeg lists
it. Left empty, the input is resolved on every start: a built-in microphone
under whatever name the Mac model gives it, else any other real microphone,
and never a loopback or a meeting-app device on its own. Every start prints
the microphone it opened, in the terminal and in `$RECORD_DIR/.record.log`,
and `record mic` prints the same answer without opening anything.

**Nothing else.** No keystrokes, no clipboard, no window titles, no browser
history, no network capture, no location, no accessibility tree. The tool
collects pixels and sound and derives everything else from them.

## Recording other people

The microphone runs for the whole session, so a meeting recording is a
recording of everyone in it. The obligations that come with that are real and
they differ by jurisdiction: several US states require every party to consent,
and in the EU a recording of identifiable speech is personal data, which makes
you its controller with everything that follows. Your employer probably also
has a policy about recording internal calls. This is a description of the
situation, not legal advice, and nothing here should be read as clearance to
record anyone.

Practically: say out loud that you are recording, stop when asked, and
remember that the transcript can end up in a folder that syncs.

One honest caveat about the indicator. The red dot is meant to signal that a
capture is running, but it is best effort, not a guarantee. `record` skips it
silently when the helper is missing or not executable, starts it with all output
discarded, and never checks that it came up; `record-dot` does print a reason
and exit when it cannot resolve the display, but it prints it to a stderr that
has been sent to `/dev/null`. An absent dot does not prove that nothing is being
recorded. `record status` is the reliable check, and it is worth running before
you assume you are private.

## Where the data lives

| What | Where | Contents |
|---|---|---|
| Video | `$RECORD_DIR` (default `~/Recordings`), one mp4 per hour, named by date and time | screen pixels and mixed audio |
| State | `$RECORD_DIR/.record.pid`, `.dot.pid`, `.session`, `.lock` (a directory), `.sysaudio.pid`, `.sysaudio.fifo`, `.sysaudio.ready`, `.record.log`, `.sysaudio.log`, `.transcribe.log` | process state, the pipe the system audio flows through while a take runs, ffmpeg and helper errors |
| Whisper model | `$RECORD_DIR/.whisper/` | about 574 MB, not sensitive |
| Note | `$RECORD_NOTES` (default `~/Documents/Obsidian/Recordings`) | full plaintext transcript, the model's description of the screen, and absolute paths to the mp4 files |
| Temporary | one scratch directory per `record transcribe` run, `mktemp -d` under `$TMPDIR` | the 16 kHz wav and, unless `RECORD_AI` is off, the downscaled JPEG frames of the video being read, one video at a time. With a server backend, also the request body being sent (the same frames, base64, and the transcript), the answer, and curl's config file, which holds the API key and is written `600`. An `EXIT` trap removes the directory on every path out, a failed ffmpeg or whisper included |

Nothing is encrypted by this tool. FileVault, if it is on, encrypts the disk
while the Mac is off or logged out, and that is the whole of it: once you log
in the volume is decrypted for everything running as you, so any process of
yours, and anyone who reaches an unlocked session, reads every video and every
note in the clear. Files are created with your default umask, so on a shared
machine check the permissions on `$RECORD_DIR` yourself.

## Video never enters the vault, and why

The note goes into your Obsidian vault. The video does not, ever. The note
references each mp4 by absolute path instead.

That split is deliberate. Vaults are usually synced, through iCloud Drive,
Obsidian Sync, Dropbox or a git remote, and hours of screen capture have no
business being uploaded anywhere. Keeping the video outside the vault means it
stays on the one disk it was written to.

The consequence deserves to be said out loud, because it cuts the other way:
the transcript is the sensitive half, and the transcript is the half that
syncs. Every word spoken in the room, by you and by everyone else, is written
as plaintext Markdown into a folder your sync provider will happily replicate
and keep versions of. If that is not acceptable, point `RECORD_NOTES` at a
directory outside the synced vault.

You are at least told when the notes folder is in no vault at all: as it files
the note, `record` walks up from that folder looking for a `.obsidian`
directory, and when it finds none it says so in a notification and prints where
it actually wrote the file. A note filed outside a vault is loud, not lost.

## The one egress, and the one line that removes it

Every other component runs locally and touches no network. ffmpeg captures,
whisper.cpp transcribes on your machine. The AI pass is the single exception,
and `record transcribe` makes it in two ways:

1. Once per video file, with the vision model (`RECORD_AI_VISION_MODEL`),
   given the frames extracted from that file (JPEG scaled to 1400 px wide, 8
   to 30 of them spread over the hour). It reads and describes them, so those
   images leave `record`. How they get there depends on the backend: `claude`
   is given their paths and its `Read` tool, `cursor-agent` opens them itself
   in read-only ask mode inside a workspace that is the scratch directory and
   nothing else, `copilot` receives them as attachments with every tool
   switched off, and a server backend receives `RECORD_AI_FRAMES` of them
   (8 by default, evenly spread) base64-encoded inside the request body.
2. Once for the whole session, with the metadata model (`RECORD_AI_META_MODEL`),
   given the first 30000 bytes of the transcript and the screen description,
   to produce a title, tags and a summary. That text leaves `record`.

Where it goes is the whole of the difference between the backends:

| `RECORD_AI` | Where the frames and the transcript go |
|---|---|
| `0` | nowhere: no call, and no frames extracted either |
| `ollama`, `lmstudio` | a server on this Mac, over loopback. Nothing reaches the network |
| `claude`, `cursor`, `copilot` | Anthropic, Cursor or GitHub, and on to whichever model provider that vendor routes the model to, under the plan the CLI is signed in with |
| `openai`, `anthropic`, `gemini`, `openrouter` | that provider's API over HTTPS, under the key you configured |
| `custom` | wherever `RECORD_AI_URL` points, which only you know |

For everything below the loopback line, the content of your screen at sampled
instants and what was said in the room are transmitted to a third party and
processed under that account's terms. Retention and training behaviour are
governed by those terms, not by anything in this repository. Those are also
the only settings that cost money. A local server and `RECORD_AI=0` cost
nothing, and so does everything else here: the capture and the transcription
run on your Mac either way.

A server backend also makes one request before any of this: `GET {endpoint}/models`,
to find out which model to ask for, and only when the config named none. It
carries no recording of any kind. Failing it is how a server that is not
running is reported, before a single frame is extracted.

**The key.** `RECORD_AI_KEY`, or the provider's usual variable
(`OPENAI_API_KEY` and so on), is passed to curl in a config file written `600`
in the run's scratch directory and deleted with it, never on the command line,
where `ps` would show it to anything running as you. It is not logged, not
written to the note, and not printed by any subcommand. `record` sends it as a
bearer token to the endpoint you configured and nowhere else.

The default models are `sonnet` and `haiku` on `claude`, `cursor-grok-4.6-high`
on `cursor`, `gemini-3.8-flash` on `copilot` and on `gemini`, `gpt-5.4-mini` on
`openai`, `claude-sonnet-5` and `claude-haiku-4-5` on `anthropic`,
`google/gemini-3.8-flash` on `openrouter`, and on `ollama` and `lmstudio`
whatever model the server lists first. A model the backend does not carry makes
the call fail, and the note says so rather than falling back to another model
silently: you should always be able to tell from the note what was sent where.

Frame sampling is spread across the whole recording, so a call in which other
people's video tiles or shared documents were on screen sends those images too.

**Turning it off.** `RECORD_AI=0`, described at the top of this file, skips
both calls and the frame extraction that feeds the first one. That is the
supported off switch and the one to use. `RECORD_AI=ollama` is the other
answer: the calls happen, the note is complete, and nothing goes out.

**If you never install it at all,** the result is nearly the same but not
identical: the pipeline completes with the title `Recorded session`, the tag
`recording`, no summary and no screen section, and the note says the CLI is
not installed. A CLI that is installed but not signed in, out of credit or
asked for a model it does not have leaves the same note, with a line pointing
at `.transcribe.log`, where the CLI's own error is kept. In both cases the
frames are still extracted to the scratch directory before the call fails.
A server backend has the same shape and one better case: a missing API key, an
endpoint that is not configured and a server that does not answer are all found
before anything is extracted, so no still of your screen is written at all, and
the note names which of the four it was. Prefer the config line.

## Retention

Every `record start` deletes old videos of its own and prints how many it
removed, though that line goes nowhere visible when the start came from the
hotkey. The disk therefore settles on a rolling buffer instead of growing
forever. Three things to know:

- **The window is `RECORD_DAYS`, 14 days by default.** It is a config key, so
  set it in `~/.config/record/config` rather than editing the script.
- **The delete is bounded, in both directions.** It runs at the top level of
  `RECORD_DIR` only, and it matches only the names ffmpeg writes here,
  `YYYY-MM-DD_HH-MM.mp4`. A video of yours sitting in the same folder under
  another name, or one directory down, is not a candidate. Treat that as a
  guard and not as a licence: give `RECORD_DIR` a directory of its own
  anyway, because a file that does match that pattern will go.
- **It only runs on start.** Stop using the tool and nothing is ever deleted:
  the last `RECORD_DAYS` days of recordings sit there indefinitely.

Notes are never deleted. Once the videos age out you keep a full transcript of
a meeting with no recording left to check it against, which is worth
remembering when the transcript says something surprising.

## Purging everything now

Stop first, so ffmpeg closes the current file, then remove the data. Adjust
the paths if you changed the defaults.

```bash
record stop

rm -f  "$HOME/Recordings"/*.mp4
rm -f  "$HOME/Recordings"/.record.log "$HOME/Recordings"/.sysaudio.log \
       "$HOME/Recordings"/.transcribe.log "$HOME/Recordings"/.session \
       "$HOME/Recordings"/.record.pid "$HOME/Recordings"/.dot.pid \
       "$HOME/Recordings"/.sysaudio.pid "$HOME/Recordings"/.sysaudio.fifo \
       "$HOME/Recordings"/.sysaudio.ready
rm -rf "$HOME/Recordings"/.whisper
rm -f  "$HOME/Documents/Obsidian/Recordings"/*.md
```

If you ran a version before 0.3, which used BlackHole, `~/bin/record-audio
down` removes the `Record-In` and `Record-Out` aggregate devices it created.
They were persistent CoreAudio devices, so a session that ended in a crash
could leave one as your default output. Nothing since 0.3 creates them.

Deleting the files is not the end of it, and the leftovers are the part people
forget:

- Emptying the Trash matters, since Finder deletions do not remove the bytes.
- If the vault syncs, deleted notes usually persist in the provider's recently
  deleted area and in its version history for weeks. Delete them there too.
- Obsidian keeps its own copies: a `.trash` folder inside the vault, and file
  recovery snapshots under `.obsidian/`.
- Time Machine and local APFS snapshots hold older versions of both the videos
  and the notes independently of anything you delete now.

## What this does not protect against

There is no authentication, no encryption at rest beyond FileVault, and no
audit log. Anyone with your unlocked machine, any process running as your
user, any backup, and any sync target has full access to the recordings and
the transcripts. Treat `$RECORD_DIR` and the notes folder as the most
sensitive directories on the disk, because for most people they will be.

## Reporting a vulnerability

Report privately through GitHub security advisories:

https://github.com/vidoluco/lightweight-rec/security/advisories/new

Please do not open a public issue for anything that could expose someone's
recordings, or that lets a local process capture screen or microphone through
this tool. Include your macOS version, the chip, the commit you are on, and
the steps to reproduce.

This is a solo side project. Reports are handled on a best effort basis, when
there is time: there is no response time commitment, no fix deadline and no
bounty. If a problem is urgent for you, stop the tool and delete the
recordings rather than waiting for a patch.

Scope is the code in this repository. ffmpeg, whisper.cpp, skhd,
the `claude`, `cursor-agent` and `copilot` CLIs, Ollama, LM Studio or whatever
else answers at `RECORD_AI_URL`, and whatever app you point
`RECORD_LAUNCH_APP` at are
upstream projects with their own reporting channels, and issues in them should
go there. Reports about how this repository uses them unsafely are in scope and
welcome.
