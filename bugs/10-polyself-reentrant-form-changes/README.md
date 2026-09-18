# Polymorphing is not atomic, and the code after the form change assumes it is

Three separate defects in `src/polyself.c` come from one fact about the code:
changing the hero's form is a long sequence, not a single step, and something
in the middle of that sequence can change the form again.

`polymon()` installs the new form, and then spends several hundred lines
applying the consequences: breaking armour the new body cannot wear, dropping
the weapon it cannot hold, being expelled from whatever swallowed you, landing
on whatever is underfoot, re-touching every artifact you carry. Several of
those steps can hurt you. While you are polymorphed, damage goes to `u.mh`,
and when `u.mh` reaches zero the game reverts you to human, by calling
`rehumanize()` right there, from inside the sequence. Control then comes back
and the rest of the sequence runs to completion, still configuring the monster
you are no longer.

Three things go wrong in that window, and they look nothing alike from a
player's chair:

| | what you see | bundle |
|---|---|---|
| A light source is deleted that was never created | `del_light_source: not found`, `Program in disorder!`, a request to mail the DevTeam | [bug 07](../07-polyself-light-delete-before-create/) |
| Cleanup runs twice for one polymorph | one polymorph, **two** artifact blasts and two damage rolls | [bug 06](../06-polymon-nested-rehumanize/) |
| Decisions keep being made by the old form's rules | a **human** is stripped of their water walking boots because a *newt* could not wear them, while standing in lava; fatal | [bug 08](../08-break-armor-stale-form/) |

Each has its own bundle, its own recordings and its own patch. This one
explains them together, because they have a single shape and the three patches
are three applications of one rule.

|  |  |
|---|---|
| Affects | `src/polyself.c` (`polymon()`, `polyself()`, `break_armor()`), `src/timeout.c` |
| Severity | Bug 08 is **fatal**. Bug 07 trips an `impossible()` and is a hard stop under the DevTeam's fuzzer. Bug 06 is player-visible duplicate damage. |
| Upstream status | all three still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0), checked 2026-09-18 |
| Recorded against | `NetHack/NetHack@16ff59115` (NetHack 5.0.0 as released) |
| Unified fix | branch [`bugreport/10-polyself-reentrancy`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/10-polyself-reentrancy), three commits |

## The three scenarios

Every one of these is a recorded game you can step through in the browser, with
the same keystrokes replayed against a patched build alongside. No build
required.

### 1. The light source that was never created (bug 07)

Polymorph into a form that glows (a yellow light, a fire vortex) while
carrying a cross-aligned artifact. `polymon()`'s own `retouch_equipment(2)`
blasts you, the frail glowing form dies, and `rehumanize()` runs. It tries to
delete the light source for the form you currently have. But the light source
for a polymorphed hero is not created by `polymon()`; it is created by
`polyself()`, *after* `polymon()` returns. There is nothing to delete yet.

