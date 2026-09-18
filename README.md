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
| [01](bugs/01-vault-guard-parkguard-newsym/) | `impossible("newsym: attempting screen update for <0,0>")` when vault guard parks — via `postmov()` | low (cosmetic + extra `--More--`s, no state corruption) | **fixed upstream in `c42d35eac`**; the second path, [09](bugs/09-see-monsters-parked-guard/), was fixed later in `d13eceb28` |
| [02](bugs/02-wizborn-totals/) | `#wizborn` totals row computed via `Sprintf` but never `putstr`'d (wizmode summary row missing) | low (wizmode-only cosmetic) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [03](bugs/03-tutorial-alignment-collision/) | Tutorial dungeon silently inherits `AM_CHAOTIC` via `UNCONNECTED` ↔ `D_ALIGN_CHAOTIC` bit collision in `init_level` | low (latent — suppressed downstream by `tut-1.lua`'s `nomongen`) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [04](bugs/04-make-glib-xor-typo/) | The "Slip" status condition never displays — `make_glib` botl-dirty test inverted by a one-`!` typo | low (visible with `OPTIONS=cond_slip`; gameplay unaffected) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [05](bugs/05-restore-reverses-chains/) | Leaving and revisiting a level reverses its trap/stairway/engraving/exclusion lists — "first staircase" flips identity, moving covetous-monster retreats and Kop spawn points on two-staircase levels | low (visible on Sokoban/Mines entrance levels) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [06](bugs/06-polymon-nested-rehumanize/) | One polymorph, two artifact blasts: `polymon()` keeps running after something inside it has already undone the polymorph, so `retouch_equipment()` runs twice | low (player-visible duplicate message and damage roll; two DevTeam `FIXME?`s already mark it) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [07](bugs/07-polyself-light-delete-before-create/) | Polymorphing into a glowing form can print "Program in disorder!": the hero's light source is created one stack frame too late, so an interrupted polymorph deletes a source that does not exist yet | low (`impossible()`; also leaks a source permanently on the `were.c` path, and stops the DevTeam's fuzzer) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [08](bugs/08-break-armor-stale-form/) | The game takes a reverted hero's water walking boots off while they stand in lava, because `break_armor()` is still applying the old form's rules | **medium (fatal)** — kills a hero who would otherwise survive | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [09](bugs/09-see-monsters-parked-guard/) | Redrawing the screen just after a vault guard leaves prints `newsym(0,0)`'s `impossible()`: `see_monsters()` was missing the off-map guard that `monmove.c`, `minion.c`, `sp_lev.c` and `wizard.c` all have | low (`impossible()`; hard stop under the DevTeam's fuzzer) | **fixed upstream in [`d13eceb28`](https://github.com/NetHack/NetHack/commit/d13eceb28bc84a36d09254a7e1d8b939115afab6)** (2026-06-14) |
| [10](bugs/10-polyself-reentrant-form-changes/) | **Explanatory bundle for 06, 07 and 08**: polymorphing is not atomic, and the code after the form change assumes it is. One rule, three defects, one unified fix branch | medium (08 is fatal) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [12](bugs/12-fort-ludios-annotation-flip/) | Fort Ludios never gets its `#overview` annotation on the half of games where `flip_level_rnd()` mirrors the level: the award looks for the throne four columns to the left of the entrance, and after a flip it is four columns to the right | low (cosmetic, but affects ~half of all games) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |

Bundle 11 is reserved for a dwarven-digging arithmetic bug that is
analysed but not yet written up, so the numbering skips it for now.

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

For example, [bug 07 at the step the assertion
fires](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session.json#step=127):

```
https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session.json#step=127
```

`#step` is read on load and rewritten as you scrub, so every frame has
its own shareable URL.

Locally: serve the repo root over HTTP (e.g. `python3 -m http.server`)
and open `http://localhost:8000/tools/session-viewer/` — load any
session JSON via the file picker. `file://` won't work because the
viewer `fetch()`s the session by relative URL.

## Proposed patches as branches

Each bundle ships its fix as a `proposed-fix.patch` against the pinned
upstream commit. For the bugs where that patch has been built and
verified, the same change is also committed to a branch of a NetHack
fork, so it can be read as a diff in the browser and fetched directly:

| bug | branch | diff |
|---|---|---|
| 06 | `bugreport/06-polymon-nested-rehumanize` | [commit 8076a1822](https://github.com/davidbau/NetHack/commit/8076a18220413d8bc6e0ff871c06fa420c8f5793) |
| 07 | `bugreport/07-polyself-light-delete-before-create` | [commit 9a5fcf78e](https://github.com/davidbau/NetHack/commit/9a5fcf78e91d292faee9295e4a4e6424efec6cc7) |
| 08 | `bugreport/08-break-armor-stale-form` | [commit e38656987](https://github.com/davidbau/NetHack/commit/e38656987319c8e62f13c428ef3ae6837f7faa3a) |
| 09 | `bugreport/09-see-monsters-parked-guard` | [commit f7f5a644c](https://github.com/davidbau/NetHack/commit/f7f5a644ce2cc579dc4ad5630d36148cb822c9ee) (superseded by upstream `d13eceb28`) |
| 06+07+08 | `bugreport/10-polyself-reentrancy` | [3-commit compare view](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/10-polyself-reentrancy) |
| 12 | `bugreport/12-fort-ludios-annotation-flip` | [commit 6d3963b4a](https://github.com/davidbau/NetHack/commit/6d3963b4a1c9f32602acac246a1e47fc4b1fdc05) |

All three branch from `NetHack/NetHack@16ff59115`, the commit the
`nethack-c/upstream` submodule is pinned to and the commit every session
here was recorded against, so each branch contains exactly one commit and
its diff is exactly the proposed patch.

```bash
git remote add bugfix https://github.com/davidbau/NetHack.git
git fetch bugfix bugreport/07-polyself-light-delete-before-create
```

## Filing a new bug

There are two bundle shapes that work, depending on whether the
bug has a screen-visible symptom or is pure C-source math:

### Shape A: session-replay (visible symptom)

Use this when the bug produces a screen-visible plinediff a player
would notice in normal play (bug 01 vault-guard `--More--`
cascade; bug 02 `#wizborn` missing totals row).

1. Record a session that triggers the bug.  Easiest method: replay
   in the [Teleport browser port](https://nethack.games/)
   with the live parity-check server enabled, which writes a
   candidate session JSON on every divergence.
2. `mkdir bugs/NN-slug/` (next number, descriptive slug).
3. Copy the session into `bugs/NN-slug/session.json`.
4. *(Optional but recommended)* re-record the same session against
   a C binary with `proposed-fix.patch` applied and ship the result
   as `session-fixed.json`.  The rebuild loop is a ~30s round-trip for a
   one-`.c` change: patch the source, `make` the one object file, relink,
   copy the binary into the install path, and re-record the session with
   its `steps` and `checkpoints` stripped so the whole keystream replays.
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
