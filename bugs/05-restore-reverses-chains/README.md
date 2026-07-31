# Bug #05 — Leaving and revisiting a level reverses its trap, stairway, engraving, and exclusion-zone lists

**Status:** unreported upstream as of 2026-07-31 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls) for `rest_stairs`,
`stairway_add`, `rest_engravings`, `choose_stairs`, "chain order",
"reversed" — no matching report).

**NetHack version:** 5.0.0 (the same code shape goes back decades in
the 3.x line).

**Severity:** LOW. Almost every lookup into these lists is by map
coordinate, where order cannot matter. But a handful of behaviors take
"the first staircase going up" (or down) from the list, and on levels
that have two staircases in the same direction, *which one that is
changes every time you leave the level and come back.*

## What happens, in plain words

NetHack keeps several per-level things in linked lists: the traps, the
staircases, the engravings, and (for special levels) monster-exclusion
zones. When you walk downstairs, the level you left is written out to a
temp file; when you come back, it is read back in.

The read-back loops rebuild each list by putting every entry it reads
at the *front* of the list. Reading a list front-first and rebuilding
it front-first reverses it — like restacking a deck of cards one card
at a time. Nothing ever un-reverses it, so every leave-and-return trip
flips these lists end for end. Saving and restoring the game does the
same thing, because it uses the same read loops.

(The developers clearly knew about the hazard: the *object* list is
protected from it. `restobjchn()` appends instead of prepending, and
`find_lev_obj()` even does a deliberate double-reversal so that piles
of items on a square keep their stacking order. The other four lists
just never got the same care.)

## Where a player can actually see it

The stairway list is the observable one. The helper functions that
answer "where are the stairs?" (`stairway_find_dir`,
`stairway_find_type_dir` in `src/stairs.c`) walk the list and return
the **first** staircase matching the requested direction — with no
regard for whether it is a branch staircase into another dungeon. On
most levels there is only one staircase per direction and nothing is
observable. But:

- the **Sokoban entrance** level has **two up staircases** (the main
  one and the Sokoban branch), and
- the **Gnomish Mines entrance** levels have **two down staircases**.

On those levels, four behaviors pick "the stairs" by first match:

| caller | what it does |
|---|---|
| `choose_stairs()` (`src/wizard.c`) | a wounded covetous monster (master lich, demon lord, quest nemesis, Vlad, the Wizard) teleports to "the stairs" and camps there to heal and block them |
| `makekops` path (`src/shk.c`) | the Keystone Kops congregate at "the stairs" when you rob a shop |
| Kop respawn (`src/mon.c`) | a dead Kop has a chance to come back "near the stairs" |
| Wizard of Yendor tactics (`src/wizard.c`) | his tactical movement targets "the stairs" |

So: wound a master lich on the Sokoban entrance level and it teleports
to one of the two up staircases and camps there. Hop down one level
and come straight back — the same wounded lich now camps **on the
other staircase.** Do it again and it switches back. The monster's
retreat spot flips on every revisit of the level, driven by nothing
but the list reversal.

(Monsters that follow you between levels, such as pets and
shopkeepers, are *not* affected — their arrival placement uses
`stairway_find_from()`, which matches the stairway by where it leads,
and the two staircases always lead to different places.)

## The recorded demonstration

`session.json` is a complete recording (seed 23, wizard mode, 105
keys) that you can replay in the browser viewer:

1. The hero teleports to dungeon level 8 — the Sokoban entrance for
   this seed, with the Sokoban branch stair on the west side of the
   map and the main up stair on the east side — and reveals the map.
2. She conjures a master lich, drinks a potion of monster detection
   (so the lich stays visible wherever it goes), and hits it with one
   wand-of-lightning bolt.
3. **Step 87:** "The master lich vanishes and reappears farther
   away." — it camps beside the **west (Sokoban branch)** staircase,
   which is first in the freshly generated level's list.
4. She level-teleports away to level 7 and immediately back — one
   leave-and-return, nothing else.
5. **Step 99:** "The master lich vanishes and reappears closer to
   you." — the same wounded lich now camps beside the **east (main)**
   staircase. The revisit reversed the stairway list, so "first up
   staircase" now names the other one.

`session-fixed.json` is the identical keystream re-recorded on a build
with `proposed-fix.patch` applied: at step 99 the lich stays camped by
the **west** staircase ("...reappears farther away"), because the list
kept its order across the revisit.

## The fix

`proposed-fix.patch` adds a single reverse-the-list pass at the end of
each of the four read loops (`getlev`'s trap loop and `rest_stairs` in
`src/restore.c`, `rest_engravings` in `src/engrave.c`,
`load_exclusions` in `src/dungeon.c`), restoring the order that was
written. The read loops themselves are untouched, and generation-time
code — including the `place_branch()` trick in `mklev.c` that relies
on the newest stairway being at the head of the list — is unaffected.

One consideration for upstream: any code or tooling that has silently
adapted to the alternating order would notice this change. I found no
such code in the tree, and the object list already behaves the way
this patch makes the other four behave.

## Test artifacts

- `session.json` — the buggy recording (vanilla 5.0 recorder build).
- `session-fixed.json` — same keystream on a patched build.
- `repro.sh` — re-records `session.json` through your recorder build
  and asserts the flip fires (the step-99 "reappears closer to you"
  camp switch); on a fixed build it reports the bug gone.
- `proposed-fix.patch` — the four reverse-once hunks.
