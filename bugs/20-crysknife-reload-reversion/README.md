# A fixed crysknife on the floor takes another 10% chance of turning into a worm tooth every time its level is loaded

A crysknife reverts to a worm tooth when nobody is holding it. A *fixed*
crysknife is meant to be the exception: it has only a 10% chance of reverting
when it is dropped. In practice the 10% chance is taken again every time the
level it lies on is read back from disk, which happens

- on every return to a level already visited (`goto_level()` -> `getlev()`),
- on every save (`dosave0()` reads each stored level back in and writes it
  into the save file), and
- on every restore (the restore reads each stored level once and the current
  level twice).

So a stash of fixed crysknives left on some level of the dungeon wears away:
after `n` such loads, each knife has survived with probability `0.9^n`,
not `0.9`. Nothing tells the player; the knives are simply worm teeth the
next time they look. A save and restore also consumes random numbers for
every fixed crysknife lying on any stored level, so saving changes the rest of
the game.

The affected code is `place_object()` in `src/mkobj.c`, which calls
`obj_no_longer_held()` unconditionally, and `find_lev_obj()` in
`src/restore.c`, which rebuilds each loaded level's floor through
`place_object()`. It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked
2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`, NetHack
5.0.0 as released. The branch
[`bugreport/20-crysknife-reload-reversion`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/20-crysknife-reload-reversion)
holds one proposed commit, verified by rebuild.

Severity: low. It loses a player's item without notice, and only affects fixed
crysknives left on the floor, but it is not rare for a player who stashes one:
twenty level loads leave about one knife in eight.

## Watch it happen

A wizard-mode Valkyrie wishes for five fixed crysknives (+0 to +4, so they do
not stack and each gets its own roll), identifies them, goes down to level 2,
drops them on the up staircase, and then goes up and down the stairs twelve
times, looking at the pile with `:` after each return. Then she goes up, saves,
restores, and comes back down once more.

- [**Stock, step 128**: the pile just after the drop; all five are fixed crysknives](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=128)
- [**Stock, step 134**: after the first return to level 2, the +3 knife is now a worm tooth](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=134)
- [**Stock, step 200**: after twelve returns, three of the five are worm teeth](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=200)
- [**Patched, step 200**: the same keystrokes; all five are still fixed crysknives](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session-fixed.json#step=200)

The save ends segment 1; segment 2 is the restored game. In the stock
recording the save itself reverts a fourth knife, so the pile seen after the
restore and one more return is four worm teeth and one crysknife. In the
patched recording it is still five crysknives.

- [**Stock, segment 2, step 5**: after save, restore and one more return, four of the five are worm teeth](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#seg=2&step=5)
- [**Patched, segment 2, step 5**: the same point; all five are still fixed crysknives](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session-fixed.json#seg=2&step=5)

The random-number log in the session makes the mechanism visible directly.
Each `>` that brings the hero back to level 2 carries one
`rn2(10) @ obj_no_longer_held(do.c:911)` per fixed crysknife still on the
floor, for example step 132:

```
rn2(10)=6 @ obj_no_longer_held(do.c:911)
rn2(10)=2 @ obj_no_longer_held(do.c:911)
rn2(10)=8 @ obj_no_longer_held(do.c:911)
rn2(10)=0 @ obj_no_longer_held(do.c:911)     <- this one reverts
rn2(10)=2 @ obj_no_longer_held(do.c:911)
rnd(10)=3 @ getlev(restore.c:1219)
...
```

and the save (step 205, key `y`) and the restore (the first step of segment 2)
carry the same draws for the knives on the stored level 2. In the patched
recording the only `obj_no_longer_held` draws are the five taken when the knives
are dropped.

## What the code is doing

`place_object()` treats every object it puts on the floor as one that has just
left someone's hands:

```c
    otmp2 = svl.level.objects[x][y];

    obj_no_longer_held(otmp);
    if (otmp->otyp == BOULDER) {
```

Source: [`src/mkobj.c:2328-2331`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkobj.c#L2328-L2331).

and `obj_no_longer_held()` rolls the fixed crysknife's chance:

```c
    case CRYSKNIFE:
        /* Normal crysknife reverts to worm tooth when not held by hero
         * or monster; fixed crysknife has only 10% chance of reverting.
         ...
         */
        if (!obj->oerodeproof || !rn2(10)) {
            /* if monsters aren't moving, assume player is responsible */
            if (!svc.context.mon_moving && !program_state.gameover)
                costly_alteration(obj, COST_DEGRD);
            obj->otyp = WORM_TOOTH;
            obj->oerodeproof = 0;
        }
```

Source: [`src/do.c:904-919`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/do.c#L904-L919).

That is right for drops, throws and monster deaths, and several drop paths
rely on it (`steal.c:834` has `/* obj_no_longer_held(obj); -- done by
place_object */`). But when a level is read back in, `getlev()` calls
`find_lev_obj()`
([`restore.c:1168`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L1168)),
which rebuilds the floor by placing every object again:

```c
    /* Set svl.level.objects (as well as reversing the chain back again) */
    while ((otmp = fobjtmp) != 0) {
        fobjtmp = otmp->nobj;
        place_object(otmp, otmp->ox, otmp->oy);
```

Source: [`src/restore.c:94-97`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L94-L97).

These objects were already lying on the floor when the level was written out.
They are not being dropped, but each fixed crysknife among them (and each one
inside a container on the floor, since `obj_no_longer_held()` recurses into
contents) takes the 10% chance again. `getlev()` runs

- when the hero arrives on a level visited before;
- once per stored level during a save, in `dosave0()`
  ([`save.c:185-215`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/save.c#L185-L215)),
  and reversions there are written into the save file;
- during a restore, once per stored level
  ([`restore.c:873`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L873))
  and twice for the current level
  ([`restore.c:811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L811)
  and
  [`restore.c:898`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L898)).

