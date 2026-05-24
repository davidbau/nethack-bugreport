# Bug #01 — `impossible("newsym: attempting screen update for <0,0>")` when vault guard parks

**Status:** unreported upstream as of 2026-05-24 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
for `newsym`, `vault guard`, `place_monster vault`, `parkguard`,
`vault guard impossible` — no matching issue or PR).

**NetHack version:** 5.0.0 (also present in 3.7 line; the relevant
code in `src/vault.c` has not changed between 3.7 and 5.0).

**Not patch-induced:** the recorder binary used by `repro.sh` is
built from `nethack-c/upstream/` with the patches in
`nethack-c/patches/`. Those patches only add marker emission for
deterministic session recording (`NOMUX_MARKERS=1`); they do not
touch game logic, monster movement, vault code, `newsym()`, or
`impossible()`. The bug fires identically when the recorded session
is replayed through the patched binary OR through a freshly-built
vanilla `nethack-c/upstream/` binary.

**Severity:** low — does not crash the game and does not corrupt
state, but emits `impossible()` machinery (warning pline, "Program
in disorder!" pline, and `devteam@nethack.org` pline) that is
visible to the player and triggers three `--More--` prompts every
time the vault guard parks.

## What you see in-game

After the player enters a vault and the vault guard arrives, finishes
escorting the player out, and the temporary corridor is cleaned up,
three plines appear in succession (each gated by `--More--`):

```
Suddenly, the guard disappears.
--More--
newsym: attempting screen update for <0,0>
--More--
Program in disorder!  (Saving and reloading may fix this problem.)
--More--
Please find these messages to devteam@nethack.org.
```

The hero is on Dlvl 1, no save corruption follows. Subsequent play
proceeds normally — but the player has been told the game is in
"disorder" and was asked to file a report. The warning is harmless
but undermines confidence and triggers extra keystrokes.

## Repro

```bash
cd nethack-bugreport
bash setup.sh                                    # build the recorder once
bash bugs/01-vault-guard-parkguard-newsym/repro.sh
```

`repro.sh` re-runs `session.json` through the recorder binary and
asserts the impossible-message text appears in the output. The
session is 187 steps; the bug fires at step 165.

To watch the run visually, open `tools/session-viewer/index.html`
and point it at `bugs/01-vault-guard-parkguard-newsym/session.json`.
Scrub to step 164–167 to see the message cascade.

## Character / seed

- Seed: `8666`
- Datetime: `20000110090000`
- Character: Trevi the Rambler (Tourist, neutral, auto-picked)
- Bug fires: step 165 (after step 164's "Suddenly, the guard disappears.")

## Root cause

Traced via backtrace instrumentation; full call chain:

```
moveloop_core → movemon → iter_mons_safe → movemon_singlemon
              → dochugw → dochug → m_move → postmov → newsym(0, 0)
```

`parkguard()` in `src/vault.c:155` sets the guard's coords to `(0,0)`
via `place_monster(grd, 0, 0)`, parking it off-map between guard-
action turns:

```c
staticfn void
parkguard(struct monst *grd)
{
    ...
    if (grd->mx) {
        remove_monster(grd->mx, grd->my);
        newsym(grd->mx, grd->my);          // redraw old cell (now empty)
    }
    if (m_at(0, 0) != grd)
        place_monster(grd, 0, 0);          // ← park at (0,0), sets mx=0,my=0
    EGD(grd)->ogx = grd->mx;               // (intentional — see kludge
    EGD(grd)->ogy = grd->my;               //  comment at vault.c:843-851)
}
```

What `parkguard()` DOESN'T do: update the guard's `mstate` field.
The guard ends up with `mx=0, my=0, mstate=MON_FLOOR (0)`.

`postmov()` in `monmove.c:1455` has the right early-return guard
for off-map monsters at line 1514:

```c
} else if (mon_offmap(mtmp)) {
    return MMOVE_DONE;
}
```

but the `mon_offmap()` macro in `monst.h:255` is:

```c
#define mon_offmap(mon) ((mon)->mstate != MON_FLOOR)
```

For the parked guard, `mstate == MON_FLOOR == 0`, so `mon_offmap()`
returns FALSE, the check at line 1514 doesn't fire, and `postmov`
falls through to line 1656:

```c
} else {
    newsym(mtmp->mx, mtmp->my);            // ← newsym(0, 0)
}
```

`newsym()` in `display.c:929` checks `isok(x, y)`, which rejects
column 0 (reserved for the status bar), routes to `impossible()`,
and fires the user-visible warning cascade. The comment in
`display.c:934` ("misuse of column 0 is less severe") shows the
author already knew `x==0` calls happen — they're real, just
disclaimed as "less severe" — but they still trigger `impossible()`.

## Proposed patch

See `proposed-fix.patch`. **In `parkguard()`, OR `MON_OFFMAP` into
the guard's `mstate`** when parking. This makes `mon_offmap(grd)`
correctly return TRUE for parked guards — and the existing
`mon_offmap()` infrastructure throughout the codebase (`monmove.c`,
`mon.c`, `mhitm.c`, `muse.c`, `dogmove.c`) all correctly skip
them, including the existing `else if (mon_offmap(mtmp)) return
MMOVE_DONE;` in `postmov` that this patch was missing.

The earlier `movemon_singlemon` check at `mon.c:1233` still works
correctly — it checks `(mtmp->mstate & MON_MIGRATING)` specifically
(bit 0x04), not full `mstate` equality. `MON_OFFMAP=0x01` and
`MON_MIGRATING=0x04` don't conflict.

The `parkguard()` setup at vault.c:155 is otherwise correct by
design — `gd_move_cleanup`'s kludge comment (`vault.c:843-851`)
explains that `ogx,ogy = mx,my = 0,0` is deliberately required for
`gd_move()`'s `abs(egrd->ogx - grd->mx) > 1` sanity check at line
930 to pass. Don't touch ogx/ogy.

**Verified locally:** applying this patch and replaying
`session.json` produces the "Suddenly, the guard disappears."
message correctly (still appears at step 117), but eliminates the
spurious `newsym: attempting screen update for <0,0>` →
`Program in disorder!` → `Please report these messages to
devteam@nethack.org.` cascade — 3 fewer plines, 3 fewer `--More--`
dismissals required from the player.

## Test session

`session.json` is a recorded `seed8666` game in clean v5 session
format (browser-captured, then re-recorded through the patched
NetHack 5.0 recorder binary). 187 steps. The `--More--` cascade
appears as recorded screen content at steps 164–167. Replay it
through `scripts/record-session.mjs` (or `repro.sh`) on a freshly-
built nethack binary to confirm the bug exists in vanilla 5.0.
