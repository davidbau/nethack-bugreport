**Title:** On half of all games, Fort Ludios never gets its `#overview` annotation

**Version:** `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0),
checked 2026-09-18; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Present since level flipping was introduced.

### Symptom

After finding the fort's entrance, `#overview` should show:

```
Fort Ludios:
   Level 1: [knox] <- You are here.
       A throne.
       Fort Ludios.
```

On about half of all games the `Fort Ludios.` line never appears, whatever the
player does. `A throne.` and the `Portal to Fort Ludios` branch line still
print.

- [**Seed 19**, x-flipped: `A throne.` then `(end)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session.json#step=105)
- [**Seed 7027**, not flipped: `A throne.` *and* `Fort Ludios.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session-unflipped.json#step=104)
- [**Seed 19 with the patch**: both lines, on the flipped level](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session-fixed.json#step=105)

In both seeds the entrance has gone `SDOOR` to `DOOR` and reached
`lastseentyp`. Map coordinates from the sessions:

| seed | flipped | throne | entrance | entrance x - 4 |
|---|---|---|---|---|
| 7027 | no | x=46, y=10 | x=50, y=10 | x=46, the throne |
| 19 | yes | x=37, y=10 | x=33, y=10 | x=29, empty floor |

### Cause

`count_feat_lastseentyp()`, `case DOOR:`
([`src/dungeon.c:3038-3057`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dungeon.c#L3038-L3057)),
sets `mptr->flags.ludios` (which prints the line,
[`dungeon.c:3656`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dungeon.c#L3656))
only when a throne is four columns to the **left** of the door:

```c
            int ty, tx = x - 4;
            ...
            for (ty = y - 1; ty <= y + 1; ++ty)
                if (isok(tx, ty) && IS_THRONE(levl[tx][ty].typ)) {
```

That matches [`dat/knox.lua`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/dat/knox.lua)
as written (throne `x=43`, entrance `x=47`), but `knox.lua` declares only
`des.level_flags("mazelevel", "noteleport")`, with no `"noflipx"`, so
`flip_level_rnd()`
([`sp_lev.c:968`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L968),
called from
[`sp_lev.c:6049`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L6049)
and
[`sp_lev.c:6493`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L6493))
mirrors it on about half of all seeds. The throne then sits four columns to the
right.

### Fix

Accept the throne on either side ([`proposed-fix.patch`](proposed-fix.patch);
branch
[`bugreport/12-fort-ludios-annotation-flip`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/12-fort-ludios-annotation-flip),
[commit 6d3963b4a](https://github.com/davidbau/NetHack/commit/6d3963b4a1c9f32602acac246a1e47fc4b1fdc05),
[fixed code](https://github.com/davidbau/NetHack/blob/6d3963b4a1c9f32602acac246a1e47fc4b1fdc05/src/dungeon.c#L3038-L3063)):

```c
            for (ty = y - 1; ty <= y + 1; ++ty)
                if ((isok(x - 4, ty) && IS_THRONE(levl[x - 4][ty].typ))
                    || (isok(x + 4, ty) && IS_THRONE(levl[x + 4][ty].typ))) {
```

`knox.lua` has one throne, four columns from the one entrance, so this cannot
give a false positive. The alternative is adding `"noflipx"` to `knox.lua`,
which also fixes it but drops the flipped layout.

Rebuilt and re-recorded on seed 19 (same datetime and keystream): 118 steps and
24,043 RNG entries both ways; stock prints only `A throne.`, patched prints
both lines. Reverting and rebuilding reproduced the stock recording exactly.

### Repro

`bash bugs/12-fort-ludios-annotation-flip/repro.sh` re-records
[`session.json`](session.json) through a freshly built recorder. In wizard
mode it magic-maps the fort, teleports into the throne room, presses `^E` to
find the entrance, re-maps, and reads `#overview`. On the tip it prints
`BUG CONFIRMED — the throne is annotated but 'Fort Ludios.' is not.` (exit 0);
with the patch, `BUG NOT REPRODUCED — both lines present.` (exit 1); exit 2 if
the scenario did not reach the throne room.