We found no comment or caller suggesting the repeated roll is intended. The
comment in `obj_no_longer_held()` describes a chance taken when the knife stops
being held. An ordinary crysknife always reverts on its first drop, so it is
never on the floor to be rolled again; only fixed ones are affected.

The call in `place_object()` dates from 2002 (`316a94d50f`), so this is
long-standing rather than new in 5.0.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): skip the check while a level is
being read in.

```c
    /* objects being read back in from a level file were already on the
       floor, so don't give a fixed crysknife another chance to revert */
    if (!program_state.in_getlev)
        obj_no_longer_held(otmp);
```

Fixed code and diff:
[commit 64b11e7e2](https://github.com/davidbau/NetHack/commit/64b11e7e251cd2856ea564d5a7b46ca449e8bdba).

`program_state.in_getlev` is set for the whole of `getlev()`, so this covers
level changes, saves and restores alike, and `find_lev_obj()` is the only
`place_object()` caller inside `getlev()`. Every other `place_object()` caller
keeps the check, including the ones that depend on it such as `steal.c:834`.
Bones files also load through `getlev()`; their floor objects have already been
through `obj_no_longer_held()` when the bones were made
([`bones.c:280`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/bones.c#L280)
and the `place_object()` that follows it), so they do not need another roll on
the way in.

**Alternatives.** The `NetHack-5.0` branch now has `level_status.loading`,
which could be tested instead of `program_state.in_getlev`. A larger change
would be to have `find_lev_obj()` link objects into `svl.level.objects`
without going through `place_object()`, but `place_object()` also does the
boulder ordering and vision blocking that level loading needs, so guarding the
one call seemed smaller and safer.

## Verification

Rebuilt and re-recorded. Same seed, same datetimes, same keystrokes:

| | stock | patched |
|---|---|---|
| steps recorded (segment 1 + segment 2) | 206 + 7 | 206 + 7 |
| RNG entries | 6,057 | 6,009 |
| `obj_no_longer_held` draws | 46 (5 on the drop, 37 on the twelve returns to level 2, 2 on the save, 1 on the restore, 1 on the return after the restore) | 5 (on drop) |
| pile after the drop (step 128) | 5 crysknives | 5 crysknives |
| pile after 12 returns (step 200) | 2 crysknives, 3 worm teeth | 5 crysknives |
| pile after save, restore and one more return | 1 crysknife, 4 worm teeth | 5 crysknives |

The patched run draws fewer random numbers, so the monsters on the two levels
move differently after the first return; the hero's route and every keystroke
still do the same thing, and the hero is at full hit points throughout both
runs. Reverting the source and rebuilding reproduced the stock recording
exactly (every segment identical), which is the control that the patched run
differed because of the patch rather than because of the rebuild.

## Reproducing it

```
bash bugs/20-crysknife-reload-reversion/repro.sh
```

That re-records [`session.json`](session.json) through the recorder binary and
checks for `obj_no_longer_held` draws on steps that only change level. It exits
0 if there are some (the bug), 1 if the only draws are the five on the drop
(the patch is applied), and 2 if the scenario did not play out.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced while porting save and restore: the port's level loader
had to reproduce C's random-number draws exactly, and a fixed crysknife on a
stored level produced draws during a save that no player action explained.
