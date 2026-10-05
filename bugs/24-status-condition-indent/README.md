**Title:** tty `statuslines:3`: weapon and armor status collide with the indented conditions

**Version:** NetHack 5.0.0 as released (`NetHack/NetHack@16ff59115`, where it
was recorded). Present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25. Introduced by `84ddf85cb` (April 2026), which added
`weaponstatus`, `armorstatus` and `terrainstatus` after the conditions; the
indentation code is from `d1dade164` ("tty statuslines:3", 2019), when only
`version` could follow them.

### Symptom

With `OPTIONS=statuslines:3,weaponstatus,armorstatus` and a condition such as
`Blind` showing, the third status line goes wrong:

1. **Weapon and armor disappear.** First `Dlvl:1       Spear Shield               Blind`;
   at the next status update of any kind (gold `$:0` to `$:100`) it becomes
   `Dlvl:1                                    Blind` until the weapon or armor
   field changes or the condition goes away.
2. **Stale characters.** When the condition moves left (gold dropped, second
   line two columns shorter), `Blind` becomes `Blindnd`.
3. **With `showvers`, the condition never appears:**
   `Dlvl:1       Spear Shield          ...          5.0.0` while blind.

Nothing depends on which condition it is. The two-line layout, and three lines
without weapon/armor/terrain status, are unaffected.

A wizard-mode Valkyrie (spear, shield) puts on a blindfold, wishes for 100
gold, and drops it:
[step 13](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=13) `Blind` appears,
[step 30](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=30) `Spear Shield` disappears,
[step 32](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=32) `Blindnd`;
[with `showvers`, step 13](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-showvers.json#step=13) no `Blind`.
Patched: [step 32](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-fixed.json#step=32),
[`showvers` step 13](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-showvers-fixed.json#step=13).

### Cause

`threelineorder[]` puts conditions ahead of the new fields
([`wintty.c:4290-4299`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L4290-L4299)):

```c
    { BL_LEVELDESC, BL_TIME, BL_CONDITION, BL_WEAPON, BL_ARMOR, BL_TERRAIN,
```

`check_fields()` places `BL_WEAPON` after the unindented conditions; then
`render_status()` indents the conditions to line up with hunger, blanking the
columns it moves over, which include weapon and armor
([`wintty.c:5062-5070`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5062-L5070)):

1. `tty_status[BEFORE][BL_CONDITION].x` is the indented column, so the
   condition always looks moved and is redrawn with its blanking, while
   `check_fields()`
   ([`wintty.c:4671-4682`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L4671-L4682))
   finds the weapon unchanged and does not redraw it.
2. `finalx[row][NOW] = x - 1`
   ([`wintty.c:5240`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5240))
   ends at the armor field, left of the conditions, so the `cl_end()`
   ([`wintty.c:5251-5256`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5251-L5256))
   that runs only when `finalx` shrinks never clears the conditions' old tail.
3. The `version` right-justify code
   ([`wintty.c:5187-5211`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5187-L5211))
   resyncs `x` only when the previous field is `BL_CONDITION`; now it is
   `BL_TERRAIN`, so blanking up to the version column erases the conditions.

The `FIXME` next to the `version` code predates `84ddf85cb` and is not about
this bug.

### Fix

Put weapon, armor and terrain ahead of the conditions on the third row, so
only `version` follows them, as the indentation code expects:

```diff
-    { BL_LEVELDESC, BL_TIME, BL_CONDITION, BL_WEAPON, BL_ARMOR, BL_TERRAIN,
+    { BL_LEVELDESC, BL_TIME, BL_WEAPON, BL_ARMOR, BL_TERRAIN, BL_CONDITION,
```

Weapon and armor then sit after `Dlvl` and the time; the conditions stay
lined up with hunger. [`proposed-fix.patch`](proposed-fix.patch); fixed code
[`wintty.c:4289-4302`](https://github.com/davidbau/NetHack/blob/7c0a3df29893d13aaf12896355f2612853f66345/win/tty/wintty.c#L4289-L4302),
[commit 7c0a3df29](https://github.com/davidbau/NetHack/commit/7c0a3df29893d13aaf12896355f2612853f66345),
branch [`bugreport/24-status-condition-indent`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/24-status-condition-indent).

Alternatives: teach `check_fields()` about the indentation (a larger change),
or skip the indentation when a field other than `version` follows the
conditions. Making `finalx[row][NOW]` the largest column drawn was built and
recorded: it removes `nd` but `Spear Shield` still disappears at step 30.

### Repro

```
bash bugs/24-status-condition-indent/repro.sh
```

Re-records [`session.json`](session.json) and
[`session-showvers.json`](session-showvers.json) and checks the bottom line for
all three symptoms; exits 0 when present, 1 when drawn correctly (patched).
By hand: the options above, a Valkyrie, a blindfold, then anything that
changes the second status line.

Patched recordings have the same step counts (34, 37) and identical RNG
streams (2,843, 2,910 entries); screens differ only on row 23 from step 13 on.
Reverting and rebuilding reproduces both stock recordings byte-for-byte.
