**Title:** `impossible("newsym: attempting screen update for <0,0>")` when the vault guard parks

**Version:** NetHack 5.0.0 (the `src/vault.c` code is unchanged since the
3.7 line).

### Symptom

After the vault guard escorts the hero out and the temporary corridor is
removed, the guard is parked and the player sees:

```
Suddenly, the guard disappears.
--More--
newsym: attempting screen update for <0,0>
--More--
Program in disorder!  (Saving and reloading may fix this problem.)
--More--
Please report these messages to devteam@nethack.org.
```

Play continues normally and no save corruption follows.

### Cause

Call chain: `movemon_singlemon -> dochugw -> dochug -> m_move -> postmov ->
newsym(0, 0)`.

`parkguard()` (`src/vault.c:155`) moves the guard to (0,0) with
`place_monster(grd, 0, 0)` but leaves `mstate` at `MON_FLOOR` (0).
`postmov()` (`monmove.c:1455`) has an early return for off-map monsters at
line 1514:

```c
} else if (mon_offmap(mtmp)) {
    return MMOVE_DONE;
}
```

but `mon_offmap()` is `((mon)->mstate != MON_FLOOR)` (`monst.h:255`), so it
is FALSE for the parked guard and `postmov()` reaches `newsym(mtmp->mx,
mtmp->my)` at line 1656. `newsym()` (`display.c:929`) rejects column 0 via
`isok()` and calls `impossible()`.

### Fix

Mark the parked guard off-map, so `mon_offmap()` is TRUE and the existing
checks in `monmove.c`, `mon.c`, `mhitm.c`, `muse.c` and `dogmove.c` skip it:

```diff
     EGD(grd)->ogx = grd->mx;
     EGD(grd)->ogy = grd->my;
+    grd->mstate |= MON_OFFMAP;
 }
```

`movemon_singlemon()` (`mon.c:1233`) tests only `mstate & MON_MIGRATING`
(0x04), which `MON_OFFMAP` (0x01) does not affect. `ogx,ogy` stay at 0,0 as
`gd_move_cleanup()`'s comment (`vault.c:843-851`) requires for the
`abs(egrd->ogx - grd->mx) > 1` check at line 930. Full diff:
`proposed-fix.patch`. With the patch, replaying `session.json` still shows
"Suddenly, the guard disappears." (at step 117) without the three
`impossible()` lines and their `--More--` prompts.

### Repro

```bash
bash setup.sh                                    # build the recorder once
bash bugs/01-vault-guard-parkguard-newsym/repro.sh
```

`repro.sh` replays `session.json` (seed 8666, datetime `20000110090000`,
Tourist, 187 steps) through the recorder and exits 0 with `BUG CONFIRMED`
if the three `impossible()` lines appear. They appear at step 165, after
step 164's "Suddenly, the guard disappears." The recorder's patches only add
session markers (`NOMUX_MARKERS=1`); the bug fires the same with a vanilla
build.

Viewer:
https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/01-vault-guard-parkguard-newsym/session.json#step=165
(or `tools/session-viewer/index.html` locally; scrub steps 164-167).

### Status

Unreported upstream as of 2026-05-24 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues) for
`newsym`, `vault guard`, `place_monster vault`, `parkguard`, `vault guard
impossible`).
