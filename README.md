# nethack-bugreport

A small public repository for reporting reproducible
[NetHack](https://github.com/NetHack/NetHack) bugs as recorded session
files. Each bug ships with:

1. A **session JSON** that records the exact keystream, rng seed,
   datetime, and `.nethackrc` needed to reproduce — plus the screen
   state at every step.
2. A **`repro.sh`** that re-runs the session through a freshly-built
   NetHack 5.0 recorder binary and asserts the bug fires.
3. A **proposed patch** against `NetHack/NetHack@HEAD`.
4. A **`README.md`** explaining what's wrong, why it happens, and
   what the fix does.

Bug recordings can be **visualized in-browser** without rebuilding
anything: open `tools/session-viewer/index.html` and load any
session JSON. The viewer renders the recorded TTY frames step-by-step
with a scrubber, so reviewers can see exactly what the player saw.

This repo is a derivative of
[davidbau/teleport-contest](https://github.com/davidbau/teleport-contest)
(the public template for the Teleport coding challenge) — it shares
the same session JSON format, the same recorder build, and the same
session viewer. It is **not** a contest entry; it just reuses the
infrastructure.

## Bugs

| # | Title | Severity | Status |
|---|---|---|---|
| [01](bugs/01-vault-guard-parkguard-newsym/) | `impossible("newsym: attempting screen update for <0,0>")` when vault guard parks | low (cosmetic + extra `--More--`s, no state corruption) | unreported upstream as of 2026-05-24 |

## Setup (once)

```bash
git clone --recursive https://github.com/davidbau/nethack-bugreport.git
cd nethack-bugreport
bash setup.sh
```

`setup.sh` checks out the NetHack/NetHack submodule at the same tag
the bugs were recorded against, applies the small set of marker
patches needed by the recorder (in `nethack-c/patches/`), and builds
the recorder binary at `nethack-c/recorder/install/games/lib/nethackdir/nethack`.
The patches do NOT change game logic — only add a stdout marker
stream so the session driver can step the binary one input at a time
deterministically.

## Reproducing a bug

```bash
bash bugs/<NN>-<slug>/repro.sh
```

Runs the bug's `session.json` through the recorder binary and
asserts the expected error appears in the captured output. Exits 0
on confirmed-bug, 1 on bug-not-found (which typically means upstream
has fixed it — please open a PR to mark the entry resolved).

## Visualizing a session

Open `tools/session-viewer/index.html` in any modern browser; load
a session JSON via the file picker. Use the scrubber to step through
the recorded frames. No build, no server, no network needed.

## Filing a new bug

1. Record a session that triggers the bug. Easiest method: replay
   in the [Teleport browser port](https://mazesofmenace.ai/play/)
   with the live parity-check server enabled, which writes a
   candidate session JSON on every divergence.
2. `mkdir bugs/NN-slug/` (next number, descriptive slug).
3. Copy the session into `bugs/NN-slug/session.json`.
4. Write `README.md` with: symptom, repro steps, root-cause analysis
   referencing specific files/lines in `nethack-c/upstream/src/`.
5. Write `proposed-fix.patch` against upstream HEAD.
6. Write `repro.sh` that runs the session and asserts the bug.
7. Add a row to the top-level README table.
8. Open a PR (or push directly if you have access).

## Conventions

- Bug directories are numbered `01`, `02`, … with a short
  hyphenated slug describing the symptom.
- `session.json` is clean-v5 format
  (`{version, segments[{seed, datetime, nethackrc, moves, steps,
  checkpoints}], source, recorded_with}`).
- Proposed patches target upstream `NetHack/NetHack@HEAD` (not the
  patched recorder binary). Patches should NOT depend on the marker
  patches in `nethack-c/patches/` — those are for the recorder only.

## License

Bug reports + this repo's infrastructure code are under MIT.
The bundled NetHack source (`nethack-c/upstream/`) is under
[NetHack General Public License (NGPL)](https://github.com/NetHack/NetHack/blob/NetHack-3.7/dat/license).
