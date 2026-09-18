# The game takes your water walking boots off while you stand in lava, and you die

Polymorphing into a small form makes the game strip the gear that form cannot
wear. If the polymorph is undone in the middle of that stripping, the game
carries on removing items by the rules of the form the hero no longer has. A
human then loses their shield and their boots because a *newt* could not wear
them. When the boots are water walking boots and the hero is standing on lava,
that is fatal:

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

The hero in that recording is a level 30 Valkyrie with 169 hit points. Lava
does `d(6,6)` a turn, so lava alone could not kill them. They die because the
game removed their water walking boots while they were in it.

Nothing asserts. No `impossible()` fires and nothing reaches paniclog: the hero
just loses their gear and dies, which looks from the outside like an ordinary
death. Of the three defects in this part of `polyself.c` this is the most
harmful and the quietest.

|  |  |
|---|---|
| Affects | NetHack 5.0 (the `NetHack-3.7` branch), [`break_armor()`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1156-L1302) in `src/polyself.c` |
| Severity | **Medium, fatal.** Kills a hero who would otherwise survive |
| Upstream status | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0) (checked 2026-09-18): `break_armor()` still caches `uptr` and never re-checks it. No upstream fix. |
| Recorded against | `NetHack/NetHack@16ff59115` |

## Watch it happen

Step through the recorded session in the browser; no build required.

