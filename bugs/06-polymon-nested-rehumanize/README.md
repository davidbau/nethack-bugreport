**Title:** One polymorph, two artifact blasts: `polymon()` keeps running after a nested `rehumanize()`

**Version:** `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0)
(checked 2026-09-18; both `FIXME?`s still there, no guard). Recorded against
`NetHack/NetHack@16ff59115`; line numbers below are against that commit.

### Symptom

A hero carrying an artifact that blasts them, whose polymorph is undone while
`polymon()` is still setting it up, is blasted twice for one polymorph, with a
fresh damage roll each time. Nothing reaches paniclog.

```
You turn into a kobold!  The lava here burns you!
You return to human form!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
You are blasted by the cubical amulet named the Eye of the Aethiopica's power!
```

In the recording this costs 5 hit points, then another 12, from one zap.
Two routes, one per `FIXME?`:

- Route A, lava: [buggy](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session.json#step=178)
  / [fixed](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-fixed.json#step=178).
  Step 177 is the first blast (100 to 95) in both; at 178 stock blasts again (95 to 83).
  [Static side-by-side](https://davidbau.github.io/nethack-bugreport/bugs/06-polymon-nested-rehumanize/visualization.html).
- Route B, land mine under an ochre jelly: [buggy](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels.json#step=247)
  / [fixed](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/06-polymon-nested-rehumanize/session-expels-fixed.json#step=246).
  First blast at step 245 (227 to 215), second (215 to 206) only in stock.

### Cause

`polymon()` ([`polyself.c:735-1071`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L735-L1071))
has one early exit (line 747). Two calls in it can revert the hero, and the
source flags both
([`929-932`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L929-L932),
[`972-974`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L972-L974)):

```c
            expels(u.ustuck, u.ustuck->data, expels_mesg);
            was_expelled = TRUE;
            /* FIXME? if expels() triggered rehumanize then we should
               return early */
...
        spoteffects(TRUE);
        /* FIXME? if spoteffects() triggered rehumanize then we should
           return early */
```

When `losehp()` reverts the form there, `rehumanize()` runs `encumber_msg()`
(1410) and `retouch_equipment(2)` (1415); back in `polymon()`, lines 1019 and
1021 run them again. `retouch_equipment()`'s `nesting` counter
([`artifact.c:2659-2660`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/artifact.c#L2659-L2660))
only catches nested calls; these are sequential.

Route A: a level-0 form has `rnd(4)` hit points (866); lava does `d(6,6)`, and
`lava_effects()` tests survival against `u.uhp` while `losehp()` decrements
`u.mh` ([`trap.c:6811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6811),
[`6872-6875`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6872-L6875)).
Route B: polymorphing into a rothe inside an ochre jelly fails the size test
([`917-920`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L917-L920));
`expels()` ends in `spoteffects(TRUE)`, which fires the mine left in place by
`gulpmu()` ([`mhitu.c:1310-1312`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mhitu.c#L1310-L1312)).
The Eye is wrong-role, right-alignment, so it blasts but stays worn.

Two controls (not shipped), where the revert comes from `polymon()`'s own
`retouch_equipment(2)` and so nests, blast once.

### Fix

[`proposed-fix.patch`](proposed-fix.patch) adds, after `break_armor()`/`drop_weapon(1)`,
`expels()`, `dismount_steed()`, `spoteffects(TRUE)` and `retouch_equipment(2)`:

```c
    if (u.umonnum != mntmp)
        return 1;
```

`u.umonnum != mntmp` rather than `!Upolyd` also catches a nested `polymon()`
(`instapetrify()`, `selftouch()`). Returning 1 keeps `polyself()`'s contract.
Fork: [commit 8076a1822](https://github.com/davidbau/NetHack/commit/8076a18220413d8bc6e0ff871c06fa420c8f5793),
[compare](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/06-polymon-nested-rehumanize),
branch `bugreport/06-polymon-nested-rehumanize`. A guard after `break_armor()`
cannot close its interior; that is [bug 08](../08-break-armor-stale-form/).

Patched, both routes blast once, the controls are unchanged, and the RNG
stream up to the polymorph is identical.

### Repro

`bash bugs/06-polymon-nested-rehumanize/repro.sh` re-records
[`session.json`](session.json) with a freshly built recorder and counts
`touch_artifact()` blasts after the polymorph: two prints `BUG CONFIRMED` and
exits 0; one (patch applied) exits 1. Keystreams:
[`repro-lava.kp`](repro-lava.kp), [`repro-expels.kp`](repro-expels.kp).

### Status

Reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682)
with [PR #1681](https://github.com/NetHack/NetHack/pull/1681), together with
[bug 07](../07-polyself-light-delete-before-create/) and
[bug 08](../08-break-armor-stale-form/). The three patches are independent and
apply in any order; this one does not fix bug 07. The shared rule and the
unified fix are in [bug 10](../10-polyself-reentrant-form-changes/), with a
[proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/)
whose [first part](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/#window)
draws this bug as a timeline.
