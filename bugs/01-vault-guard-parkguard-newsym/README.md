# Bug #01 — `impossible("newsym: attempting screen update for <0,0>")` when vault guard parks

**Status:** unreported upstream as of 2026-05-24 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
for `newsym`, `vault guard`, `place_monster vault`, `parkguard`,
`vault guard impossible` — no matching issue or PR).

**NetHack version:** 5.0.0 (also present in 3.7 line; the relevant
code in `src/vault.c` has not changed between 3.7 and 5.0).

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

`src/vault.c:155` — `parkguard()`:

```c
staticfn void
parkguard(struct monst *grd)
{
    if (grd == svc.context.polearm.hitmon)
        svc.context.polearm.hitmon = 0;
    if (grd->mx) {
        remove_monster(grd->mx, grd->my);
        newsym(grd->mx, grd->my);
    }
    if (m_at(0, 0) != grd)
        place_monster(grd, 0, 0);          // ← guard parked at (0,0)
    /* [grd->mx,my just got set to 0,0 by place_monster(), so this
       just sets EGD(grd)->ogx,ogy to 0,0 too; is that what we want?] */
    EGD(grd)->ogx = grd->mx;               // ← ogx = 0
    EGD(grd)->ogy = grd->my;               // ← ogy = 0
}
```

NetHack uses `(0,0)` as a "parked" off-map sentinel for the vault
guard between guard-action turns. `place_monster(grd, 0, 0)` sets
`grd->mx = grd->my = 0`. The subsequent lines then propagate `(0,0)`
into `EGD(grd)->ogx, ogy` — and **the inline comment on line 167-168
already flags this as suspect** ("is that what we want?").

On the very next moveloop iteration, some downstream display pass
(vision recalc / postmov / movemon iteration) reads the guard's
coords and calls `newsym(grd->mx, grd->my)` = `newsym(0, 0)`.
`newsym()` in `src/display.c:929` checks `isok(x, y)`, which rejects
column 0 (it's reserved for the status bar), routes to `impossible()`,
and fires the warning cascade.

The comment in `display.c:934` calls out the same situation: "misuse
of column 0 is less severe" — the author already knew `x==0` calls
happen and chose `impossible` over `panic`. But `impossible` still
emits the user-visible warning pline + "Program in disorder!" pline.

## Proposed patch

See `proposed-fix.patch`. Two options offered, primary + fallback:

**Option A (preferred, root cause):** Don't overwrite `ogx`/`ogy`
with `(0,0)` in `parkguard()`. Leave them at the guard's last on-map
values. The earlier `remove_monster + newsym` in `parkguard` already
redrew the guard's prior map cell, so any subsequent code that reads
`ogx/ogy` and calls `newsym` will redraw an already-empty cell — a
harmless no-op.

**Option B (defense in depth, in `newsym()`):** Recognize `(0,0)`
explicitly as the vault-guard parking sentinel and return silently
without `impossible()`. Targeted, conservative; doesn't change any
game state.

Both are included so reviewers can choose. Option A removes the root
cause and is more conservative behaviorally; Option B is a one-line
safety net at the display layer.

## Test session

`session.json` is a recorded `seed8666` game in clean v5 session
format (browser-captured, then re-recorded through the patched
NetHack 5.0 recorder binary). 187 steps. The `--More--` cascade
appears as recorded screen content at steps 164–167. Replay it
through `scripts/record-session.mjs` (or `repro.sh`) on a freshly-
built nethack binary to confirm the bug exists in vanilla 5.0.
