# Session Viewer

A zero-build replay viewer for recorded NetHack sessions. Renders
the canonical TTY frames from a session JSON file step-by-step in
a 24×80 grid, with a scrubber, full keystream, seed, datetime, and
`.nethackrc` shown alongside.

This is the bug-reporting cousin of the
[teleport-contest session viewer](https://github.com/davidbau/teleport-contest/tree/main/tools/session-viewer)
— stripped of the JS-port driver and PRNG-divergence timelines,
since those aren't relevant when the goal is "show reviewers what
the recorded NetHack process printed at every keystroke."

## Usage

**Hosted (recommended):** browse to the published GitHub Pages site:

```
https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/01-vault-guard-parkguard-newsym/session.json
```

The `?session=` query parameter is the path to the session JSON
inside this repo. Append `#step=N` to deep-link to a specific frame.

**Local:** from the repo root, run any static file server (the
viewer fetches the session JSON, so `file://` won't work):

```bash
python3 -m http.server 8080
# then open
# http://localhost:8080/tools/session-viewer/?session=bugs/01-vault-guard-parkguard-newsym/session.json
```

Or skip the URL parameter and use the **Load session file…** picker
in the header to load any `.json` from disk.

## Controls

- **Drag the scrubber** or use ◀/▶ buttons to step.
- **Arrow keys**: ← / → step one frame; PgUp / PgDn step 10; Home / End jump to ends.
- The current keystroke is shown in red above the grid; the next
  ~12 keystrokes follow as preview.
- URL hash `#step=N` updates on every step, so you can copy-paste
  a frame URL.

## Metadata panel (left)

- **seed**: the rng seed passed to NetHack (`NETHACK_SEED=N`).
- **datetime**: the pinned datetime (`NETHACK_DATETIME=YYYYMMDDHHMMSS`)
  used for deterministic replay. Without this NetHack reads the
  wall clock and game content drifts.
- **recorded with**: git short-hashes of the teleport tools and
  the nethack-c submodule that produced the recording.
- **`.nethackrc`** (collapsible): the rcfile content the recorder
  fed into NetHack. Visible to bug reviewers so they can confirm
  no exotic options are involved.
- **moves** (collapsible): the full keystream as the recorder saw
  it (character name on line 1, then keystrokes).

## Notes

- The viewer is self-contained: just `index.html`, `viewer.mjs`,
  `screen-decode.mjs`, `style.css`. No build, no dependencies, no
  network calls except to fetch the session JSON.
- The screen-decode is vendored from the contest template's
  `frozen/screen-decode.mjs` so this repo doesn't need contest
  infrastructure.
- The viewer makes no claims about parity or correctness — it
  just plays back what NetHack printed. The bug READMEs explain
  what's going wrong.
