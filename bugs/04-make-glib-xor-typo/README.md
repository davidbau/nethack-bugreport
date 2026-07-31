# Bug #04 — The "Slip" status condition never displays (one-character typo in `make_glib`)

**Status:** unreported upstream as of 2026-07-31 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
and [PRs](https://github.com/NetHack/NetHack/pulls) for `make_glib`,
`Glib`, `Slippery`, `cond_slip` — no matching issue or PR).

**NetHack version:** 5.0.0 (the line is unchanged for years in the
3.7 line too).

**Severity:** LOW, but genuinely visible. The status line offers an
opt-in "Slip" condition indicator (`OPTIONS=cond_slip`) that is
supposed to show while your fingers are slippery with grease. Because
of this bug it effectively never shows: the status line is not told
to refresh when slipperiness starts or stops. Players who enable the
indicator get nothing; everything *else* about slippery fingers works
(you still drop your weapon), which makes the missing indicator all
the more confusing.

## The bug, in plain words

When your fingers get slippery (or dry off), the function
`make_glib()` in `src/potion.c` records the new state and is supposed
to tell the status line "something you display just changed — redraw."
The line that does that:

```c
disp.botl |= (!Glib ^ !!xtime);
```

is meant to ask "is the new state different from the old state?" It
uses the C idiom `!!x` to squash a value to 0-or-1 on the right side,
but the left side is missing one `!` — so the left side is squashed
*and inverted*. The comparison comes out backwards: the status line
is told to refresh precisely when nothing changed, and told nothing
precisely when the indicator needs to change.

The state itself is stored correctly on the very next line, so the
game *behaves* slippery — only the display is never told. Twelve
lines up in the same file, the sibling function `make_deaf()` writes
the same test correctly.

## What you see in-game

Put `OPTIONS=cond_slip` in your nethackrc, then grease your hands
(apply a can of grease and answer `-`):

- "You coat your fingers with grease." Your wielded weapon
  immediately slips out of your hands — the effect is live. The
  status line shows **no Slip indicator**, this turn or any later
  turn.
- Press `^R` (redraw): **Slip appears** — the game knew all along;
  only the status line was never told to refresh.
- One turn later the indicator **vanishes again** while your fingers
  are still greasy: the next routine status update rewrites the row
  from its stale cached idea of your conditions, erasing what `^R`
  showed.
- When the grease wears off, nothing changes on screen either (there
  is nothing showing to remove).

So across a ~20-turn slippery window, the indicator is visible for
exactly the one moment you force a full redraw.

## The recorded demonstration

`session.json` (seed 404, wizard mode, ~35 keys, `cond_slip` enabled):

1. Wish for a can of grease, apply it, answer `-` to grease the
   hands. **Step 22:** "You coat your fingers with grease. Your
   spear slips from your grasp" — and no Slip on the status line.
2. **Steps 23-30:** eight quiet waiting turns. Still no Slip.
3. **Step 31:** `^R`. Slip appears.
4. **Step 33:** one turn later, Slip is gone again — while the
   fingers are still greasy (see below for the proof).
5. The rest of the recording waits out the grease timer; a second
   `^R` at step 64 shows nothing, correctly, because by then the
   grease really has worn off.

`session-fixed.json` is the identical keystream re-recorded on a
build with `proposed-fix.patch` applied. There the Slip indicator
displays from step 22 through step 63 — the entire slippery window,
onset to expiry, with no `^R` needed. That contrast is also the proof
for point 4 above: at steps 33-63 the fixed build shows the fingers
are still slippery, while the buggy build shows nothing.

Buggy recording:  Slip visible at steps 31-32 only (the forced
redraw).  Fixed recording:  Slip visible at steps 22-63.

## The fix

One keystroke — add the missing `!` so both sides of the comparison
are squashed to 0-or-1 the same way:

```diff
-    disp.botl |= (!Glib ^ !!xtime);
+    disp.botl |= (!!Glib ^ !!xtime);
```

See `proposed-fix.patch`. An equally good alternative is to spell it
the way `make_deaf()` does (`(xtime != 0L) ^ (old != 0L)`), which is
immune to this class of typo.

## Test artifacts

- `session.json` — the buggy recording (vanilla 5.0 recorder build).
- `session-fixed.json` — same keystream on a build with the one-`!`
  fix; Slip displays for the whole slippery window.
- `repro.sh` — re-records `session.json` through your recorder build
  and asserts the signature: no Slip during the slippery waiting
  turns, Slip present right after `^R`. On a fixed build it reports
  the bug gone.
- `proposed-fix.patch` — the one-character diff.
