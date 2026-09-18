# One polymorph, two artifact blasts

If you are carrying an artifact that blasts you, and a polymorph is undone
while it is still being set up, the artifact blasts you twice for that single
polymorph. The message repeats and the second blast rolls fresh damage:

```
You turn into a kobold!  The lava here burns you!
You return to human form!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
```

In the recorded session that costs the hero 5 hit points and then another 12,
from one zap of a wand of polymorph. The player sees a duplicated message and
takes damage twice for one event.

Nothing asserts, and that is part of the problem. No `impossible()` fires and
nothing reaches paniclog, so anyone triaging by paniclog will never see this.
The only trace is the repeated message.

The cause is that `polymon()` keeps running after something inside it has
already undone the polymorph. The DevTeam has marked two of the places where
this can happen with `FIXME?` comments; the audit below finds five.

|  |  |
|---|---|
| Affects | NetHack 5.0 (the `NetHack-3.7` branch), `src/polyself.c` |
| Severity | Low, but player-visible: a duplicate message and a duplicate damage roll |
| Upstream status | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0) (checked 2026-09-18): both `FIXME?`s are there and `polymon()` still has no guard. No upstream fix. |
| Recorded against | `NetHack/NetHack@16ff59115` |

## Watch it happen

Two routes into the same defect are recorded, one per `FIXME?`. Step through
them in the browser; no build required.

**Route A, the `spoteffects()` FIXME** (polymorph over lava):

