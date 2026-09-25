# Saving a hero who is hiding as a mimic loses the disguise

Polymorph into a mimic, use `#monster`, and the hero hides by mimicking a
strange object: the map shows `]` where the hero stands, `#monster` again says
"You are already mimicking a strange object.", and monsters that blunder into
the hero are surprised ("Wait, <monster>! That's a giant mimic named <name>!").

Save the game and restore it, and the disguise is gone. The map shows the hero
as `m`, and `#monster` says "You are now mimicking a strange object." and uses
a turn, because as far as the game is concerned the hero was not hiding. The
other kind of hiding, used by hiders such as a piercer on the ceiling, is
recorded in `u.uundetected`, which is part of the saved `u`, so the two kinds of
hiding are treated differently by a save.

The affected code is `dohide()` in `src/polyself.c`, which keeps the disguise
in `gy.youmonst`, together with `savegamestate()` and `restgamestate()` in
`src/save.c` and `src/restore.c`, which do not save `gy.youmonst`. It is
present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117), checked
2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`, NetHack
5.0.0 as released. The branch
[`bugreport/21-mimic-disguise-save`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/21-mimic-disguise-save)
holds one proposed commit, verified by rebuild.

Severity: low. The player loses a disguise they paid a turn for, silently, and
the two kinds of hiding disagree across a save.

## Watch it happen

A wizard-mode Valkyrie polymorphs into a giant mimic with `#polyself`, uses
`#monster`, uses `#monster` again, and saves. A second segment restores the game
and uses `#monster` once more.

- [**Step 33**: "You are now mimicking a strange object." The hero is drawn as `]`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#step=33)
- [**Step 42**: "You are already mimicking a strange object." just before the save](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#step=42)

The restore is the session's second segment:

- [**Stock, segment 2, step 0**: the "welcome back" screen; the hero is drawn as `m`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#seg=2&step=0)
- [**Stock, segment 2, step 11**: `#monster` says "You are now mimicking a strange object."](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#seg=2&step=11)
- [**Patched, segment 2, step 0**: the hero is still drawn as `]`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session-fixed.json#seg=2&step=0)
- [**Patched, segment 2, step 11**: `#monster` says "You are already mimicking a strange object."](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session-fixed.json#seg=2&step=11)

| segment 2 | stock ([`session.json`](session.json)) | patched ([`session-fixed.json`](session-fixed.json)) |
|---|---|---|
| step 0, the "welcome back" screen | hero drawn as `m` | hero drawn as `]` |
| step 11, `#monster` | "You are now mimicking a strange object." (takes a turn) | "You are already mimicking a strange object." (no time) |

## What the code is doing

`dohide()` records a hero-mimic's disguise in the hero's monster structure:

```c
    if (ismimic) {
        /* should bring up a dialog "what would you like to imitate?" */
        gy.youmonst.m_ap_type = M_AP_OBJECT;
        gy.youmonst.mappearance = STRANGE_OBJECT;
    } else
        u.uundetected = 1;
```

Source: [`src/polyself.c:1865-1870`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1865-L1870).

`display_self()` draws the hero as the object in `mappearance` while
`m_ap_type` is `M_AP_OBJECT`
([`display.h:251-260`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/display.h#L251-L260)),
and the rest of the game (`mhitu.c`, `monmove.c`, `mthrowu.c`, `vault.c`,
`insight.c`) tests `U_AP_TYPE` to decide whether the hero is disguised.

`gy.youmonst` is not written to the save file. The save writes `u`, and the
restore rebuilds `youmonst` from it:

```c
    Sfi_you(nhfp, &u, "gamestate-you");
    gy.youmonst.cham = u.mcham;
```

Source: [`src/restore.c:603-604`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L603-L604).

`set_uasmon()` then sets `youmonst.data`, but nothing restores `m_ap_type` or
`mappearance`, so in the restored process they have their initial value,
`M_AP_NOTHING`. The DevTeam already met this problem for one other field:
`set_uasmon()` copies `youmonst.cham` into `u.mcham` with the comment
`/* for save/restore since youmonst isn't */`
([`polyself.c:53`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L53)).
The disguise fields seem simply to have been missed. We found no comment in
`save.c`, `restore.c` or `polyself.c` saying the disguise is meant to be dropped
on save, and the game gives no message when it is.

The other ways the hero gets an appearance are brief and happen while the
hero is helpless or about to die (eating a mimic corpse; the last turn of
turning into green slime), so `#monster` is the case a player will meet.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): carry the two fields in `u`, the
way `u.mcham` carries `youmonst.cham`.

```c
/* you.h, struct you, next to mcham */
    uchar um_ap_type;        /* youmonst.m_ap_type, for save/restore */
    unsigned umappearance;   /* youmonst.mappearance, for save/restore */

/* save.c, savegamestate(), just before Sfo_you() */
    /* youmonst isn't saved; keep hero's disguise (mimic hiding via
       #monster) with u, the way u.mcham keeps youmonst.cham */
    u.um_ap_type = gy.youmonst.m_ap_type;
    u.umappearance = gy.youmonst.mappearance;

/* restore.c, restgamestate(), after Sfi_you() */
    gy.youmonst.m_ap_type = u.um_ap_type;
    gy.youmonst.mappearance = u.umappearance;
```

Fixed code and diff:
[commit 03dacd04e](https://github.com/davidbau/NetHack/commit/03dacd04eae6fde6253d209b9f07a03bf74c27a4).

Copying at save time, rather than at every place that changes the disguise,
keeps the change to three places, and the checkpoint path (`INSURANCE`) goes
through `savegamestate()` too.

**This changes the save file format.** `sizeof (struct you)` is one of the
critical sizes checked when a save file is opened
([`version.c:618-619`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/version.c#L618-L619)),
so a build with this patch will refuse save files from 5.0.0 as released. If
that is unwelcome for a point release, the same information fits in the
existing `long uspare1` field of `struct you`
([`you.h:486`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/you.h#L486)),
which is saved but unused, at the cost of packing two values into one; or it
could wait for the next change that breaks the format anyway. The
`NetHack-5.0` branch has also started a save-file revision mechanism
(`SAVEFILE_REVISION_LEVEL`) that may be the DevTeam's preferred route. We have
not tried to choose among these.

## Verification

Rebuilt and re-recorded. Same seeds, same datetimes, same keystrokes:

| | stock | patched |
|---|---|---|
| steps recorded (segment 1 + segment 2) | 45 + 12 | 45 + 12 |
| RNG entries | 2,878 | 2,850 |
| hero glyph after the restore | `m` | `]` |
| `#monster` after the restore | "You are now mimicking a strange object." | "You are already mimicking a strange object." |

Segment 1 is identical in the two recordings. The 28 extra RNG entries in the
stock run are the turn that the second `#monster` spends re-hiding. Reverting
the source and rebuilding reproduced the stock recording exactly (every segment
identical), which is the control that the patched run differed because of the
patch rather than because of the rebuild.

## Reproducing it

```
bash bugs/21-mimic-disguise-save/repro.sh
```

That re-records [`session.json`](session.json) through the recorder binary and
reads the `#monster` message after the restore. It exits 0 if the hero has to
hide again (the bug), 1 if the hero is still hiding (the patch is applied), and
2 if the scenario did not play out.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced while porting save and restore: the port's restore had to
decide which of the hero's monster fields to rebuild, and matching C meant
deliberately dropping these two.
