**Title:** Saving a hero who is hiding as a mimic loses the disguise

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/21-mimic-disguise-save`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/21-mimic-disguise-save).

**Symptom**

Polymorphed into a mimic, `#monster` makes the hero mimic a strange object:
the map shows `]`, and `#monster` again says "You are already mimicking a
strange object." After a save and restore the hero is drawn as `m`, and
`#monster` says "You are now mimicking a strange object." and takes a turn.
Hiding as a hider (`u.uundetected`) survives a save, since it is in `u`.

Recording: a wizard-mode Valkyrie `#polyself`s into a giant mimic, uses
`#monster` twice, saves; segment 2 restores and uses `#monster`.

- [Step 33](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#step=33): "You are now mimicking a strange object.", hero drawn as `]`
- [Step 42](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#step=42): "You are already mimicking a strange object." before the save
- [Stock, segment 2, step 0](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#seg=2&step=0): after restore, hero drawn as `m`
- [Stock, segment 2, step 11](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session.json#seg=2&step=11): "You are now mimicking a strange object."
- [Patched, segment 2, step 0](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session-fixed.json#seg=2&step=0): still `]`
- [Patched, segment 2, step 11](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/21-mimic-disguise-save/session-fixed.json#seg=2&step=11): "You are already mimicking a strange object."

**Cause**

`dohide()` stores the disguise in `gy.youmonst`
([`polyself.c:1865-1870`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1865-L1870)):

```c
        gy.youmonst.m_ap_type = M_AP_OBJECT;
        gy.youmonst.mappearance = STRANGE_OBJECT;
```

`youmonst` is not saved; `restgamestate()` reads `u` and rebuilds
`youmonst` from it
([`restore.c:603-604`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L603-L604)),
restoring `cham` but not `m_ap_type` or `mappearance`, which are left at
`M_AP_NOTHING`. `set_uasmon()` already copies `youmonst.cham` into
`u.mcham` "for save/restore since youmonst isn't"
([`polyself.c:53`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L53));
the disguise fields were not given the same treatment. The other ways the
hero gets an appearance (eating a mimic corpse, the last turn of turning
into green slime) are brief.

**Fix**

Carry the two fields in `u`, as `u.mcham` carries `cham`:

```c
/* you.h, struct you, next to mcham */
    uchar um_ap_type;        /* youmonst.m_ap_type, for save/restore */
    unsigned umappearance;   /* youmonst.mappearance, for save/restore */
/* save.c, savegamestate(), before Sfo_you() */
    u.um_ap_type = gy.youmonst.m_ap_type;
    u.umappearance = gy.youmonst.mappearance;
/* restore.c, restgamestate(), after Sfi_you() */
    gy.youmonst.m_ap_type = u.um_ap_type;
    gy.youmonst.mappearance = u.umappearance;
```

Commit [03dacd04e](https://github.com/davidbau/NetHack/commit/03dacd04eae6fde6253d209b9f07a03bf74c27a4);
also `proposed-fix.patch`. The `INSURANCE` checkpoint also goes through
`savegamestate()`.

This changes the save format: `sizeof (struct you)` is checked when a save
is opened
([`version.c:618-619`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/version.c#L618-L619)),
so 5.0.0 saves would be refused. Alternatives: pack both values into the
saved but unused `long uspare1`
([`you.h:486`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/you.h#L486)),
wait for the next format break, or use the branch's new
`SAVEFILE_REVISION_LEVEL` mechanism.

**Repro**

```
bash bugs/21-mimic-disguise-save/repro.sh
```

re-records [`session.json`](session.json) and reads the `#monster` message
after the restore. Exit 0: the hero has to hide again (bug); 1: still
hiding (patched); 2: scenario did not play out. Both recordings have 45 + 12
steps with identical segment 1; stock has 2,878 RNG entries, patched 2,850
(the 28 are the turn spent re-hiding). Reverting and rebuilding reproduced
the stock recording exactly.