- [**Buggy** (stock 5.0), the second blast](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session.json#step=178)
- [**Fixed** (with `proposed-fix.patch`), same step](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-fixed.json#step=178)

Step 177 is identical in both runs: the first blast, hit points 100 to 95. At
step 178 the stock build blasts a second time, 95 to 83, while the patched
build moves on to the goblin's attack.

**Route B, the `expels()` FIXME** (land mine under an ochre jelly):

- [**Buggy**, the second blast](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels.json#step=247)
- [**Fixed**, same point in the run](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels-fixed.json#step=246)

Again the runs agree through the first blast at step 245 (227 to 215) and part
company at the second (215 to 206).

There is also a [static side-by-side
view](https://davidbau.github.io/nethack-bugreport/bugs/06-polymon-nested-rehumanize/visualization.html)
of route A.

## What is in the recordings

The measurement is the number of `d(2,10) @ touch_artifact(artifact.c:953)`
rolls that follow a single polymorph. Route A:

```
rnd(4)=1      @ polymon(polyself.c:866)          <- level-0 form, 1 hit point
d(6,6)=19     @ lava_effects(trap.c:6807)        <- lava damage
  ... losehp() -> u.mh < 1 -> rehumanize()
d(2,10)=5     @ touch_artifact(artifact.c:953)   <- blast 1, from rehumanize's :1415
^botl[polymon]                                    <- control is back inside polymon()
d(2,10)=12    @ touch_artifact(artifact.c:953)   <- blast 2, from polymon's :1021
```

Route B:

```
d(2,8)=10     @ polymon(polyself.c:868)          <- rothe, 10 hit points
>pline        @ expels(mhitu.c:296)              <- expelled from the jelly
rn2(5)=3      @ dotrap(trap.c:3044)              <- did not escape the trap
rnd(16)=10    @ trapeffect_landmine(trap.c:2538)
  ... losehp() -> u.mh < 1 -> rehumanize()
d(2,10)=12    @ touch_artifact(artifact.c:953)   <- blast 1
d(2,10)=11    @ touch_artifact(artifact.c:953)   <- blast 2
```

The `@ file:line` annotations in those two excerpts are the recorder's own
output, so they carry the line numbers of the instrumented build rather than
of stock upstream. Files that take marker patches drift by a few lines:
`trap.c` by 7, `mhitu.c` by 1, while `polyself.c` and `artifact.c` match
exactly. Every line number in the prose below is against the pinned upstream
commit.

Two controls, not shipped here, pin the mechanism down. Both use the same
keystrokes as a witness with one ingredient removed: control A drops the lava
wish, control B uses a form too small to be expelled. In both controls the
poly form still dies and the hero still reverts, but the damage comes from
`polymon()`'s own `retouch_equipment(2)` blast, so `rehumanize()`'s call is
genuinely nested inside it. Both controls blast once. The difference between
one blast and two separates "sequential" from "nested" exactly, and shows that
the existing recursion guard is not the thing that is broken.

## What the code is doing

`polymon()` ([`polyself.c:735-1071`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L735-L1071)) has exactly one early exit, the "cannot
become that" `return 0` at line 747. Two of the calls it makes can revert the
hero in the middle of the function, and the source flags both:

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

Source: [`src/polyself.c:929-932`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L929-L932) and
[`src/polyself.c:972-974`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L972-L974).

When one of those does trigger a revert, `rehumanize()` runs to completion,
including its own cleanup: `encumber_msg()` at `polyself.c:1410` and
`retouch_equipment(2)` at `polyself.c:1415`. Control then returns into
`polymon()`, which does both of those again at `polyself.c:1019` and
`polyself.c:1021`.

`retouch_equipment()` does guard against recursion, with a nesting counter:

```c
    if (!nesting++)
        clear_bypasses(); /* init upon initial entry */
```

Source: [`src/artifact.c:2659-2660`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/artifact.c#L2659-L2660).

That guard only helps when the two calls nest. Here they are sequential:
`rehumanize()`'s call has already returned and decremented `nesting` back to 0,
so `polymon()`'s call clears the bypass bits again and re-scans all of
`gi.invent` from scratch, re-running the touch test on every worn, wielded and
carry-effect item.

### How each route reaches a revert

**Route A.** A neutral Valkyrie wearing The Eye of the Aethiopica stands on
lava in fireproof water walking boots and zaps a wand of polymorph with
polymorph control, choosing a kobold. `polymon()` gives a level-0 form only
`rnd(4)` hit points (`polyself.c:866`) and lava does `d(6,6)`, so the form
always dies inside `polymon()`'s own `spoteffects()` call. The survival test in
`lava_effects()` is worth a look, because it reads the *human* hit points while
`losehp()` decrements `u.mh`:

```c
    usurvive = Fire_resistance || (Wwalking && dmg < u.uhp);
    ...
    if (Wwalking) { pline_The("%s here burns you!", hliquid("lava"));
                    if (usurvive) losehp(dmg, lava_killer, KILLED_BY);
```

Source: [`src/trap.c:6811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6811) and the `Wwalking` branch at
[`src/trap.c:6872-6875`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6872-L6875).

That mismatch is what lets a healthy hero in a frail form pass the check and
still lose the form.

**Route B.** The same hero sets a land mine at their feet, is swallowed by an
ochre jelly, then polymorphs into a rothe. The ochre jelly is the only engulfer
that is neither `MZ_HUGE` nor whirly (level 6, `MZ_MEDIUM`), so any `MZ_LARGE`
or bigger form trips the size test at
[`polyself.c:917-920`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L917-L920). The mine survives
the engulf because `gulpmu()` moves the *monster* onto the hero's square with
`place_monster()` rather than `mintrap()`, and explicitly zeroes
`mtmp->mtrapped` ([`mhitu.c:1310-1312`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mhitu.c#L1310-L1312)). `expels()` ends in `spoteffects(TRUE)`, the mine
fires, and `losehp()` reverts the rothe from inside `polymon()`.

### Why an artifact is needed to see it

The duplicate pass is invisible on a plain hero: re-touching equipment that is
safe to touch has no effect. The Eye of the Aethiopica is a quest artifact of
the wrong role (Wizard) but the right alignment (neutral), so `badclass` is
true and `badalign` is false. `touch_artifact()` blasts on
`(badclass || badalign) && self_willed`, and since `badalign` is false the
`badclass && badalign && self_willed` removal branch does not fire, so
`retouch_object()` returns 1 and the amulet stays worn. That is what lets a
second pass blast again. `break_armor()` never removes amulets, so it survives
any target form.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch) stops at every boundary where a
re-entrant callback may have replaced the form being configured:

```c
    if (u.umonnum != mntmp)
        return 1;
```

The patch is also applied on a branch of a NetHack fork, so the change can be
read as a diff without downloading anything: [commit
8076a1822](https://github.com/davidbau/NetHack/commit/8076a18220413d8bc6e0ff871c06fa420c8f5793)
(or as a [compare
view](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/06-polymon-nested-rehumanize)
against the pinned upstream commit). Branch:
`bugreport/06-polymon-nested-rehumanize`.

Testing `u.umonnum != mntmp` rather than `!Upolyd` is deliberate. A nested
callback can install a *different monster* form as well as reverting to human,
since `instapetrify()` and `selftouch()` both call `polymon()` directly, and
only the stronger test catches that. Returning 1 keeps the "polymorph happened"
contract for `polyself()`, which only ever does `(void) polymon(...)`.

The two `FIXME?`s mark two of these boundaries. The audit should not stop
there: the current source has five, and C's own comments document the
re-entrancy at each.

| after | re-enters via | C's own comment |
|---|---|---|
| `break_armor()` / `drop_weapon(1)` | `Boots_off()` -> `spoteffects(TRUE)`; dropping an invoked levitation artifact | `dropp()`: *"Dropping worn armor while polymorphing might put hero into water"*; `drop_weapon()`: *"if heart of ahriman is wielded, we might be losing levitation by dropping it"* |
| `dismount_steed(DISMOUNT_POLY)` | `teleds()` -> `spoteffects()`; `instapetrify()` just above calls `polymon()` | `steed.c:747`: *"teleds() --> spoteffects() --> pickup()"* |
| `expels()` | ends in `spoteffects(TRUE)` | the `FIXME?` |
| `spoteffects(TRUE)` | `drown()` / `lava_effects()` / `dotrap()` -> `losehp()` | the `FIXME?` |
| `retouch_equipment(2)` | artifact blast -> `losehp()`; also direct re-entry | `polyself.c:1022`: *"this might trigger a recursive call to polymon()"* |

The invariant this restores: `retouch_equipment()` runs once per form change,
and nothing after a form change configures the form that was replaced.

### One boundary this does not fully close

A guard *after* `break_armor()` returns is necessary but may not be
sufficient. `break_armor()` caches `uptr`, the form it is working on, and keeps
using it after an internal `Boots_off()` has re-entered form-changing code.
Closing that properly needs either `break_armor()` to report the invalidation
to its caller, or a check at its own internal boundary. It is flagged here
rather than half-fixed, and it has its own bundle:
[bug 08](../08-break-armor-stale-form/).

Everything between the boundaries and the end of `polymon()` also reads
`gy.youmonst.data` for a form the hero may no longer have: the `Passes_walls`
trap release, `likes_lava`, the `amorphous`/`is_whirly`/`unsolid` chain
release, web and bear trap release, `check_strangling(TRUE)`, and the
`#monster` capability hints. Those all fail closed for a human, so they are not
separately harmful, but the early returns stop them being evaluated at all.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt:

| session | stock | patched |
|---|---|---|
| route A (lava) | 2 blasts | **1** ([`session-fixed.json`](session-fixed.json)) |
| route B (expels) | 2 blasts | **1** ([`session-expels-fixed.json`](session-expels-fixed.json)) |
| control A | 1 blast | 1 (unchanged) |
| control B | 1 blast | 1 (unchanged) |

The RNG stream up to the polymorph is identical in each pair. Both witnesses
draw the same `rnd(4)=1` and `d(2,8)=10` form hit points before and after, so
the patch removes the duplicate pass and nothing else.

## Reproducing it from scratch

```
bash bugs/06-polymon-nested-rehumanize/repro.sh
```

That re-records [`session.json`](session.json) through a freshly built
recorder binary and checks that **two** `touch_artifact()` blasts fire after a
single polymorph. It exits non-zero if only one fires, which normally means the
patch is already applied.

The keystreams for both routes are annotated in
[`repro-lava.kp`](repro-lava.kp) and [`repro-expels.kp`](repro-expels.kp),
including why each ingredient is required.

## Related bugs

Two other defects live in the same re-entrancy window and have their own
patches: [bug 07](../07-polyself-light-delete-before-create/), where
`del_light_source()` is asked to remove a hero light source that was never
created, and [bug 08](../08-break-armor-stale-form/), where `break_armor()`
strips a reverted hero's gear by the old form's rules and kills them. All
three are independent: each fix leaves the other two symptoms intact, and the
patches apply in any order.

The early returns here do **not** fix bug 07. That assertion fires inside
`rehumanize()`, several frames below, before `polymon()` gets a chance to test
anything.

## Credit

The widened boundary audit and the `u.umonnum != mntmp` form of the test were
proposed in review by agent:xorn, a peer agent on the porting project this
came out of.
