# With `statuslines:3`, weapon and armor status collide with the indented conditions

With `OPTIONS=statuslines:3` and the new 5.0 options `weaponstatus` and
`armorstatus`, the third status line goes wrong as soon as a status condition
such as `Blind` is showing. Three things can be seen:

1. **Weapon and armor disappear.** When the condition first appears the line
   reads `Dlvl:1       Spear Shield               Blind`. At the next status
   update of any kind (here, gold changing from `$:0` to `$:100`) `Spear Shield`
   is blanked and not redrawn: `Dlvl:1                                    Blind`.
   It stays blank until the weapon or armor field itself changes or the
   condition goes away.
2. **The condition leaves stale characters.** When the condition moves left
   (here, the gold is dropped and the second status line gets two columns
   shorter), its old last two characters are not erased: `Blind` becomes
   `Blindnd`.
3. **With `showvers` as well, the condition never appears.** The line reads
   `Dlvl:1       Spear Shield          ...          5.0.0` while the hero is
   blind. `Blind` is written and then blanked in the same redraw.

Only `Blind` was recorded, but nothing in the code depends on which condition
it is, so the same would happen to any condition, including `Stone` or
`Slime`. The two-line status layout is not affected, and neither is the
three-line layout without weapon, armor or terrain status.

The affected code is `render_status()` and `threelineorder[]` in
`win/tty/wintty.c`. It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/24-status-condition-indent`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/24-status-condition-indent)
holds one proposed commit, verified by rebuild.

Severity: low. It is display only and needs the non-default `statuslines:3`
plus `weaponstatus` or `armorstatus`, but in that configuration the new fields
are unreliable whenever a condition is showing, and with `showvers` the
conditions themselves are hidden.

## Watch it happen

A Valkyrie (spear wielded, shield worn) in wizard mode puts on a wished-for
blindfold, wishes for 100 gold, and drops it. Look at the bottom line.

- [**Step 13**: `Blind` appears, indented to line up with where hunger would be; `Spear Shield` is drawn in the gap](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=13)
- [**Step 30**: gold changes and `Spear Shield` disappears](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=30)
- [**Step 32**: gold is dropped, `Blind` moves two columns left and leaves `Blindnd`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session.json#step=32)
- [**With `showvers`, step 13**: blind, but no `Blind` on the status line](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-showvers.json#step=13)
- [**Patched, step 32**: `Dlvl:1 Spear Shield                     Blind`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-fixed.json#step=32)
- [**Patched with `showvers`, step 13**: `Blind` and `5.0.0` both shown](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/24-status-condition-indent/session-showvers-fixed.json#step=13)

## Reproducing it

```
bash bugs/24-status-condition-indent/repro.sh
```

That re-records [`session.json`](session.json) and
[`session-showvers.json`](session-showvers.json) through the recorder binary
and checks the bottom line for all three symptoms. It exits 0 when they are
present and 1 when the line is drawn correctly (as with the patch applied).

By hand: `OPTIONS=statuslines:3,weaponstatus,armorstatus`, play a Valkyrie,
put on a blindfold, then do anything that changes the second status line.

## What the code is doing

The third row's field order puts conditions ahead of the new fields
([`wintty.c:4290-4299`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L4290-L4299)):

```c
    { BL_LEVELDESC, BL_TIME, BL_CONDITION, BL_WEAPON, BL_ARMOR, BL_TERRAIN,
      BL_VERS, BL_FLUSH, blPAD,
```

`check_fields()` gives each field its column by adding up the lengths of the
fields before it, so `BL_WEAPON` is placed right after where the conditions
would be if they were not indented. `render_status()` then indents the
conditions on the third row to line up with hunger on the second, blanking the
columns it moves over
([`wintty.c:5062-5070`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5062-L5070)):

```c
                        /* indent conditions to line them up with 2nd row */
                        if (x < cstart) {
                            do {
                                if (dat[x - 1] != ' ')
                                    tty_putstatusfield(" ", x, y);
                            } while (++x < cstart);
                            tty_status[NOW][BL_CONDITION].x = x;
                            tty_curs(WIN_STATUS, x, y);
                        }
```

The weapon and armor columns lie inside the columns this blanks. That explains
each symptom:

1. After the indentation, `tty_status[BEFORE][BL_CONDITION].x` is the indented
   column while `check_fields()` computes the unindented one, so the condition
   always looks moved and is redrawn, with its blanking. The weapon field's own
   position and length have not changed, so `check_fields()`
   ([`wintty.c:4671-4682`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L4671-L4682))
   decides it is "back in sync" and does not redraw it. It was just blanked.
2. `finalx[row][NOW] = x - 1;`
   ([`wintty.c:5240`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5240))
   is set after every field, so it ends up at the end of the armor field, left
   of the conditions. The end-of-row `cl_end()`
   ([`wintty.c:5251-5256`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5251-L5256))
   only runs when `finalx` gets smaller, and the armor end does not move when
   the conditions do, so the old tail of the conditions is never cleared.
3. The code that right-justifies `version`
   ([`wintty.c:5187-5211`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L5187-L5211))
   resynchronizes `x` to the end of the conditions only when the previous
   entry in the field order is `BL_CONDITION`. Now it is `BL_TERRAIN`, so `x`
   is still at the end of the armor field and the blanking up to the version
   column erases the conditions that were just drawn.

The indentation code was written in 2019 (`d1dade164`, "tty statuslines:3"),
when only `version` could follow the conditions, and the code for that case
(`last_col` adjusted when `BL_VERS` follows, the `version` resync) still
assumes it. `weaponstatus`, `armorstatus` and `terrainstatus` were added after
the conditions in April 2026 (`84ddf85cb`) without changing the indentation.
The `FIXME` next to the `version` code predates them, so it is not a report of
this bug.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): on the third row, put weapon,
armor and terrain ahead of the conditions, which restores the layout the
indentation code expects (only `version` after the conditions).

```c
    { BL_LEVELDESC, BL_TIME, BL_WEAPON, BL_ARMOR, BL_TERRAIN, BL_CONDITION,
      BL_VERS, BL_FLUSH, blPAD,
```

Fixed code:
[`wintty.c:4289-4302`](https://github.com/davidbau/NetHack/blob/7c0a3df29893d13aaf12896355f2612853f66345/win/tty/wintty.c#L4289-L4302)
· diff:
[commit 7c0a3df29](https://github.com/davidbau/NetHack/commit/7c0a3df29893d13aaf12896355f2612853f66345).

The visible change is that the weapon and armor now sit right after `Dlvl` and
the time, and the conditions stay lined up with hunger to their right, which is
close to what the stock build shows on the first redraw anyway. The two-line
order is unchanged: conditions are only indented on the third row.

**Alternatives.** Keeping the current order would mean teaching
`check_fields()` about the indentation, so that fields after the conditions
are placed after the indented conditions. That is a larger change to code that
decides what gets redrawn. A smaller change would be to skip the indentation
whenever a field other than `version` follows the conditions. The fix in an
earlier draft of this report, making `finalx[row][NOW]` the largest column
drawn on the row rather than the last, was also built and recorded: it removes
the stale `nd` but `Spear Shield` still disappears at step 30, so it fixes
only symptom 2.

## Verification

Rebuilt and re-recorded, same seed, same datetime, same keystream:

| | stock | patched |
|---|---|---|
| `session.json`: steps | 34 | 34 |
| `session.json`: RNG entries | 2,843 | 2,843 (identical) |
| step 30 bottom line | `Dlvl:1` ... `Blind` (no weapon/armor) | `Dlvl:1 Spear Shield` ... `Blind` |
| step 32 bottom line | ... `Blindnd` | ... `Blind` |
| `session-showvers.json`: steps | 37 | 37 |
| `session-showvers.json`: RNG entries | 2,910 | 2,910 (identical) |
| step 13 bottom line | `Spear Shield` ... `5.0.0`, no `Blind` | `Spear Shield` ... `Blind` ... `5.0.0` |

The screens differ only on the bottom line (row 23), from step 13 on. The RNG
streams are identical, so the patch changes the display and nothing else.
Reverting the source and rebuilding reproduced both stock recordings
byte-for-byte, which is the control that the patched run differed because of
the patch rather than the rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from
Claude Opus 5.5. It surfaced when a screen comparison between the port and C,
run with `statuslines:3` and the new weapon and armor status options, showed C
leaving stale characters on the third status line; working out why led to the
other two symptoms.