- [**Buggy** (stock 5.0), the fatal moment](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session.json#step=202)
- [**Fixed** (with `proposed-fix.patch`), end of the run](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/08-break-armor-stale-form/session-fixed.json#step=200)

Both runs use the same seed and the same keystrokes, and they agree through
step 199. Then:

| step | stock | patched |
|---|---|---|
| 200 | `You can no longer hold your shield!` | `The lava here burns you!` (still alive, 111 hit points) |
| 201 | shield burns up in the lava | (run ends) |
| 202 | `Your boots slide off your feet! You fall into the molten lava!` | |
| 203 | `You burn to a crisp...` | |
| 204 | `Die? [yn]` | |

Scrub back to step 196 to see the polymorph, and 197 to see the revert that
should have stopped the stripping.

There is also a [static side-by-side
view](https://davidbau.github.io/nethack-bugreport/bugs/08-break-armor-stale-form/visualization.html)
of the same frames.

## Reproducing it from scratch

```
bash bugs/08-break-armor-stale-form/repro.sh
```

That re-records [`session.json`](session.json) through a freshly built
recorder binary and checks that the shield and the water walking boots are
stripped after the revert and that the run ends in death. It exits non-zero if
the hero survives, which normally means the patch is already applied.

To set it up by hand, in wizard mode; the keystream is annotated in
[`repro.kp`](repro.kp).

1. Neutral **Valkyrie**, `OPTIONS=playmode:debug`, `#levelchange` to 30. The
   large hit point pool is what makes the cause unambiguous: lava damage alone
   cannot account for the death.
2. Wish for **fireproof water walking boots** (wear them), **leather gloves**
   (wear them), **The Heart of Ahriman** (wield it), a **ring of polymorph
   control** (put it on) and a **wand of polymorph**.
3. `#invoke` the Heart. The hero starts levitating.
4. Wish for **lava** underfoot, which is safe while levitating.
5. Zap the wand at yourself and choose **newt**. It is a level 0 form, so
   `u.mhmax = rnd(4)`, and it is both `nohands` and `verysmall`, so the gloves
   block in `break_armor()` fires.

The boots have to be fireproof. `lava_effects()` burns organic boots away
*before* it tests `Wwalking`, which would skip the survivable branch and hide
this behind an ordinary lava death.

## What the code is doing

`break_armor()` caches the hero's form once, at entry:

```c
break_armor(void)
{
    struct obj *otmp;
    struct permonst *uptr = gy.youmonst.data;
```

Source: [`src/polyself.c:1156-1160`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1156-L1160).

and from then on asks `uptr`, rather than the hero's *current* form, what to
strip: `breakarm(uptr)`, `sliparm(uptr)`, `nohands(uptr)`, `verysmall(uptr)`,
`slithy(uptr)`, `uptr->mlet == S_CENTAUR`, `is_whirly(uptr)`,
`has_head(uptr)`.

In between those questions, its own gloves block calls `drop_weapon(0)`:

```c
    if (nohands(uptr) || verysmall(uptr)) {
        if ((otmp = uarmg) != 0) {
            ...
            You("drop your gloves%s!", uwep ? " and weapon" : "");
            drop_weapon(0);
```

Source: [`src/polyself.c:1248-1254`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1248-L1254).

If the wielded item is an artifact whose `#invoke`d levitation is holding the
hero up, releasing it ends that levitation. `finesse_ahriman()`'s own comment
says as much: *"if we aren't levitating or this isn't an artifact which confers
levitation via #invoke then freeinv() won't toggle levitation"*. So
`freeinv()` calls `float_down()`, which puts the hero on whatever is below.

If that is lava and the water walking boots are **still worn** (they come off
in the *next* block), then `lava_effects()` takes its survivable branch:

```c
    usurvive = Fire_resistance || (Wwalking && dmg < u.uhp);
    ...
    if (Wwalking) { pline_The("%s here burns you!", hliquid("lava"));
                    if (usurvive) losehp(dmg, lava_killer, KILLED_BY);
```

Source: [`src/trap.c:6811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6811) and the `Wwalking` branch at
[`src/trap.c:6872-6875`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/trap.c#L6872-L6875).

`losehp()` ([`hack.c:4267-4273`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4267-L4273)) sees `Upolyd`, drives `u.mh` below 1 and calls
`rehumanize()`. The hero is human again, *inside* `break_armor()`.

`break_armor()` then resumes at its next sub-block with `uptr` still pointing
at the newt, and strips a human's shield (because a newt has `nohands`) and a
human's water walking boots (because a newt is `verysmall`). With the boots
gone, the next `lava_effects()` no longer qualifies for the `losehp()` branch
and goes straight to `u.uhp = -1; done(BURNING)`.

The gates that read the stale `uptr` after the revert are the boots test at
[`polyself.c:1273-1274`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1273-L1274), the `is_whirly` and
`verysmall` tests inside that block at [`1278-1282`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1278-L1282),
and the eyewear test at [`1291`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1291). The shield and helmet
sub-blocks run under a gate that was evaluated at `1248`, before the revert.

### This is not a dangling pointer

`uptr` is stale but valid. `gy.youmonst.data` always points into the static
`mons[]` table, which is never freed, so `nohands(uptr)` is well-defined. It
simply answers about the newt. This is a logic error, not memory unsafety.

### Why the re-entry point is `drop_weapon()`, not `Boots_off()`

`Boots_off()` (`do_wear.c:262`) does `setworn((struct obj *) 0, W_ARMF);`
*before* its switch, so by the time it calls `spoteffects(TRUE)` the boots are
already unworn. Without `Wwalking`, lava goes to `done(BURNING)` and water goes
to `drown()`, and neither routes through `losehp()`, so neither reaches
`rehumanize()`. The revert has to arrive one block earlier, at
`drop_weapon(0)`, while the boots are still on. That ordering is the whole
mechanism.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch) stops the function when the form it
is working on is no longer the hero's form:

```c
        if (gy.youmonst.data != uptr)
            return;
```

The patch is also applied on a branch of a NetHack fork, so the change can be
read as a diff without downloading anything: [commit
e38656987](https://github.com/davidbau/NetHack/commit/e38656987319c8e62f13c428ef3ae6837f7faa3a)
(or as a [compare
view](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/08-break-armor-stale-form)
against the pinned upstream commit). Branch:
`bugreport/08-break-armor-stale-form`.

placed at three sub-block boundaries: after the gloves block and before the
shield, before the boots block, and before the eyewear block.

Checking at boundaries rather than mid-block matters. Each sub-block pairs an
`_off()` call with a `dropp()`, and bailing out between those two would leave
an item half-removed.

The invariant this restores: `break_armor()` only ever strips gear that the
hero's *current* form cannot wear.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt. Same keystream:

| | stock | patched |
|---|---|---|
| shield stripped from the reverted human | yes | **no** |
| water walking boots stripped from the reverted human | yes | **no** |
| `You fall into the molten lava!` / `You burn to a crisp...` | yes | **no** |
| outcome | dead | survives, taking ordinary `d(6,6)` lava damage |

Everything up to the revert is identical; the patch changes only what happens
after it. Applying it alone does not disturb the other two bundles: the bug 06
witnesses still show their two `touch_artifact()` blasts.

## Related bugs

Two other defects live in the same re-entrancy window and have their own
patches: [bug 06](../06-polymon-nested-rehumanize/), where `polymon()`
continues past a nested `rehumanize()` and re-touches equipment twice, and
[bug 07](../07-polyself-light-delete-before-create/), where
`del_light_source()` is asked to remove a hero light source that was never
created. All three are independent: each fix leaves the other two symptoms
intact, and the patches apply in any order.

All three, and the single rule behind them, are explained together in
[bug 10](../10-polyself-reentrant-form-changes/), which also carries the
unified fix branch.

Bug 06 adds a guard *after* `break_armor()` returns. This bundle closes the
interior, which that guard cannot reach.
