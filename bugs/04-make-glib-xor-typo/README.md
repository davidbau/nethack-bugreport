**Title:** The "Slip" status condition never displays: `make_glib()` tests `!Glib` instead of `!!Glib`

**Version:** NetHack 5.0.0 (the line is unchanged for years in the 3.7 line
too). Re-checked 2026-09-18: still present at the `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0);
`make_glib()` (`potion.c:461`) is unchanged.

### Symptom

With `OPTIONS=cond_slip`, grease your hands (apply a can of grease, answer
`-`):

- "You coat your fingers with grease." The wielded weapon slips from your
  grasp, but the status line shows no Slip, this turn or later.
- `^R` makes Slip appear.
- One turn later Slip is gone again while the fingers are still greasy.
- When the grease wears off nothing changes on screen.

Across a ~20-turn slippery window the indicator shows only right after `^R`.

### Cause

`make_glib()` in `src/potion.c`:

```c
    disp.botl |= (!Glib ^ !!xtime);
    set_itimeout(&Glib, xtime);
```

The test means "did the state change?", but the left side has one `!`, so it
is inverted: `disp.botl` is set when the state does not change and left alone
when it does. The timeout itself is set correctly, so slippery fingers work;
only the status update is skipped. `make_deaf()`, twelve lines up, writes the
same test as `(xtime != 0L) ^ (old != 0L)`.

### Fix

```diff
-    disp.botl |= (!Glib ^ !!xtime);
+    disp.botl |= (!!Glib ^ !!xtime);
```

Writing it the way `make_deaf()` does also works. Diff: `proposed-fix.patch`.

### Repro

`repro.sh` re-records `session.json` through your recorder build and checks
for the signature: no Slip during the slippery waiting turns, Slip present
right after `^R`. On a fixed build it reports the bug gone.

`session.json` (seed 404, wizard mode, ~35 keys, `cond_slip`, vanilla 5.0
recorder build):

- Step 22: wish for and apply grease to the hands. "You coat your fingers
  with grease. Your spear slips from your grasp"; no Slip.
- Steps 23-30: eight waiting turns, no Slip.
- Step 31: `^R`, Slip appears.
- Step 33: one turn later, Slip is gone.
- Step 64: a second `^R` shows nothing, correctly; the grease has worn off.

`session-fixed.json` is the same keystream on a build with
`proposed-fix.patch`. Slip shows from step 22 through step 63 with no `^R`,
which also confirms the fingers are still slippery at steps 33-63.

Buggy: Slip visible at steps 31-32 only. Fixed: Slip visible at steps 22-63.

### Status

Unreported upstream as of 2026-07-31 (searched
[issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls) for `make_glib`, `Glib`,
`Slippery`, `cond_slip`).
