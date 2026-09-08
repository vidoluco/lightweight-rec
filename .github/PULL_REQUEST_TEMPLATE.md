# What this changes

<!-- One or two sentences. What behaviour is different after this merges. -->

# Why

<!-- The problem, not the patch. Link the issue if there is one. -->

# How it was verified

<!--
CI is the floor, not the proof. It has no Screen Recording, Microphone or
Accessibility grant, no BlackHole, no skhd, no whisper model and no claude
CLI, so it cannot observe a single real recording. Say what you ran by hand.
-->

- Commands run:
- Mac and macOS version:
- Display setup, if the change touches capture or the red dot:

# Checklist

- [ ] `./test/run.sh` passes on a real Mac with the display awake (the record-dot tests need a live screen).
- [ ] `shellcheck -x -S warning` is clean over the files CI lints, or the new suppression is justified in `.shellcheckrc`.
- [ ] Exercised end to end by hand: started a recording, stopped it, and confirmed the note landed where the config says it should, with the expected content.
- [ ] A test covers the change, or this PR says which permission grant makes that impossible.
- [ ] `README.md` and `config.example` still describe reality, and no personal path, vault name, hostname or device name is in the diff.
