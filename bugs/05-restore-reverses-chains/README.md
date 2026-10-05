**Title:** Leaving and revisiting a level reverses its trap, stairway, engraving and exclusion-zone lists

**Version:** NetHack 5.0.0 (the same code shape goes back to the 3.x line).
Re-checked 2026-09-18: still present at the `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0);
`stairway_add()` (`stairs.c:8`) still prepends with
`tmp->next = gs.stairs; gs.stairs = tmp;`.

### Symptom

On a level with two staircases in the same direction (the Sokoban entrance
has two up stairs, the Gnomish Mines entrance levels have two down stairs),
"the stairs" switches between them every time the hero leaves the level and
returns. `stairway_find_dir()` and `stairway_find_type_dir()`
(`src/stairs.c`) return the first stairway in the given direction, whatever
its branch. Callers: `choose_stairs()` (`src/wizard.c`; wounded covetous
monsters retreat there), the `makekops` path (`src/shk.c`), Kop respawn
(`src/mon.c`) and Wizard of Yendor tactics (`src/wizard.c`).

A wounded master lich on the Sokoban entrance level camps on one up
staircase; after the hero goes down one level and comes straight back, it
camps on the other. Monsters that follow the hero between levels are not
affected: `stairway_find_from()` matches by destination.

### Cause

Levels are written to a temp file on leaving and read back on return (and
on restore). The read loops rebuild each list by prepending every entry, so
each read reverses the list:

- traps: `getlev()` trap loop, `src/restore.c`
- stairways: `rest_stairs()` via `stairway_add()`, `src/restore.c`
- engravings: `rest_engravings()`, `src/engrave.c`
- exclusion zones: `load_exclusions()`, `src/dungeon.c`

The object list does not have this problem: `restobjchn()` appends, and
`find_lev_obj()` reverses twice so floor piles keep their order.

### Fix

`proposed-fix.patch` reverses each list once after its read loop, e.g. in
`rest_stairs()`:

```diff
+    {
+        stairway *sprev = (stairway *) 0, *scur = gs.stairs, *snxt;
+
+        while (scur) {
+            snxt = scur->next, scur->next = sprev;
+            sprev = scur, scur = snxt;
+        }
+        gs.stairs = sprev;
+    }
```

In `rest_engravings()` the end-of-list `return` becomes `break` so the
reversal runs. Generation-time code is unchanged: `stairway_add()` still
prepends, and `place_branch()` in `mklev.c` still finds the newest stairway
at the head. Code or tooling that has adapted to the alternating order would
see a change; none was found in the tree.

### Repro

`session.json` (seed 23, wizard mode, 105 keys; view it in the session
viewer):

1. On Dlvl 8, the Sokoban entrance (Sokoban stair west, main up stair
   east), create a master lich, quaff monster detection, and zap it once
   with a wand of lightning.
2. Step 87: "The master lich vanishes and reappears farther away." It camps
   by the west (Sokoban) staircase, first in the newly generated list.
3. Level-teleport to Dlvl 7 and straight back.
4. Step 99: "The master lich vanishes and reappears closer to you." It camps
   by the east (main) staircase.

`session-fixed.json` is the same keystream on a build with
`proposed-fix.patch`: at step 99 the lich stays by the west staircase
("...reappears farther away").

`repro.sh` re-records `session.json` through your recorder build and checks
for the step-99 "reappears closer to you" switch; on a fixed build it
reports the bug gone.

### Status

Unreported upstream as of 2026-07-31 (searched
[issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls) for `rest_stairs`,
`stairway_add`, `rest_engravings`, `choose_stairs`, "chain order",
"reversed").
