# On half of all games, Fort Ludios never gets its `#overview` annotation

Visit Fort Ludios, find the fort's entrance, and `#overview` should list the
level like this:

```
Fort Ludios:
   Level 1: [knox] <- You are here.
       A throne.
       Fort Ludios.
```

On about half of all games the `Fort Ludios.` line never appears, no matter
what the player does. Searching again, re-mapping, leaving and coming back:
none of it helps, because the condition that awards the line can no longer be
satisfied on that level for the rest of the game.

The annotation is awarded by finding the fort's throne four columns to the
**left** of the entrance. `knox.lua` does place the throne exactly four
columns from the entrance, but it does not forbid horizontal flipping, so
`flip_level_rnd()` mirrors the whole level on roughly half of all seeds. After
a flip the throne is four columns to the **right**, the check looks four
columns past it at empty floor, and no other door on the level has a throne
four columns to its left either.

Nothing else about the fort is affected. The hero still finds the door,
`#overview` still lists the level, the `A throne.` line still prints, and the
`Portal to Fort Ludios` branch line still prints. Only the level's own
annotation is missing, which is presumably why this has gone unnoticed since
level flipping was introduced.

The affected code is `count_feat_lastseentyp()`'s `case DOOR:` arm in
`src/dungeon.c`. It is present at the `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0),
checked 2026-09-18, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/12-fort-ludios-annotation-flip`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/12-fort-ludios-annotation-flip)
holds one proposed commit, verified by rebuild.

Severity: low and cosmetic, but it silently removes a player-visible
annotation on about half of all games.

## Watch it happen

Two seeds, the same scenario, viewable in a browser:

- [**Seed 19**, the level is x-flipped: `A throne.` and then `(end)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session.json#step=105)
- [**Seed 7027**, not flipped: `A throne.` *and* `Fort Ludios.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session-unflipped.json#step=104)
- [**Seed 19 with the patch applied**: both lines, on the flipped level](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/12-fort-ludios-annotation-flip/session-fixed.json#step=105)

The `#overview` panel is on the right of the screen in each. In both seeds the
hero is standing inside the throne room, orthogonally adjacent to the
entrance, and in both the entrance really has been found: `levl[x][y].typ` goes
`SDOOR` to `DOOR` and reaches `lastseentyp`. The only difference between the
first two is which side of the entrance the throne ended up on.

## The geometry, measured

Both recordings carry a map snapshot, so the coordinates can be read out of the
sessions rather than taken on trust:

| seed | flipped | throne | entrance | `x - 4` from the entrance | `#overview` says |
|---|---|---|---|---|---|
| 7027 | no | x=46, y=10 | x=50, y=10 (throne **+** 4) | x=46, the throne | `A throne.` + `Fort Ludios.` |
| 19 | yes | x=37, y=10 | x=33, y=10 (throne **−** 4) | x=29, empty floor | `A throne.` only |

## Reproducing it

```
bash bugs/12-fort-ludios-annotation-flip/repro.sh
```

That re-records [`session.json`](session.json) through a freshly built recorder
binary and checks that the throne is annotated while `Fort Ludios.` is not. It
exits non-zero if both lines appear, which normally means the patch is already
applied.

The scenario itself, in wizard mode: magic-map the fort, wizard-teleport into
the throne room, press `^E` (`findit`) to convert the entrance from `SDOOR` to
`DOOR`, re-map, and read `#overview`.

## What the code is doing

```c
    case DOOR:
        if (Is_knox(&u.uz)) {
            int ty, tx = x - 4;

            /* Throne is four columns to left, either directly in
             * line or one row higher or lower, and doesn't have
             * to have been seen yet.
             *   ......|}}}.
             *   ..\...S}...
             *   ..\...S}...
             *   ......|}}}.
             * For 3.6.0 and earlier, it was always in direct line:
             * both throne and door on the lower of the two rows.
             */
            for (ty = y - 1; ty <= y + 1; ++ty)
                if (isok(tx, ty) && IS_THRONE(levl[tx][ty].typ)) {
                    mptr->flags.ludios = 1;
                    break;
                }
            break;
        }
```

Source: [`src/dungeon.c:3038-3057`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dungeon.c#L3038-L3057).

The comment draws the geometry straight out of `knox.lua`, and the offset is
right for that file as written: the throne is at `x=43` and the entrance secret
door at `x=47`.

What the comment does not account for is flipping. `knox.lua` declares only

```lua
des.level_flags("mazelevel", "noteleport")
```

Source: [`dat/knox.lua`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/dat/knox.lua).

With no `"noflipx"`, `flip_level_rnd(coder->allow_flips, FALSE)` is free to
mirror the map horizontally
([`sp_lev.c:968`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L968),
called from
[`sp_lev.c:6049`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L6049)
and
[`sp_lev.c:6493`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L6493)),
and it does so on about half of all seeds. The throne and the entrance are
flipped together, so their four-column spacing survives; only the sign of the
offset changes, and the check hard-codes one sign.

`mptr->flags.ludios` is the only thing gated on this, and it is what prints the
line
([`dungeon.c:3656`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dungeon.c#L3656)).

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): accept the throne on either side,
which is what "four columns to left" means once the map can be mirrored.

```c
            for (ty = y - 1; ty <= y + 1; ++ty)
                if ((isok(x - 4, ty) && IS_THRONE(levl[x - 4][ty].typ))
                    || (isok(x + 4, ty) && IS_THRONE(levl[x + 4][ty].typ))) {
                    mptr->flags.ludios = 1;
                    break;
                }
```

Fixed code:
[`dungeon.c:3038-3063`](https://github.com/davidbau/NetHack/blob/6d3963b4a1c9f32602acac246a1e47fc4b1fdc05/src/dungeon.c#L3038-L3063)
· diff:
[commit 6d3963b4a](https://github.com/davidbau/NetHack/commit/6d3963b4a1c9f32602acac246a1e47fc4b1fdc05).

`knox.lua` puts exactly one throne on the level, four columns from the one
entrance, so widening the test cannot produce a false positive there. The now
unused `tx` is removed and the comment records why both signs are checked.

**An alternative, smaller change** would be to add `"noflipx"` to `knox.lua`'s
`des.level_flags`. That fixes the annotation too, and it is a one-word edit,
but it gives up the layout variety the flip was added for. Accepting either
side keeps the variety, which is why it is the version offered here. A
maintainer who would rather pin the layout can take the one-word version
instead; the bug report stands either way.

## Verification

Rebuilt and re-recorded on the seed that flips. Same seed, same datetime, same
keystream:

| | stock | patched |
|---|---|---|
| steps recorded | 118 | 118 |
| RNG entries | 24,043 | 24,043 |
| `A throne.` | printed | printed |
| `Fort Ludios.` | **absent** | **printed** |

The RNG stream and the step count are identical, so the patch changes the
annotation and nothing else. Reverting the source and rebuilding reproduced the
stock recording exactly, byte-for-byte on both counts, which is the control
that the patched run differed because of the patch rather than because of the
rebuild.

Both `session.json` and `session-unflipped.json` are also registered
regression fixtures in the JavaScript port this came out of, and both pass
every channel exactly, so the behaviour above is C's rather than an artefact of
how the sessions were captured.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5. The defect surfaced while porting the `#overview` annotation cascade:
nine of the ten labels matched C on the first pass, and Fort Ludios matched on
one seed but not another, which is what exposed the sign.
