# `see_monsters()` draws the parked vault guard at `<0,0>`, tripping `newsym()`'s own `impossible()`

**Component:** `src/display.c` `see_monsters()` (the `newsym(mon->mx, mon->my)`
in the `fmon` loop)
**Severity:** LOW / `impossible()` — cosmetic for a player (an extra `--More--`
cascade), but a hard stop for the DevTeam's fuzzer, since `impossible()`
escalates to `panic()` under `iflags.debug_fuzzer == fuzzer_impossible_panic`.

## This is a second path to bug 01, not a regression of it

[Bug 01](../01-vault-guard-parkguard-newsym/) reported the same assertion via
`postmov()`. That was fixed upstream in **`c42d35eac`** ("avoid newsym(0,0) for
vault guard"), which guards that one call site:

```c
             /* only call newsym() when not a vault guard moving to <0,0> */
             if (mtmp->mx)
                 newsym(mtmp->mx, mtmp->my);
```

`see_monsters()` calls `newsym(mon->mx, mon->my)` from a different loop and was
never taught the same thing, so the assertion still fires. With `c42d35eac`
applied, **every** observed firing comes from `see_monsters()`.

## Symptom

```
Suddenly, the guard disappears.--More--
newsym: attempting screen update for <0,0>--More--
Program in disorder!  (Saving and reloading may fix this problem.)--More--
```

## Root cause: an invariant stated in a comment and implemented in four other loops, but not this one

When a vault guard's temporary corridor is being removed, `parkguard()`
(`vault.c`) moves it off the map to `<0,0>`:

```c
parkguard(struct monst *grd)
{
    /* either guard is dead or will now be treated as if so;
       monster traversal loops should skip it */          <-- the asserted invariant
    ...
    if (m_at(0, 0) != grd)
        place_monster(grd, 0, 0);
```

The guard stays on `fmon`. Four traversal loops already honour that invariant,
three of them naming the guard explicitly:

```
monmove.c:926   if (mtmp->isgd && (DEADMONSTER(mtmp) || mtmp->mx == 0))
minion.c:48     if (mtmp->isgd && mtmp->mx == 0)
sp_lev.c:643    if (mtmp->mx == 0) /* not on map so don't flip guard->mx,my */
wizard.c:750    if (!mtmp->mx)
```

`see_monsters()` skips only two categories, and off-map is not one of them:

```c
    for (mon = fmon; mon; mon = mon->nmon) {
        if (DEADMONSTER(mon))
            continue;
        if ((mon->mstate & MON_STILL_ARRIVING) != 0)
            continue;
        newsym(mon->mx, mon->my);        /* <0,0> for the parked guard */
```

and `newsym()` rejects column 0 by design (`isok()` requires `x >= 1`), so it
reports `impossible("newsym: attempting screen update for <%d,%d>")`.

Note `MON_OFFMAP` is *not* the vehicle here: upstream `parkguard()` sets no
`mstate` at all, and `MON_OFFMAP` is used for migrating/limbo monsters
(`mon.c:4051`, `wizcmds.c:99`). The `mx == 0` idiom is what the sibling loops
and `c42d35eac` itself already use.

## Witnesses

Four independent recordings, different roles and seeds, all already in the
porting project and all **passing parity** (the JS port reproduces C exactly,
so the defect is C's):

| session | role | steps | `impossible()` at |
|---|---|---|---|
| [`session.json`](session.json) (`nao-val-eiy51p-s3675-rcwildkatz`) | Valkyrie | 220 | 137, 140, 143 |
| `nao-tou-1dmu1g-s8361-rcjorgejarai` | Tourist | 445 | 107, 111, 115 |
| `cov-wear-every-armor-s5012` | — | 479 | 117, 120, 123 |
| `nao-tou-mnzci-s4359-rcrzepol` | Tourist | 752 | 94, 98, 106 |

The shipped one is the shortest. All four were recorded against a tree with
`c42d35eac` applied, which is what establishes that the remaining path is
`see_monsters()`.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch) — give `see_monsters()` the guard its
siblings already have, in the same idiom `c42d35eac` chose:

```c
         if ((mon->mstate & MON_STILL_ARRIVING) != 0)
             continue;
+        if (!mon->mx)
+            continue;
         newsym(mon->mx, mon->my);
```

**Invariant preserved:** the one `parkguard()` already states — monster
traversal loops skip a guard parked off the map.

A broader alternative would be to have `parkguard()` set an `mstate` flag and
teach every traversal loop to consult it, which would subsume the four existing
ad-hoc `mx == 0` checks. That is a larger refactor; this patch matches the
style the DevTeam has already accepted twice.

## Status

**Not yet verified against a rebuilt binary.** The porting project's C harness
is pinned for an unrelated long-running job at time of writing; the analysis,
the witnesses and the patch are complete, and the rebuild check (assert the
`impossible()` disappears and nothing else changes) is pending.

Tracked in [teleport#1585](https://github.com/davidbau/teleport/issues/1585).
