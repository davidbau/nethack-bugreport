# Redrawing the screen just after a vault guard leaves prints "Program in disorder!"

When a vault guard has escorted you out of the vault and vanished, there is a
short window before its temporary corridor is removed. Anything that redraws
every monster during that window (pressing `^R`, or saving and restoring)
makes the game print an internal error and ask you to mail the DevTeam:

```
Suddenly, the guard disappears.
newsym: attempting screen update for <0,0>
Program in disorder!  (Saving and reloading may fix this problem.)
```

Nothing is corrupted and play continues. The cost to a player is a short
`--More--` cascade and a message telling them to report a bug. Under the
DevTeam's own fuzzer it is a hard stop, because `impossible()` escalates to
`panic()` when `iflags.debug_fuzzer == fuzzer_impossible_panic`.

The cause is that the departing guard is not removed from the monster list.
`parkguard()` moves it *off the map*, to `<0,0>`, and leaves it on `fmon` for
the corridor-removal code to finish with. A comment there states the resulting
rule for everyone else: "monster traversal loops should skip it". Four loops do
skip it. `see_monsters()`, which walks the same list to redraw every monster,
did not, and `newsym()` rejects column 0 by design, so it reported the
attempt.

## This one is already fixed upstream

**Fixed in [`d13eceb28`](https://github.com/NetHack/NetHack/commit/d13eceb28bc84a36d09254a7e1d8b939115afab6)**
("eliminate one more source of vault guard newsym msgs", nhmall, 2026-06-14),
which reached the `NetHack-5.0` branch three months before this bundle was
written. The bundle's earlier "unreported upstream" status was wrong: it was
checked against the pinned submodule commit and never against the live branch.
It is kept here as a recorded witness of the defect and because the way
upstream fixed it is more interesting than the patch proposed below.

|  |  |
|---|---|
| Affects | `see_monsters()` in `src/display.c`, up to `d13eceb28` |
| Present in | NetHack 5.0.0 as released (`16ff59115`), which is the commit the sessions here were recorded against |
| Fixed in | [`d13eceb28`](https://github.com/NetHack/NetHack/commit/d13eceb28bc84a36d09254a7e1d8b939115afab6), 2026-06-14 |
| Severity | Low. `impossible()`, no state corruption; a hard stop under the fuzzer |
| Sibling | [bug 01](../01-vault-guard-parkguard-newsym/), the same assertion from `postmov()`, fixed in [`c42d35eac`](https://github.com/NetHack/NetHack/commit/c42d35eac0b3aa87a45ad102b4c2945b602a5897) |

## Watch it happen

[**Replay the recorded game, at the first firing**](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/09-see-monsters-parked-guard/session.json#step=137)
No build required. Step back to 136 for `Suddenly, the guard disappears.`
and forward through 140 and 143, where the same assertion fires twice more as
the display is refreshed again.

This is a real game, not a constructed scenario: the recording comes from a
public NAO game replayed keystroke for keystroke.

## Reproducing it by hand

nhmall's own recipe, from the fix commit, is the shortest route:

1. Enter a vault by teleporting into it.
2. Wait for the guard to arrive.
3. Drop your gold if the guard asks, and follow the guard out.
4. Right after the guard disappears, but before the corridor does, either
   press `^R` to redraw, or save and restore.

Either action calls `see_monsters()`, which walks `fmon` and redraws the parked
guard.

The recorded session reproduces it without any of that:

```
bash bugs/09-see-monsters-parked-guard/repro.sh
```

That re-records [`session.json`](session.json) through a freshly built recorder
binary and checks that `newsym: attempting screen update` appears. Note the
caveat in the script: on a tree that predates `c42d35eac` the older
`postmov()` path fires as well, so the message alone does not tell you which
call site produced it.

## What the code is doing

`parkguard()` moves the departing guard off the map and says what that means
for everyone else:

```c
parkguard(struct monst *grd)
{
    /* either guard is dead or will now be treated as if so;
       monster traversal loops should skip it */
    ...
    if (m_at(0, 0) != grd)
        place_monster(grd, 0, 0);
```

Source: [`src/vault.c:155-166`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/vault.c#L155-L166).

The guard stays on `fmon`. Four traversal loops honour the rule, three of them
naming the guard explicitly:

```
monmove.c:926   if (mtmp->isgd && (DEADMONSTER(mtmp) || mtmp->mx == 0))
minion.c:48     if (mtmp->isgd && mtmp->mx == 0)
sp_lev.c:643    if (mtmp->mx == 0) /* not on map so don't flip guard->mx,my */
wizard.c:750    if (!mtmp->mx)
```

Source: [`monmove.c:926`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/monmove.c#L926),
[`minion.c:48`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/minion.c#L48),
[`sp_lev.c:643`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L643),
[`wizard.c:750`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/wizard.c#L750).

`see_monsters()` skipped two categories, and off-map was not one of them:

```c
    /* loop through level.monsters (aka fmon) */
    for (mon = fmon; mon; mon = mon->nmon) {
        if (DEADMONSTER(mon))
            continue;
        if ((mon->mstate & MON_STILL_ARRIVING) != 0)
            continue;
        newsym(mon->mx, mon->my);        /* <0,0> for the parked guard */
```

Source: [`src/display.c:1504-1510`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/display.c#L1504-L1510).

`newsym()` treats column 0 as a caller error. `isok()` requires `x >= 1`, and
the failure is routed to `impossible()` rather than `panic()` precisely because
misusing column 0 is the milder case:

```c
    /* should never happen; same error handling as u_on_newpos() */
    if (!isok(x, y)) {
        void (*errfunc)(const char *, ...) PRINTF_F_PTR(1, 2);

        errfunc = (x < 0 || y < 0 || x > COLNO - 1 || y > ROWNO - 1) ? panic
                  : impossible; /* misuse of column 0 is less severe */
        (*errfunc)("newsym: attempting screen update for <%d,%d>", x, y);
        return;
    }
```

Source: [`src/display.c:928-936`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/display.c#L928-L936).

One dead end worth recording, so nobody re-walks it: `MON_OFFMAP` is not the
vehicle here. `parkguard()` sets no `mstate` at all, and `MON_OFFMAP` is used
for migrating and limbo monsters. The `mx == 0` idiom is what the sibling loops
and `c42d35eac` already used.

## How upstream fixed it

`d13eceb28` guards `see_monsters()` the same way, and then goes further: it
introduces a macro so the rule has one name instead of four hand-written
spellings.

```c
#define MON_PARKED         0x00000200
...
#define PARKEDMONSTER(mon) ((mon)->isgd && (mon)->mx == 0)
/* eventually, we'll be able to use (((mon)->mstate & MON_PARKED) != 0) */
```

Source: [`include/monst.h:224-225` at the branch tip](https://github.com/NetHack/NetHack/blob/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0/include/monst.h#L224-L225).

`see_monsters()` now reads:

```c
    for (mon = fmon; mon; mon = mon->nmon) {
        if (DEADMONSTER(mon) || PARKEDMONSTER(mon))
            continue;
```

Source: [`src/display.c:1546-1548` at the branch tip](https://github.com/NetHack/NetHack/blob/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0/src/display.c#L1546-L1548).

The commit reaches 19 call sites across `detect.c`, `display.c`, `light.c`,
`minion.c`, `mon.c`, `monmove.c` and `steed.c`, and adds a `MON_PARKED`
`mstate` bit that the macro does not consult yet. That is the broader
alternative this bundle had described and set aside as "a larger refactor";
upstream did the refactor. Several of those 19 sites, the `detect.c` monster
and object detection loops in particular, were the same latent defect waiting
for a different trigger.

## The patch this bundle proposed

[`proposed-fix.patch`](proposed-fix.patch) is the narrow version: give
`see_monsters()` the guard its siblings already had, in the idiom `c42d35eac`
chose.

```c
         if ((mon->mstate & MON_STILL_ARRIVING) != 0)
             continue;
+        if (!mon->mx)
+            continue;
         newsym(mon->mx, mon->my);
```

It still applies cleanly to the pinned commit (`git apply --check`), and it is
committed on a branch of a NetHack fork so it can be read as a diff:
[commit f7f5a644c](https://github.com/davidbau/NetHack/commit/f7f5a644ce2cc579dc4ad5630d36148cb822c9ee)
(branch `bugreport/09-see-monsters-parked-guard`). It is superseded by
`d13eceb28` and is kept only to show what was proposed.

## Witnesses

Four independent recordings, different roles and seeds, all from real games:

| session | role | steps | `impossible()` at |
|---|---|---|---|
| [`session.json`](session.json) (`nao-val-eiy51p-s3675-rcwildkatz`) | Valkyrie | 220 | 137, 140, 143 |
| `nao-tou-1dmu1g-s8361-rcjorgejarai` | Tourist | 445 | 107, 111, 115 |
| `cov-wear-every-armor-s5012` | — | 479 | 117, 120, 123 |
| `nao-tou-mnzci-s4359-rcrzepol` | Tourist | 752 | 94, 98, 106 |

The shipped one is the shortest. All four are registered regression fixtures in
the JavaScript port that this bundle came out of, and all four pass every
channel exactly — the port reproduces C's RNG stream, event order and screen
output including this assertion. That is what establishes the behaviour is C's
and not an artefact of how the sessions were captured.

## Verification status

The analysis, the witnesses and the patch were never checked against a binary
rebuilt with the patch applied, which was this bundle's one gap. It is now
moot: `d13eceb28` is upstream's own fix for the same call site, and its commit
message describes the same trigger (`^R`, or save and restore, right after the
guard disappears) arrived at independently.

Tracked in the porting project this came out of as issue 1585; that
repository is not public, so the analysis that matters is reproduced above.
