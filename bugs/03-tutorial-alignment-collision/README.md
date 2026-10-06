**Title:** Dungeon alignment: Tutorial levels are chaotic by a bit collision, and no other dungeon's alignment reaches its levels

**Version:** `NetHack-5.0` tip
[`8898570da`](https://github.com/NetHack/NetHack/tree/8898570da). The
dungeon alignment was lost in `9cd928027` (2019, "Lua: remove dgn_comp");
the collision came with `UNCONNECTED` in `fc7a32b86` (2023, the Tutorial).
This is a design question more than a bug report.

**Symptom**

In shipped NetHack, `align_shift()` (src/makemon.c:1611-1636) and
`induced_align()` (src/dungeon.c:2010) see an alignment only on special
levels that declare their own (Oracle, Medusa) and on the Tutorial's levels,
which are chaotic. `alignment` on a dungeon in `dat/dungeon.lua` (Mines
lawful, Sokoban neutral, Vlad's Tower chaotic) has no effect. In 3.6.x it
biased monster generation on every level of that dungeon.

In the Tutorial nothing reads the alignment today: `tut-1.lua` and
`tut-2.lua` set `nomongen`, every corpse has a `montype`, and there is no
random altar.

**Cause**

Two defects. `get_dgn_align()` (dungeon.c:781-794) returns `D_ALIGN_*`,
which is `AM_* << 4` (0x10, 0x20, 0x40).

1. `svd.dungeons[].flags.align` is `Bitfield(align, 3)` (include/dungeon.h:21),
   and dungeon.c:1103 stores the unshifted value in it, so it is 0 for every
   dungeon.
2. `init_level()`'s fallback (dungeon.c:588-591) reads alignment bits from
   `tmpdungeon[].flags`, which since `9cd928027` holds no alignment, only
   flags. `UNCONNECTED` is 0x10, equal to `D_ALIGN_CHAOTIC`
   (include/dgn_file.h:60, 63), so the fallback makes every level of the
   Tutorial (`flags = { "mazelike", "unconnected" }`) chaotic.

**Fix**

There are two choices:

1. Keep today's behavior everywhere except the Tutorial: drop the fallback
   (or mask out `UNCONNECTED`). `proposed-fix.patch` drops it; checked with
   `clang -fsyntax-only`.
2. Restore the 3.6.x design: store `dgn_align >> 4` at dungeon.c:1103 and
   read `tmpdungeon[dgn].align >> 4` in the fallback. This changes monster
   generation and random altar alignment throughout the Mines, Sokoban and
   Vlad's Tower, so it is a balance decision.

An earlier version of this bundle proposed only the fallback change of (2).
That makes special levels inherit their dungeon's alignment (Minetown and
Mines' End lawful, Sokoban neutral, Vlad's Tower chaotic) while filler levels
stay unaligned, which matches neither 3.6.x nor 5.0.

**Repro**

`bash repro.sh` compiles `repro.c`, which copies the macros from `align.h`
and `dgn_file.h`. It prints the fallback's result for the Tutorial's flags
(0x14 gives `AM_CHAOTIC`) against its parsed alignment (`AM_NONE`), and what
a 3-bit field keeps of 0x10, 0x20 and 0x40 (0 each). It exits 0 while the
constants collide.

Unreported upstream (searched
[issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls)).
