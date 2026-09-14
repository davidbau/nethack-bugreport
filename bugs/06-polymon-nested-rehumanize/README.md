# `polymon()` runs on past a nested `rehumanize()`, re-touching equipment twice

**Component:** `src/polyself.c` `polymon()`, lines 929-932 and 971-974
**Severity:** LOW / player-visible. A duplicate artifact blast — a repeated
message **and** a second damage roll — from a single polymorph, plus a
duplicate full inventory touch-scan.
**Status upstream:** both sites already carry a DevTeam `FIXME?`.

## Symptom

One polymorph, two blasts:

```
You turn into a kobold!  The lava here burns you!
You return to human form!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
```

In the recorded RNG stream (`session.json`):

```
rnd(4)=1      @ polymon(polyself.c:866)          <- level-0 form, 1 hit point
d(6,6)=19     @ lava_effects(trap.c:6807)        <- lava damage
  ... losehp() -> u.mh < 1 -> rehumanize()
d(2,10)=5     @ touch_artifact(artifact.c:953)   <- blast 1: rehumanize's :1415
^botl[polymon]                                   <- control is back inside polymon()
d(2,10)=12    @ touch_artifact(artifact.c:953)   <- blast 2: polymon's :1021
```

**No assertion fires.**  Unlike its sibling
[bug 07](../07-polyself-light-delete-before-create/), this defect never calls
`impossible()` — verified across the recorded sessions.  A player sees a
repeated blast message and takes a second damage roll, with nothing in
paniclog.  A maintainer triaging by paniclog would never see it.

## Root cause

`polymon()` (`polyself.c:735-1071`) has exactly one early exit — the "cannot
become that" `return 0` at line 747. Two of its calls can revert the hero
mid-function, and the source flags both:

```c
/* polyself.c:929-932 */
    expels(u.ustuck, u.ustuck->data, expels_mesg);
    was_expelled = TRUE;
    /* FIXME? if expels() triggered rehumanize then we should
       return early */

/* polyself.c:972-974 */
        spoteffects(TRUE);
        /* FIXME? if spoteffects() triggered rehumanize then we should
           return early */
```

`rehumanize()` finishes with its own cleanup (`polyself.c:1410`
`encumber_msg()`, `polyself.c:1415` `retouch_equipment(2)`). Control then
returns into `polymon()`, which does both again at `polyself.c:1019` and
`polyself.c:1021`.

That is not a harmless repeat. `retouch_equipment()` guards against recursion
with a nesting counter:

```c
    if (!nesting++)
        clear_bypasses(); /* init upon initial entry */
```

The guard only helps when the two calls **nest**. Here they are **sequential** —
`rehumanize()`'s call has already returned and decremented `nesting` back to 0 —
so `polymon()`'s call clears the bypass bits again and re-scans the whole of
`gi.invent` from scratch, re-running the touch test on every worn, wielded and
carry-effect item.

## Reproducers

Four recorded C sessions: a witness per FIXME, each with a control that differs
by one ingredient. The measurement is the number of
`d(2,10) @ touch_artifact(artifact.c:953)` rolls after one polymorph.

| session | path | blasts |
|---|---|---|
| [`session.json`](session.json) | `spoteffects()` FIXME | **2** |
| [`session-expels.json`](session-expels.json) | `expels()` FIXME | **2** |
| control A (not shipped; same keys minus the lava wish) | no nested revert | 1 |
| control B (not shipped; same keys, form too small to be expelled) | no expulsion | 1 |

**The controls are the point.** In both of them the poly form *also* dies and
the hero *also* rehumanizes — but there the damage comes from `polymon()`'s own
`retouch_equipment(2)` blast, so `rehumanize()`'s call is genuinely nested,
`nesting` is 1, `clear_bypasses()` is skipped, every item is already bypassed
and nothing is re-scanned. The difference between 1 and 2 blasts isolates
"sequential" from "nested" exactly, and shows the existing guard is not what is
broken.

### Witness A — the `spoteffects()` FIXME ([`repro-lava.kp`](repro-lava.kp))

A neutral Valkyrie wearing **The Eye of the Aethiopica** stands on **lava** in
**fireproof water walking boots** and zaps a wand of polymorph with polymorph
control, choosing a **kobold**.

`polymon()` gives a level-0 form only `rnd(4)` hit points (`polyself.c:866`) and
lava does `d(6,6)`, so the form always dies inside `polymon()`'s own
`spoteffects()` call. `lava_effects()` reaches `losehp()` on one branch, and
note that the survival test reads the **human** hit points while `losehp()`
decrements `u.mh`:

```c
    usurvive = Fire_resistance || (Wwalking && dmg < u.uhp);
    ...
    if (Wwalking) { pline_The("%s here burns you!", hliquid("lava"));
                    if (usurvive) losehp(dmg, lava_killer, KILLED_BY);
```

That mismatch is what lets a healthy hero in a frail form pass the check and
still lose the form.

### Witness B — the `expels()` FIXME ([`repro-expels.kp`](repro-expels.kp))

Same hero sets a **land mine** at their feet, is swallowed by an **ochre
jelly**, then polymorphs into a **rothe**.

