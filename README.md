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
| [06](bugs/06-polymon-nested-rehumanize/) | One polymorph, two artifact blasts: `polymon()` keeps running after something inside it has already undone the polymorph, so `retouch_equipment()` runs twice | low (player-visible duplicate message and damage roll; two DevTeam `FIXME?`s already mark it) | reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682), with [PR #1681](https://github.com/NetHack/NetHack/pull/1681) |
| [07](bugs/07-polyself-light-delete-before-create/) | Polymorphing into a glowing form can print "Program in disorder!": the hero's light source is created one stack frame too late, so an interrupted polymorph deletes a source that does not exist yet | low (`impossible()`; also leaks a source permanently on the `were.c` path, and stops the DevTeam's fuzzer) | reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682), with [PR #1681](https://github.com/NetHack/NetHack/pull/1681) |
| [08](bugs/08-break-armor-stale-form/) | The game takes a reverted hero's water walking boots off while they stand in lava, because `break_armor()` is still applying the old form's rules | **medium (fatal)** — kills a hero who would otherwise survive | reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682), with [PR #1681](https://github.com/NetHack/NetHack/pull/1681) |
| [09](bugs/09-see-monsters-parked-guard/) | Redrawing the screen just after a vault guard leaves prints `newsym(0,0)`'s `impossible()`: `see_monsters()` was missing the off-map guard that `monmove.c`, `minion.c`, `sp_lev.c` and `wizard.c` all have | low (`impossible()`; hard stop under the DevTeam's fuzzer) | **fixed upstream in [`d13eceb28`](https://github.com/NetHack/NetHack/commit/d13eceb28bc84a36d09254a7e1d8b939115afab6)** (2026-06-14) |
| [10](bugs/10-polyself-reentrant-form-changes/) | **Explanatory bundle for 06, 07 and 08**: polymorphing is not atomic, and the code after the form change assumes it is. One rule, three defects, one unified fix branch, with a formal proof and an [interactive explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/) | medium (08 is fatal) | reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682), with [PR #1681](https://github.com/NetHack/NetHack/pull/1681) |
| [11](bugs/11-dwarf-dig-accumulator/) | The dwarven digging bonus doubles the accumulated effort rather than the per-turn increment, so dwarves dig 2.6x to 5.3x faster instead of 2x, and the advantage is not constant | low (balance; unchanged since 2002) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [12](bugs/12-fort-ludios-annotation-flip/) | Fort Ludios never gets its `#overview` annotation on the half of games where `flip_level_rnd()` mirrors the level: the award looks for the throne four columns to the left of the entrance, and after a flip it is four columns to the right | low (cosmetic, but affects ~half of all games) | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| [13](bugs/13-subroom-roomno-stale-on-restore/) | After the first revisit, subroom squares can belong to the wrong subroom: a shop stops being a shop (its goods are free) and an ordinary room reports "This shop seems to be untended." | low (rare: 3 of ~18,000 generated levels; changes play when it happens) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [14](bugs/14-rebind-key-message/) | Rebinding a key from the `O` menu never says so, and unbinding one reads a freed struct | low (missing message; use-after-free that is harmless on common allocators) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [16](bugs/16-shk-block-door-wrong-room/) | A shopkeeper at his post never blocks a diagonal move through a broken shop door: `block_door()`/`block_entry()` pass a `ROOMOFFSET` room number to `IS_SHOP()` | low (needs a broken or doorless shop door; makes theft and pick-axe entry easier) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [17](bugs/17-alter-cost-next-shkp-loop/) | `alter_cost()` can loop forever: it passes the current shopkeeper back to `next_shkp()`, which starts its scan at its argument | low (latent: a hang if reached; no reachable path found) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [18](bugs/18-water-vault-chest-locked/) | The water-surrounded vault's "forced unlocked" escape chest can be locked: `themerms.lua` passes `olocked`, `des.object()` reads `locked` | low (rare: glass escape item, about 1 vault in 28; the chest is then locked 4 times in 5) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [19](bugs/19-farlook-engraving-overflow/) | Farlook writes one byte past a stack buffer when it quotes an engraving of 219 or more characters | low (1-byte stack overflow, invisible in normal builds; stops ASan and fuzz builds) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [20](bugs/20-crysknife-reload-reversion/) | A fixed crysknife on the floor takes another 10% chance of turning into a worm tooth every time its level is loaded (level change, save, restore) | low (silent item loss for stashed fixed crysknives; saving also consumes random numbers) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [21](bugs/21-mimic-disguise-save/) | Saving a hero who is hiding as a mimic (`#monster`) loses the disguise: after the restore the hero is drawn as the mimic and is no longer hiding | low (silent loss of a disguise; the two kinds of hiding disagree across a save) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [22](bugs/22-look-engrs-glyph-cut/) | The engravings list shows the wrong symbol for an object lying on a ~190-200 character engraving: the overflow guard cuts the encoded glyph in half | low (cosmetic) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [23](bugs/23-perminv-mode-none/) | `OPTIONS=perminv_mode:none` turns persistent inventory on, the opposite of what the Guidebook says | low (the option does the opposite of its documentation; nothing visible on the default Unix tty build) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [24](bugs/24-status-condition-indent/) | With `statuslines:3`, `weaponstatus`/`armorstatus` collide with the indented third-row conditions: weapon and armor vanish, stale condition text is left behind ("Blindnd"), and with `showvers` the conditions are hidden | low (display only; needs statuslines:3 plus weaponstatus/armorstatus) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |
| [25](bugs/25-gem-learned-bill-skip/) | Identifying a gem does not reprice it on a shop bill that has a used-up item ahead of it: `gem_learned()`'s `continue` skips the `++bp` | low (the hero is overcharged, e.g. 800 zm for identified worthless glass) | still present at the `NetHack-5.0` tip [`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked 2026-09-25 |

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
| 06+07+08 | `bugreport/10-polyself-reentrancy` | [4-commit compare view](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/10-polyself-reentrancy) |
| 11 | `bugreport/11-dwarf-dig-accumulator` | [commit de5628951](https://github.com/davidbau/NetHack/commit/de56289519c8b4776fe14d194a58fb7d7c742e37) |
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
