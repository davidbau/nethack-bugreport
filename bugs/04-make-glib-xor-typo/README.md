# Bug #04 — `make_glib` botl-dirty XOR is inverted (one-`!` typo)

**Status:** unreported upstream as of 2026-06-19 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
and [PRs](https://github.com/NetHack/NetHack/pulls) for
`make_glib`, `Glib`, `Slippery`, `disp.botl Glib`, `potion.c 463` —
no matching issue or PR).

**NetHack version:** 5.0.0 (also present in the 3.7 line; the
`make_glib()` function in `src/potion.c` has not changed in this
area for several years).

**Not patch-induced:** the bug is a one-character difference in a
single line of source.  The `repro.c` shipped with this bundle is
self-contained — it implements both the buggy and corrected
expressions in pure C with no NetHack headers, exercises them
against all four `(old_Glib, new_xtime)` state combinations, and
prints the resulting truth table.  No NetHack build required to
confirm.

**Severity:** LOW / LATENT.  The bug is a real defect — the XOR
expression returns the inverse of the boolean-transition
predicate it was clearly meant to compute — but `bot()` is called
every player turn anyway, driven by other status changes that
mark `disp.botl` correctly.  Verified empirically by rebuilding
the C source with the proposed fix and re-recording a session
that exercises `make_glib` (see "Verification by C-rebuild"
below): the rendered status line is identical between buggy and
fixed in every stock 5.0 configuration I could construct.  Worth
fixing for code-quality and future-proofing reasons, not for any
present-day in-game symptom.

## What you see in-game

**Nothing.**  The Glib state itself is set correctly by
`set_itimeout(&Glib, xtime)` immediately after the buggy line, so
all of NetHack's downstream Glib-related behavior (the
"Your X slips from your hands" message, the wielding-failure
check, the gloves slipperiness tag) fires correctly.  Only the
status-line dirty flag is wrong, and only for the
`disp.botl |=` line — `disp.botl` is OR-set TRUE on
no-transition turns and left clean on real transition turns.
Since other turn-changes mark `disp.botl` independently, the
incorrect dirty flag is masked.

## The bug, in one line of source

`src/potion.c:463` (inside `make_glib()`):

```c
disp.botl |= (!Glib ^ !!xtime);
```

The intended idiom is the standard "did this boolean state
change?" predicate, where each side is coerced to a boolean
(`!!`).  The expression as written uses `!` on the left and `!!`
on the right, producing the inverse: the dirty flag is set
exactly when the state DOESN'T change.

The truth table (also produced by `repro.c`):

| old `Glib` | new `xtime` | `!Glib` | `!!xtime` | buggy XOR | fixed XOR | should fire? | verdict |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 1 | 0 | **1** | 0 | no | inverted |
| 0 | ≠0 (becomes Glib) | 1 | 1 | **0** | 1 | YES | inverted |
| ≠0 | 0 (Glib expires) | 0 | 0 | **0** | 1 | YES | inverted |
| ≠0 | ≠0 (refresh) | 0 | 1 | **1** | 0 | no | inverted |

## Three lines of evidence this is a typo, not a design choice

1. **The sibling function 12 lines above does it right.**
   `make_deaf()` at `potion.c:443-456` writes exactly the same
   boolean-transition predicate, just spelled in the more verbose
   form that elides the typo risk:
   ```c
   set_itimeout(&HDeaf, xtime);
   if ((xtime != 0L) ^ (old != 0L)) {
       disp.botl = TRUE;
       ...
   }
   ```
   `(x != 0L) ^ (old != 0L)` is mathematically identical to
   `(!!Glib) ^ (!!xtime)`.  The author of `make_glib` clearly
   knew the right pattern; they just lost one `!` typing it.
2. **The "redraw on no-transition" semantic has no apparent
   purpose.**  The status line doesn't display the Glib timer's
   *value*, only the boolean Slippery indicator, so no-change ==
   no-redraw is the right pattern.  If the author *wanted*
   redraw-on-no-transition they would have used `==` or `XNOR`,
   not the inverted-XOR formulation a typo produces.
3. **The fix is one keystroke** — insert one `!` to make the
   left half a coerced boolean, matching the right half.  No
   API change, no semantic change beyond restoring the obvious
   intent.

## Verification by C-rebuild

I applied `proposed-fix.patch` to my local
`nethack-c/patched/src/potion.c`, rebuilt the C nethack binary,
re-recorded the same session
(`seed6287-wizard-grease-hands`, plus `OPTIONS=time` and a
keystream extension to dismiss the trailing `--More--` and search,
exercising several turns after `make_glib`), and reverted.

**Event-stream evidence:**
the `^botl` / `>bot` event sequences differ between buggy and
fixed — proving `bot()` is being called at different turns.
This is the unambiguous signature of the dirty-flag bug.

**Screen-content evidence:**
the rendered status line is *identical* between buggy and fixed
at every step.  The reason is that other status fields (HP, Pw,
T, AC, Xp) happen to be the same regardless of which turn
`bot()` runs on, and the "Slippery" condition indicator that
*would* show the bug is opt-in (`OPTIONS=cond_slip` plus
`statushilites`/`statuslines` plumbing) and didn't display in
any nethackrc I tried.  In stock 5.0 default configurations,
the bug truly has no visible symptom.

## Why it's still worth fixing

- **Code-quality**: the line literally computes the opposite of
  what its surrounding code style indicates.  A future
  contributor reading `make_glib` after `make_deaf` will see one
  function that does it right and one that does it backwards, in
  the same file, twelve lines apart.
- **Future-proofing**: if NetHack ever changes how `disp.botl`
  interacts with conditions (e.g., a refactor that makes the
  status indicator more visible by default), the inverted XOR
  becomes a real visible bug.  Better to fix the typo while it
  is still cheap.
- **Cardinal Rule 2 cost on the JS-port side**:
  [davidbau/teleport](https://github.com/davidbau/teleport)
  reproduces the typo verbatim today (`js/mhitu.js:3554`
  `make_glib`) so its `^botl` event stream matches C bit-for-bit.
  Every porter who hits this line has to discover for themselves
  that the inverted XOR is intentional-by-parity, not a JS bug.
  Fixing upstream would let the JS port unwind one of its
  Cardinal Rule 2 "port the bug" caveats.

## Proposed patch

See `proposed-fix.patch`.  **Insert one `!`** at `src/potion.c:463`
so the left half of the XOR is also a coerced boolean:

```diff
-    disp.botl |= (!Glib ^ !!xtime);
+    disp.botl |= (!!Glib ^ !!xtime);
```

Or, mirroring the adjacent `make_deaf` shape verbatim (slightly
more verbose but immune to typo risk):

```c
{
    int old = (int) Glib;
    set_itimeout(&Glib, xtime);
    if ((xtime != 0) ^ (old != 0))
        disp.botl = TRUE;
}
```

## Test artifacts

- `repro.c` — standalone C program; no NetHack headers, no
  linking, no recorder. Implements both the buggy and corrected
  expressions in pure C, exercises them against all four
  state combinations, prints the truth table.
- `repro.sh` — wrapper: compiles `repro.c` with `${CC:-cc}` and
  reports exit status.
- `proposed-fix.patch` — the one-character diff against vanilla
  `src/potion.c`.

No `session.json` for this bug: a full screen-level
gameplay-recording demo was attempted via C-rebuild + re-record,
and confirmed the bug fires at the event level but produces
identical rendered status-line content in every stock 5.0
configuration I could construct.  The static truth-table repro
in `repro.c` is the authoritative reproducer for this bug.
