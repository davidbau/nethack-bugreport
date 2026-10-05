**Title:** `init_level()` treats every `UNCONNECTED` dungeon as chaotic (the Tutorial gets `AM_CHAOTIC`)

**Version:** NetHack 5.0.0 (also in the 3.7 line). Re-checked 2026-09-18:
still present at the `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0);
`dgn_file.h` still has `UNCONNECTED 0x10` and
`D_ALIGN_CHAOTIC (AM_CHAOTIC << 4)`, also `0x10`.

### Symptom

Every Tutorial level gets `flags.align = AM_CHAOTIC` instead of `AM_NONE`.
The Tutorial is the only stock dungeon with `unconnected` and no `alignment`
key (Sokoban has `alignment = "lawful"`).

There is no in-game symptom today, because nothing on the Tutorial levels
reads `flags.align`:

1. `tut-1.lua:30-31` and `tut-2.lua:3-4` set `nomongen`, so `makemon.c:1168`
   returns before `rndmonst()` and `align_shift()` run.
2. Every Tutorial corpse has an explicit `montype` (`sp_lev.c:2262`), so
   `rndmonnum()` does not run either.
3. There is no `des.altar` or `AM_SPLEV_RANDOM` placement, the callers of
   `induced_align()` (`dungeon.c:2004`).

A new `UNCONNECTED` dungeon without an `alignment` key, or removing one of
these gates, would expose it: under `AM_CHAOTIC`, `align_shift()`
(`makemon.c:1621`) adds +1 to +3 to the spawn weight of every monster with
`maligntyp` below +15. It was found by calling `rndmonst_adj()` directly on a
Tutorial level: cumulative weights `5,8,11,...,39` in C against
`3,4,5,...,21` for `AM_NONE`. `peace_minded()` is unaffected.

### Cause

`include/dgn_file.h`:

```c
#define UNCONNECTED     0x10                /* bit 4 */
#define D_ALIGN_CHAOTIC (AM_CHAOTIC << 4)   /* also 0x10 */
#define D_ALIGN_MASK    0x70
```

`dat/dungeon.lua` gives the Tutorial `flags = { "mazelike", "unconnected" }`
and no `alignment`. `init_dungeon_set_dungeon()` stores `.flags = 0x14` and
`.align = D_ALIGN_NONE` (`dungeon.c:1056-1057`). The fallback in
`init_level()` (`dungeon.c:583-591`) reads alignment from `.flags` instead
of `.align`:

```c
new_level->flags.align = ((tlevel->flags & D_ALIGN_MASK) >> 4);
if (!new_level->flags.align)
    new_level->flags.align =
        ((pd->tmpdungeon[dgn].flags & D_ALIGN_MASK) >> 4);   /* 0x14 -> 1 */
```

### Fix

Read the parsed `.align` field:

```diff
     if (!new_level->flags.align)
-        new_level->flags.align =
-            ((pd->tmpdungeon[dgn].flags & D_ALIGN_MASK) >> 4);
+        new_level->flags.align = pd->tmpdungeon[dgn].align >> 4;
```

`D_ALIGN_{NONE,CHAOTIC,NEUTRAL,LAWFUL} >> 4` gives exactly
`AM_{NONE,CHAOTIC,NEUTRAL,LAWFUL}`. The per-level `tlevel->flags` line is
left as is. Moving `D_ALIGN_*` out of bits 4-6 would also work but changes
the save format. Full diff: `proposed-fix.patch`.

### Repro

```bash
bash bugs/03-tutorial-alignment-collision/repro.sh
```

No setup. `repro.sh` compiles `repro.c`, a standalone program that copies
the macros from `align.h` and `dgn_file.h` and evaluates both the
`init_level()` fallback and the fixed expression. It exits 0 on the tip:

```
    (tutorial_flags & D_ALIGN_MASK)       = 0x10
    >> 4                                   = 0x01   (AM_CHAOTIC)
...
Proposed fix (read the parsed .align instead):
    tmpdungeon[dgn].align >> 4             = 0x00   (AM_NONE)

BUG REPRODUCED: init_level fallback yields AM_CHAOTIC, but the
Lua-parsed alignment is AM_NONE.
```

There is no `session.json`: the effect is not visible on screen.

### Status

Unreported upstream as of 2026-06-19 (searched
[issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls) for `Tutorial alignment`,
`UNCONNECTED chaotic`, `init_level align`, `D_ALIGN_MASK`,
`dungeon flags collision`, `align_shift Tutorial`).
