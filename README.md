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
anything. The viewer is hosted as a GitHub Pages site, and each bug
gets a deep-link URL that shows the recorded TTY frames step-by-step
with a scrubber:

  https://davidbau.github.io/nethack-bugreport/

You can also serve `tools/session-viewer/` locally over HTTP
(`python3 -m http.server` from the repo root) and load any session
JSON via the file picker — no build, no JS port, no dependencies.

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
| [02](bugs/02-wizborn-totals/) | `#wizborn` totals row computed via `Sprintf` but never `putstr`'d (wizmode summary row missing) | low (wizmode-only cosmetic) | unreported upstream as of 2026-06-19 |
| [03](bugs/03-tutorial-alignment-collision/) | Tutorial dungeon silently inherits `AM_CHAOTIC` via `UNCONNECTED` ↔ `D_ALIGN_CHAOTIC` bit collision in `init_level` | low (latent — suppressed downstream by `tut-1.lua`'s `nomongen`) | unreported upstream as of 2026-06-19 |
| [04](bugs/04-make-glib-xor-typo/) | The "Slip" status condition never displays — `make_glib` botl-dirty test inverted by a one-`!` typo | low (visible with `OPTIONS=cond_slip`; gameplay unaffected) | unreported upstream as of 2026-07-31 |
| [05](bugs/05-restore-reverses-chains/) | Leaving and revisiting a level reverses its trap/stairway/engraving/exclusion lists — "first staircase" flips identity, moving covetous-monster retreats and Kop spawn points on two-staircase levels | low (visible on Sokoban/Mines entrance levels) | unreported upstream as of 2026-07-31 |

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

Hosted: https://davidbau.github.io/nethack-bugreport/. Each bug in
the index table on that page links into the viewer with the
session pre-loaded. Direct-link form:

```
https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=<RELATIVE_PATH_TO_SESSION_JSON>#step=<N>
```

Locally: serve the repo root over HTTP (e.g. `python3 -m http.server`)
and open `http://localhost:8000/tools/session-viewer/` — load any
session JSON via the file picker. `file://` won't work because the
viewer `fetch()`s the session by relative URL.

## Filing a new bug

There are two bundle shapes that work, depending on whether the
bug has a screen-visible symptom or is pure C-source math:

### Shape A: session-replay (visible symptom)

Use this when the bug produces a screen-visible plinediff a player
would notice in normal play (bug 01 vault-guard `--More--`
cascade; bug 02 `#wizborn` missing totals row).

1. Record a session that triggers the bug.  Easiest method: replay
   in the [Teleport browser port](https://mazesofmenace.ai/play/)
   with the live parity-check server enabled, which writes a
   candidate session JSON on every divergence.
2. `mkdir bugs/NN-slug/` (next number, descriptive slug).
3. Copy the session into `bugs/NN-slug/session.json`.
4. *(Optional but recommended)* re-record the same session against
   a C binary with `proposed-fix.patch` applied and ship the result
   as `session-fixed.json`.  See the staging-area
   [workflow notes](https://github.com/davidbau/teleport/blob/main/docs/upstream-reports/README.md)
   for the rebuild loop (~30s round-trip for a one-`.c` change).
5. Write `README.md` with: symptom, repro steps, root-cause
   analysis referencing specific files/lines in
   `nethack-c/upstream/src/`.
6. Write `proposed-fix.patch` against upstream HEAD.
7. Write `repro.sh` that runs the session and asserts the bug.
8. Add a `<tr>` row to `index.html` with a `▶ replay` link into the
   viewer (and `▶ replay (after fix)` if `session-fixed.json` is
   included).
9. Add a row to this README's "Bugs" table above.

### Shape B: static C reproducer (math-only or invisible symptom)

Use this when the bug is in pure expression math whose semantics
don't depend on game state (bug 03 Tutorial alignment bit
collision).  These bugs are typically *latent* — real defects
whose visible effect is masked by other safety nets in stock 5.0
play — but still worth filing for code-quality and future-proofing
reasons.  Prefer Shape A whenever an in-game symptom can be
provoked at all: bug 04 started life as Shape B ("no visible
symptom") until enabling the opt-in `OPTIONS=cond_slip` status
condition turned it into a screen-visible Shape A recording.

1. `mkdir bugs/NN-slug/`.
2. Write `repro.c` — self-contained C program that hard-codes the
   relevant macros from `nethack-c/upstream/include/`, exercises
   both the buggy and proposed-fix expressions, prints a truth
   table, and exits 0 if the bug fires / 1 if it doesn't.
3. Write `repro.sh` that just `${CC:-cc} -o repro repro.c && ./repro`
   and reports the exit status.  No NetHack build required.
4. Write `README.md` explaining the bug, citing the C file:line,
   listing downstream consumers (and which ones, if any, would
   fire if the bug weren't suppressed by an overlapping safety net).
5. Write `proposed-fix.patch` against upstream HEAD.
6. Add a `<tr>` row to `index.html` with a `view repro.c` link
   (no `▶ replay` since there's no session).
7. Add a row to this README's table.

### Shared steps

- Open a PR (or push directly if you have access).
- Before pushing: search NetHack/NetHack issues + PRs for the
  bug; if already reported, link the existing issue in the
  README's "Status" line rather than adding a new bundle.
- Severity convention: `low (cosmetic)` for visible-but-harmless;
  `low (latent — <why>)` for masked-in-practice; `medium`+ for
  state-affecting; `high` for crash / corruption.

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
