**Title:** Redrawing the screen just after a vault guard leaves prints "Program in disorder!"

**Version:** NetHack 5.0.0 as released (`16ff59115`), against which the
sessions were recorded. **Fixed upstream** in
[`d13eceb28`](https://github.com/NetHack/NetHack/commit/d13eceb28bc84a36d09254a7e1d8b939115afab6)
("eliminate one more source of vault guard newsym msgs", nhmall,
2026-06-14). Sibling: [bug 01](../01-vault-guard-parkguard-newsym/), the same
assertion from `postmov()`, fixed in
[`c42d35eac`](https://github.com/NetHack/NetHack/commit/c42d35eac0b3aa87a45ad102b4c2945b602a5897).

### Symptom

After a vault guard escorts you out and vanishes, and before its temporary
corridor is removed, anything that calls `see_monsters()` (`^R`, save and
restore, `^T` onto your own square) prints:

```
Suddenly, the guard disappears.
newsym: attempting screen update for <0,0>
Program in disorder!  (Saving and reloading may fix this problem.)
```

Nothing is corrupted and play continues. Under the fuzzer it is a hard stop,
because `impossible()` escalates to `panic()` when
`iflags.debug_fuzzer == fuzzer_impossible_panic`.

### Cause

`parkguard()` ([`src/vault.c:155-166`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/vault.c#L155-L166)) moves the departing guard to `<0,0>` and
leaves it on `fmon`, with the comment "monster traversal loops should skip it".
Four loops do ([`monmove.c:926`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/monmove.c#L926),
[`minion.c:48`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/minion.c#L48),
[`sp_lev.c:643`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L643),
[`wizard.c:750`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/wizard.c#L750)). `see_monsters()`
([`src/display.c:1504-1510`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/display.c#L1504-L1510))
skips only dead and still-arriving monsters:

```c
    for (mon = fmon; mon; mon = mon->nmon) {
        if (DEADMONSTER(mon))
            continue;
        if ((mon->mstate & MON_STILL_ARRIVING) != 0)
            continue;
        newsym(mon->mx, mon->my);        /* <0,0> for the parked guard */
```

`newsym()` rejects column 0 with `impossible()`
([`display.c:928-936`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/display.c#L928-L936)).
`parkguard()` sets no `mstate`, so `MON_OFFMAP` does not apply.

### Fix

Upstream's `d13eceb28` adds
`#define PARKEDMONSTER(mon) ((mon)->isgd && (mon)->mx == 0)` and a not yet
consulted `MON_PARKED` bit
([`include/monst.h:224-225`](https://github.com/NetHack/NetHack/blob/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0/include/monst.h#L224-L225)),
and applies it at 19 call sites in `detect.c`, `display.c`, `light.c`,
`minion.c`, `mon.c`, `monmove.c` and `steed.c`, including
[`see_monsters()`](https://github.com/NetHack/NetHack/blob/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0/src/display.c#L1546-L1548).

This bundle's narrower [`proposed-fix.patch`](proposed-fix.patch), now
superseded, used the `c42d35eac` idiom:

```diff
         if ((mon->mstate & MON_STILL_ARRIVING) != 0)
             continue;
+        if (!mon->mx)
+            continue;
         newsym(mon->mx, mon->my);
```

It is on branch `bugreport/09-see-monsters-parked-guard`,
[commit f7f5a644c](https://github.com/davidbau/NetHack/commit/f7f5a644ce2cc579dc4ad5630d36148cb822c9ee).
Rebuilt on the same seed, datetime and keystream: 5 assertions unpatched, 0
patched, with `Suddenly, the guard disappears.` printed once in each.

### Repro

By hand (nhmall's recipe): teleport into a vault, wait for the guard, drop
gold if asked and follow it out, then press `^R` or save and restore right
after the guard disappears.

[`session-directed.json`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/09-see-monsters-parked-guard/session-directed.json#step=73)
is a 97-key wizard-mode scenario that stays standing in the temporary corridor
(so `clear_fcorr()` keeps the guard parked) and uses `^T`; it fires at steps
[73](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/09-see-monsters-parked-guard/session-directed.json#step=73),
78, 83, 88 and 93.
[`session.json`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/09-see-monsters-parked-guard/session.json#step=137)
is from a real NAO game (firings at
[137](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/09-see-monsters-parked-guard/session.json#step=137),
140 and 143); it replays but no longer re-records, because its fresh C
recording diverges at RNG draw 2486 under the current harness. Three more
games found in ordinary play hit it too
(`nao-tou-1dmu1g-s8361-rcjorgejarai`, `cov-wear-every-armor-s5012`,
`nao-tou-mnzci-s4359-rcrzepol`).

`bash bugs/09-see-monsters-parked-guard/repro.sh` re-records
[`session-directed.json`](session-directed.json) (not
[`session.json`](session.json)) through a freshly built
recorder and prints `BUG CONFIRMED` (exit 0) if `newsym: attempting screen
update` appears, else `BUG NOT REPRODUCED` (exit 1). The tree must contain
`c42d35eac`, or the `postmov()` path fires first; on any tree at or after
`d13eceb28` it exits 1.