[**Buggy**](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session.json#step=127)
·
[**Fixed**, same step](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session-fixed.json#step=127)

### 2. The cleanup that runs twice (bug 06)

Polymorph into a level-0 form while standing on lava, or onto a land mine
while swallowed. The form dies inside `polymon()`, and `rehumanize()` does its
own end-of-form-change cleanup: `encumber_msg()` and `retouch_equipment(2)`.
Control returns to `polymon()`, which is about to do exactly those two things
itself. The artifact blasts you a second time, for a second roll of damage.

[**Buggy**, the second blast](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session.json#step=178)
·
[**Fixed**, same step](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-fixed.json#step=178)
·
[second route, buggy](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels.json#step=247)
·
[second route, fixed](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels-fixed.json#step=246)

### 3. The decisions made by the wrong form (bug 08)

Polymorph into a newt while levitating over lava on an `#invoke`d artifact.
`break_armor()` decides what to strip by asking the form it captured when it
started. Its gloves block drops your weapon, which ends the levitation, which
drops you in the lava, which kills the newt, which reverts you to human. The
function then carries on asking the *newt* what a human may wear, and takes
the water walking boots off a human standing in lava.

[**Buggy**, the fatal strip](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session.json#step=202)
·
[**Fixed**, hero survives](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session-fixed.json#step=200)

## The rule the code is missing

Stated once, in the form that covers all three:

> Every effect applied during a form change must be appropriate to the form the
> hero has **now**, not to the form the code was told to install.

The existing code is not wrong because it is re-entrant. Re-entrancy here is
unavoidable: dropping armour can put you in water, dropping an artifact can end
levitation, and being hurt while polymorphed reverts you. The code is wrong
because it decides once, at the top, and then acts on that decision after
something else has invalidated it.

Two obligations follow, one for each side of the boundary.

**If you change the form, leave the world consistent with it before you
return.** This is the ownership question, and it is bug 07. The light source is
part of what it means to be a glowing monster, so it belongs to the code that
installs the form, not to a caller several frames up who will get around to it
later. As long as it lives in the caller, there is a window in which "the form
glows" and "a light source exists" disagree, and anything that reverts the form
inside that window is looking at an inconsistent world.

**If you continue after a call that might have changed the form, check before
you act.** This is bugs 06 and 08. Both are the same mistake at different
scales: `polymon()` continues configuring a form that is gone, and
`break_armor()` continues stripping by a form that is gone.

Neither obligation is new to this file. The DevTeam has already written both
down in places: two `FIXME?` comments say `polymon()` "should return early" if
a nested revert happened, a hand-placed `old_light = 0` patches one instance of
the light-ownership problem, and `timeout.c` deletes the light source by hand
before its own `polymon()` call. Each of those is a local workaround for one
instance of a general rule. The fix below applies the rule.

## How the fix is built

Three commits on
[`bugreport/10-polyself-reentrancy`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/10-polyself-reentrancy),
branched from `16ff59115`. Each is also its own branch, and they cherry-pick
cleanly in any order, because they touch different lines and none depends on
another:

| commit | what it does | bundle |
|---|---|---|
| [`1aacf75f1`](https://github.com/davidbau/NetHack/commit/1aacf75f163477f989deb900d3567c3aa47c38b2) | five early returns in `polymon()` | 06 |
| [`e21c87732`](https://github.com/davidbau/NetHack/commit/e21c8773279d77160e29706c3bd4ef8ac4f5ada3) | move light ownership to form installation | 07 |
| [`2dc124672`](https://github.com/davidbau/NetHack/commit/2dc124672878074a8fbf2c2380e23509084df08d) | three re-checks inside `break_armor()` | 08 |

Combined: `src/polyself.c` +70/-27, `src/timeout.c` -2, no other file.
[`proposed-fix.patch`](proposed-fix.patch) is the whole thing as one diff.

### Part 1: give the light source to whoever installs the form

Before, the only place a hero light source was created was `polyself()`'s
`made_change:` block, which runs after `polymon()` has already returned
([`polyself.c:720-730`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L720-L730)).
The patch moves that transition into a helper and calls it from every place
that installs a form:

```c
/* update the hero's light source to match the form set_uasmon() has just
   installed; 'old_light' is emits_light() for the form being replaced.
   Every place which changes gy.youmonst.data calls this immediately, so
   that "the form emits light" and "a light source exists" can never
   disagree -- not even for the duration of a re-entrant callback. */
staticfn void
uasmon_light(int old_light)
{
    int new_light = emits_light(gy.youmonst.data);

    if (old_light != new_light) {
        if (old_light)
            del_light_source(LS_MONSTER, monst_to_any(&gy.youmonst));
        if (new_light == 1)
            ++new_light; /* otherwise it's undetectable */
        if (new_light)
            new_light_source(u.ux, u.uy, new_light, LS_MONSTER,
                             monst_to_any(&gy.youmonst));
    }
}
```

Fixed code: [`polyself.c:197-216`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L197-L216).

There are exactly two places that install a form, and each now captures the
old state immediately before and calls the helper immediately after:

- `polymon()`, around its `u.umonnum = mntmp; set_uasmon();`:
  [`polyself.c:824-827`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L824-L827)
- `polyman()`, around its own `set_uasmon()`:
  [`polyself.c:228-237`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L228-L237)

`polyman()` is the one to notice: `newman()` and `rehumanize()` both go through
it, so covering it covers every way back to human, including the nested
`rehumanize()` that caused the original `impossible()`.

Three things then become dead and are removed: `polyself()`'s `made_change:`
block, the `old_light = 0` workaround at `polyself.c:581`, and `timeout.c`'s
by-hand delete before `polymon(PM_GREEN_SLIME)`. `slimed_to_death()`'s comment,
which said `polymon()` "does not perform `polyself()`'s light source
bookkeeping", is updated, because now it does.

**Why this is correct.** The unsafe window existed because two facts were
maintained in two places at two times. After the patch they are maintained in
one place at one time: the helper runs in the same statement sequence as
`set_uasmon()`, with nothing in between that can be re-entered. Any observer,
including a `rehumanize()` called from deep inside `polymon()`, sees a world
where the form and its light source agree.

**What it fixes beyond the reported bug.** `polymon()` has around twenty
callers outside `polyself.c`: stone-golem petrification from `dokick.c`,
`eat.c`, `trap.c` and `uhitm.c`; `polymon(PM_QUEEN_BEE)`;
`were.c:209 polymon(u.ulycn)`; `timeout.c:493 polymon(PM_GREEN_SLIME)`. None of
them ran `made_change:`, so none of them ever managed the light source at all. A
fire vortex who caught lycanthropy kept its light source forever. Those callers
are now correct without any of them changing, which no amount of strengthening
`made_change:` could have achieved.

**The one deliberate behaviour change.** The light now appears at
`set_uasmon()` rather than after `polymon()` returns. Anything inside
`polymon()` that consults the light map now sees the new form's light instead
of the old state. That is the point: the map matches the body.

### Part 2: stop `polymon()` at each boundary that can change the form

`polymon()` had exactly one early exit, the "cannot become that" `return 0`
([`polyself.c:747`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L747)).
The patch adds five, each immediately after a call that can re-enter
form-changing code:

| after | can revert because | fixed code |
|---|---|---|
| `break_armor()` / `drop_weapon(1)` | `Boots_off()` reaches `spoteffects()`; dropping an `#invoke`d levitation artifact ends levitation | [`polyself.c:902-913`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L902-L913) |
| `expels()` | ends in `spoteffects(TRUE)` | [`polyself.c:953-957`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L953-L957) |
| `dismount_steed(DISMOUNT_POLY)` | `teleds()` reaches `spoteffects()`; `instapetrify()` just above calls `polymon()` directly | [`polyself.c:989-994`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L989-L994) |
| `spoteffects(TRUE)` | `drown()` / `lava_effects()` / `dotrap()` reach `losehp()` | [`polyself.c:1001-1003`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L1001-L1003) |
| `retouch_equipment(2)` | an artifact blast reaches `losehp()` | [`polyself.c:1052-1057`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L1052-L1057) |

Each is the same two lines:

```c
    if (u.umonnum != mntmp)
        return 1;
```

**Why the test is `u.umonnum != mntmp` and not `!Upolyd`.** A nested callback
can install a *different monster* form, not only revert to human:
`instapetrify()` and `selftouch()` both call `polymon()` directly, and the
source's own comment at the fifth boundary describes exactly that case: a hero
wielding a cockatrice corpse, hit by stone-to-flesh, becoming a flesh golem and
then being turned back into a stone golem. `!Upolyd` would miss it. Asking
"is the hero still the form I was asked to install?" catches both.

**Why the return value is 1.** `polymon()` returns 1 for "the polymorph
happened", and it did: the form was installed, and then something replaced it.
`polyself()`, the only caller that inspects the result, does
`(void) polymon(...)`, so the value matters only for the direct callers that
check it, and for them "a polymorph occurred" is the truthful answer.

**Why five and not the two the `FIXME?`s mark.** The `FIXME?`s mark `expels()`
and `spoteffects()`. The other three are the same hazard documented in the
comments of the functions being called: `dropp()` says *"Dropping worn armor
while polymorphing might put hero into water"*, `drop_weapon()` says *"if heart
of ahriman is wielded, we might be losing levitation by dropping it"*,
`steed.c:747` says *"teleds() --> spoteffects() --> pickup()"*, and
`polyself.c:1022` says *"this might trigger a recursive call to polymon()"*.
Fixing only the two annotated boundaries would leave three known paths open.

**What the early returns skip, and why that is safe.** Everything after a
boundary reads `gy.youmonst.data` for a form the hero may no longer have: the
`Passes_walls` trap release, `likes_lava`, the `amorphous`/`is_whirly`/`unsolid`
chain release, web and bear trap release, `check_strangling(TRUE)`, and the
`#monster` capability hints. All of those fail *closed* for a human (a human
is not `amorphous`, does not pass walls, has no breath weapon), so skipping
them loses nothing a human should have had. What the returns do prevent is the
duplicated `encumber_msg()` and `retouch_equipment(2)` that `rehumanize()` has
already performed, which is the reported bug.

### Part 3: re-check inside `break_armor()`

`break_armor()` is a special case of the same problem one level down. It
captures the form at entry
([`polyself.c:1160`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1160))
and then asks that captured `uptr` what to strip, block by block. Its own
gloves block calls `drop_weapon(0)`, which is one of the re-entrant calls above.
So a guard placed *after* `break_armor()` returns, which part 2 does, is
necessary but not sufficient: by then the damage is done inside.

The patch adds three re-checks, at sub-block boundaries:

```c
        if (gy.youmonst.data != uptr)
            return;
```

- before the shield block, immediately after the gloves block that can revert:
  [`polyself.c:1292-1300`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L1292-L1300)
- before the boots block:
  [`polyself.c:1315-1316`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L1315-L1316)
- before the eyewear block:
  [`polyself.c:1331-1337`](https://github.com/davidbau/NetHack/blob/2dc124672878074a8fbf2c2380e23509084df08d/src/polyself.c#L1331-L1337)

**Why the boundaries and not the tests.** The obvious alternative is to replace
every `nohands(uptr)` with `nohands(gy.youmonst.data)`. That is worse. Each
sub-block pairs an `_off()` call with a `dropp()`, and re-evaluating the form
mid-block could take an item off and then decline to drop it, leaving inventory
half-updated. Returning at a boundary leaves every item either fully worn or
fully removed.

**Why `return` rather than continuing with the new form.** The caller,
`polymon()`, is itself about to stop: part 2's first guard sits immediately
after `break_armor()` returns. And the hero is human again, so the correct
amount of further stripping is none: a human can wear all of it.

## Why you should believe the three fixes are right

Four things a reviewer can check independently.

**Each patch has a recorded before-and-after on the same keystream.** The links
in "The three scenarios" above are the same seed, the same datetime and the same
keys, replayed against an unpatched and a patched build. In each pair the runs
are identical up to the moment of the defect. The RNG stream is identical too:
bug 06's witnesses draw the same `rnd(4)=1` and `d(2,8)=10` form hit points on
both sides, so the patches remove the wrong behaviour without perturbing the
game.

**Each patch has a control.** Bug 06 ships two routes into the same defect
(`expels()` and `spoteffects()`) and two controls that differ by one ingredient
and blast only once, which separates "sequential call" from "nested call" and
shows the existing recursion guard in `retouch_equipment()` is not what is
broken. Bug 08's patched run still prints `The lava here burns you!` and takes
`d(6,6)`, proving the patched build reached the same lava rather than avoiding
the scenario.

**The three are independent.** Each fix leaves the other two symptoms intact,
and the three commits cherry-pick cleanly onto the pinned commit in any order.
Bug 06's early returns specifically do *not* fix bug 07: that assertion fires
inside `rehumanize()`, several frames below, before `polymon()` gets the chance
to test anything. If they were three views of one defect, one patch would have
silenced all three; it does not.

**Each guard sits where the source already says the hazard is.** Every one of
the five boundaries in part 2, and the entry point in part 3, is a call whose
own comments document that it can re-enter form-changing code. The patch adds no
new theory about what is dangerous; it acts on what the file already says.

## Not fixed here

Two things stay open deliberately.

`break_armor()` reports nothing to its caller about having been invalidated.
Part 3 stops it from doing further harm and part 2 stops `polymon()` afterwards,
so no path is left broken, but the cleaner shape would be for `break_armor()` to
return a "form changed under me" result rather than have both sides infer it.

The wider question of whether a form change should be a transaction at all,
with the consequences applied as a unit that either completes or unwinds, is a
much larger design change. These patches make the existing sequence honest
about its own re-entrancy instead.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction. The recordings, the root-cause analysis and the
patches are Claude Opus 5's; the widened boundary audit, the
`u.umonnum != mntmp` form of the test, and the form-installation-boundary
structure for the light source were proposed in review by Codex GPT-5.6.
