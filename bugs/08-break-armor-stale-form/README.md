**Title:** `break_armor()` strips a reverted human's water walking boots by the old form's rules; the hero dies in lava

**Version:** `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0)
(checked 2026-09-18; `break_armor()` still caches `uptr` and never re-checks it).
Recorded against `NetHack/NetHack@16ff59115`; line numbers below are against
that commit.

### Symptom

A level 30 Valkyrie with 169 hit points, levitating over lava by the invoked
Heart of Ahriman, polymorphs into a newt:

```
You turn into a male newt!  You drop your gloves and weapon!
The lava here burns you!  You return to human form!
The lava here burns you!
You see a +0 pair of leather gloves hit lava and burn up!
You can no longer hold your shield!                       <- decided by the NEWT
You see a blessed +3 small shield hit lava and burn up!
Your boots slide off your feet!  You fall into the molten lava!
An item in your inventory has been destroyed.  You burn to a crisp...
Die? [yn] (n)
```

Lava does `d(6,6)`; the hero dies because the boots were removed. Nothing
reaches paniclog.

[Buggy](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session.json#step=202)
/ [fixed](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session-fixed.json#step=200):
identical through step 199 (polymorph at 196, revert at 197); at 200 stock
strips the shield, patched takes ordinary lava damage (111 hit points left).
[Static side-by-side](https://davidbau.github.io/nethack-bugreport/bugs/08-break-armor-stale-form/visualization.html).

### Cause

[`break_armor()`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1156-L1302)
caches the form at entry
([`polyself.c:1160`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1156-L1160)),
`struct permonst *uptr = gy.youmonst.data;`, and asks `uptr` what to strip.
Its gloves block calls `drop_weapon(0)`
([`1248-1254`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1248-L1254));
releasing the invoked Heart ends levitation (`freeinv()` -> `float_down()`).
With the boots still worn, `lava_effects()` takes the `Wwalking` branch
([`trap.c:6811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6811),
[`6872-6875`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6872-L6875))
and `losehp()` ([`hack.c:4267-4273`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4267-L4273))
calls `rehumanize()` inside `break_armor()`.

`break_armor()` then continues with `uptr` still the newt: the shield and
helmet sub-blocks under the gate evaluated at 1248, the boots test at
[`1273-1274`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1273-L1274),
the `is_whirly`/`verysmall` tests at
[`1278-1282`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1278-L1282),
and eyewear at [`1291`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1291).
Without boots, the next `lava_effects()` goes to `done(BURNING)`. (`uptr`
points into `mons[]`; it is stale, not dangling.)

The re-entry has to come at `drop_weapon(0)`: `Boots_off()` (`do_wear.c:262`)
unsets the boots before `spoteffects()`, so lava or water there goes to
`done(BURNING)`/`drown()`, not `losehp()`.

### Fix

[`proposed-fix.patch`](proposed-fix.patch) adds

```c
        if (gy.youmonst.data != uptr)
            return;
```

at three sub-block boundaries: after the gloves and before the shield, before
the boots block, and before the eyewear block. Checking only between
sub-blocks keeps each `_off()`/`dropp()` pair together.
Fork: [commit e38656987](https://github.com/davidbau/NetHack/commit/e38656987319c8e62f13c428ef3ae6837f7faa3a),
[compare](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/08-break-armor-stale-form),
branch `bugreport/08-break-armor-stale-form`.

With the patch the shield and boots are kept and the hero survives; everything
up to the revert is identical, and bug 06's witnesses still show two blasts.

### Repro

`bash bugs/08-break-armor-stale-form/repro.sh` re-records
[`session.json`](session.json) with a freshly built recorder; if the shield and
boots are stripped after the revert and the hero dies it prints `BUG CONFIRMED`
and exits 0, otherwise exits 1. By hand ([`repro.kp`](repro.kp)): neutral
Valkyrie, `playmode:debug`, `#levelchange` 30; wish for and wear fireproof
water walking boots (organic boots burn before the `Wwalking` test) and leather
gloves, wield The Heart of Ahriman, put on a ring of polymorph control, get a
wand of polymorph; `#invoke` the Heart; wish for lava underfoot; zap yourself
and choose newt (`rnd(4)` hit points, `nohands` and `verysmall`).

### Status

Reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682)
with [PR #1681](https://github.com/NetHack/NetHack/pull/1681), together with
[bug 06](../06-polymon-nested-rehumanize/) and
[bug 07](../07-polyself-light-delete-before-create/). The three patches are
independent and apply in any order; bug 06 guards after `break_armor()`
returns, this one closes its interior. The shared rule and the unified fix are
in [bug 10](../10-polyself-reentrant-form-changes/), with a
[proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/)
whose [first part](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/#window)
draws this bug as a timeline.