The ochre jelly is the only engulfer that is neither `MZ_HUGE` nor whirly
(level 6, `MZ_MEDIUM`), so any `MZ_LARGE`+ form trips the size test at
`polyself.c:915-918`. The mine survives the engulf because `gulpmu()`
(`mhitu.c:1292`) moves the *monster* onto the hero's square with
`place_monster()` — not `mintrap()` — and explicitly zeroes `mtmp->mtrapped`.
`expels()` ends in `spoteffects(TRUE)`, the mine fires, and `losehp()` reverts
the rothe from inside `polymon()`.

```
d(2,8)=10     @ polymon(polyself.c:868)          <- rothe, 10 hit points
>pline        @ expels(mhitu.c:296)              <- expelled
rn2(5)=3      @ dotrap(trap.c:3044)              <- did not escape the trap
rnd(16)=10    @ trapeffect_landmine(trap.c:2538)
  ... losehp() -> u.mh < 1 -> rehumanize()
d(2,10)=12    @ touch_artifact(artifact.c:953)   <- blast 1
d(2,10)=11    @ touch_artifact(artifact.c:953)   <- blast 2
```

### Why the artifact

The duplicate pass is silent on a plain hero. **The Eye of the Aethiopica** is a
quest artifact of the wrong role (Wizard) but the right alignment (neutral), so
`badclass` is true and `badalign` is false. `touch_artifact()` blasts on
`(badclass || badalign) && self_willed`, and because `badalign` is false the
`badclass && badalign && self_willed` removal branch does not fire, so
`retouch_object()` returns 1 and the amulet stays worn — which is exactly why a
second pass can blast again. `break_armor()` never removes amulets, so it
survives any target form.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch). Stop at every boundary where a
re-entrant callback may have replaced the form being configured:

```c
    if (u.umonnum != mntmp)
        return 1;
```

Testing `u.umonnum != mntmp` rather than `!Upolyd` is deliberate: a nested
callback can install a *different monster* form as well as reverting to human
(`instapetrify()` and `selftouch()` both call `polymon()` directly), and only
the stronger test catches that.

Returning 1 keeps the "polymorph happened" contract for `polyself()`, which
only ever does `(void) polymon(...)`.

The two DevTeam `FIXME?`s mark two of these boundaries. The audit should not
stop there — the current source has five, and C's own comments document the
re-entrancy at each:

| after | re-enters via | C's own comment |
|---|---|---|
| `break_armor()` / `drop_weapon(1)` | `Boots_off()` -> `spoteffects(TRUE)`; dropping an invoked levitation artifact | `dropp()`: *"Dropping worn armor while polymorphing might put hero into water"*; `drop_weapon()`: *"if heart of ahriman is wielded, we might be losing levitation by dropping it"* |
| `dismount_steed(DISMOUNT_POLY)` | `teleds()` -> `spoteffects()`; `instapetrify()` just above calls `polymon()` | `steed.c:747`: *"teleds() --> spoteffects() --> pickup()"* |
| `expels()` | ends in `spoteffects(TRUE)` | the `FIXME?` |
| `spoteffects(TRUE)` | `drown()` / `lava_effects()` / `dotrap()` -> `losehp()` | the `FIXME?` |
| `retouch_equipment(2)` | artifact blast -> `losehp()`; also direct re-entry | `polyself.c:1022`: *"this might trigger a recursive call to polymon()"* |

**Invariant preserved:** `retouch_equipment()` runs once per form change, and
nothing after a form change configures the form that was replaced.

### One boundary this does not fully close

A guard *after* `break_armor()` returns is necessary but may not be sufficient:
`break_armor()` caches `uptr` (the form it is working on) and keeps using it
after an internal `Boots_off()` has re-entered form-changing code. Closing that
properly needs either `break_armor()` to report invalidation to its caller, or
a check at its own internal boundary. Flagged here rather than half-fixed.

Everything between the boundaries and the end of `polymon()` also reads
`gy.youmonst.data` for a form the hero may no longer have (`Passes_walls` trap
release, `likes_lava`, the `amorphous`/`is_whirly`/`unsolid` chain release, web
and bear trap release, `check_strangling(TRUE)`, the `#monster` capability
hints). Those all fail *closed* for a human, so they are not separately
harmful — but the early returns stop them being evaluated at all.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt:

| session | unpatched | patched |
|---|---|---|
| witness A (lava) | 2 blasts | **1** ([`session-fixed.json`](session-fixed.json)) |
| witness B (expels) | 2 blasts | **1** ([`session-expels-fixed.json`](session-expels-fixed.json)) |
| control A | 1 blast | 1 (unchanged) |
| control B | 1 blast | 1 (unchanged) |

The RNG stream up to the polymorph is identical in each pair — the witnesses
draw the same `rnd(4)=1` / `d(2,8)=10` form hit points before and after — so
the patch removes the duplicate pass and nothing else.

## Related

The `del_light_source()` `impossible()` reachable from the same re-entrancy
window is a *separate* defect with a separate patch — see
[bug 07](../07-polyself-light-delete-before-create/).
These early returns do **not** fix it: that assertion fires inside
`rehumanize()`, several frames below, before `polymon()` gets a chance to test
anything. The two patches are independent and apply cleanly in either order.

## Reproducing

```
bash bugs/06-polymon-nested-rehumanize/repro.sh
```

Re-records `session.json` through a freshly built NetHack recorder binary and
asserts that **two** `touch_artifact()` blasts fire after a single polymorph.
It exits non-zero if only one fires — i.e. if the patch is already applied.

## Credit

The widened boundary audit and the `u.umonnum != mntmp` form of the test were
proposed in review by agent:xorn, a peer agent on the porting project this
came out of.
