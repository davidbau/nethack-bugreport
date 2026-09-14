# `break_armor()` keeps stripping gear by the old form's rules after the hero has reverted — and kills them

**Component:** `src/polyself.c` `break_armor()` (line 1157; the stale reads are
at 1260, 1282 and 1300)
**Severity:** MEDIUM / **fatal**. The hero's water walking boots are removed
while they are standing in lava, by a rule that belongs to a form they no longer
have. Death follows immediately.

## Symptom

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

See [`visualization.html`](visualization.html) for the rendered before/after.

**No assertion fires.**  This is the most harmful of the three and the quietest:
it never calls `impossible()` — verified across the recorded session.  The hero
simply loses their gear and dies.  Of the three defects in this re-entrancy
window, only [bug 07](../07-polyself-light-delete-before-create/) announces
itself, and it is the least harmful of them.

## Root cause

`break_armor()` caches the form once, at entry:

```c
break_armor(void)
{
    struct obj *otmp;
    struct permonst *uptr = gy.youmonst.data;
```

and then asks `uptr` — not the hero's *current* form — what to strip:
`breakarm(uptr)`, `sliparm(uptr)`, `nohands(uptr)`, `verysmall(uptr)`,
`slithy(uptr)`, `uptr->mlet == S_CENTAUR`, `is_whirly(uptr)`, `has_head(uptr)`.

In between, its own gloves block calls `drop_weapon(0)`:

```c
    if (nohands(uptr) || verysmall(uptr)) {
        if ((otmp = uarmg) != 0) {
            ...
            You("drop your gloves%s!", uwep ? " and weapon" : "");
            drop_weapon(0);
```

If the wielded item is an artifact whose `#invoke`d levitation is holding the
hero up, releasing it ends that levitation — `finesse_ahriman()`'s own comment
says so: *"if we aren't levitating or this isn't an artifact which confers
levitation via #invoke then freeinv() won't toggle levitation"*. So
`freeinv()` -> `float_down()` puts the hero on whatever is below. If that is
lava and the water walking boots are **still worn** (they come off in the
*next* block), `lava_effects()` takes its survivable branch:

```c
    usurvive = Fire_resistance || (Wwalking && dmg < u.uhp);
    ...
    if (Wwalking) { pline_The("%s here burns you!", hliquid("lava"));
                    if (usurvive) losehp(dmg, lava_killer, KILLED_BY);
```

and `losehp()` (`hack.c:4310`) sees `Upolyd`, drives `u.mh` below 1 and calls
`rehumanize()`. The hero is human again — **inside** `break_armor()`.

`break_armor()` then resumes at its next sub-block with `uptr` still pointing at
the newt, and strips a human's shield (`nohands`) and a human's water walking
boots (`verysmall`). With the boots gone, the next `lava_effects()` no longer
qualifies for the `losehp()` branch and goes straight to
`u.uhp = -1; done(BURNING)`.

The hero does not die of lava damage — a level-30 Valkyrie absorbs `d(6,6)`
indefinitely. **They die because the game took their water walking boots off
while they were standing in lava.**

### Not a dangling pointer

`uptr` is stale but valid: `gy.youmonst.data` always points into the static
`mons[]` table, which is never freed. `nohands(uptr)` is well-defined; it simply
answers about the newt. This is a logic error, not memory unsafety.

### Why `Boots_off()` is not the re-entry point

`Boots_off()` (`do_wear.c:262`) does `setworn((struct obj *) 0, W_ARMF);`
**before** its switch, so by the time it calls `spoteffects(TRUE)` the boots are
already unworn. Without `Wwalking`, lava goes to `done(BURNING)` and water to
`drown()`, neither of which routes through `losehp()` — so no `rehumanize()`.
The revert has to arrive one block **earlier**, at `drop_weapon(0)`, while the
boots are still on. That ordering is the whole mechanism.

## Minimal reproducer

[`repro.kp`](repro.kp); recorded C output in
[`session.json`](session.json), and the same keys against the
patched binary in [`session-fixed.json`](session-fixed.json).

1. Neutral **Valkyrie**, wizard mode; `#levelchange` to 30 (enough hp that lava
   alone cannot kill, which is what makes the cause unambiguous).
2. Wish **fireproof water walking boots** (wear), **leather gloves** (wear),
   **The Heart of Ahriman** (wield), a **ring of polymorph control** (put on)
   and a **wand of polymorph**.
3. `#invoke` the Heart — the hero starts levitating.
4. Wish **lava** underfoot (safe while levitating).
5. Zap the wand at yourself and choose **newt** — level 0, so
   `u.mhmax = rnd(4)`, and `nohands`/`verysmall`, so the gloves block fires.

Fireproof boots matter: `lava_effects()` burns organic boots away *before*
testing `Wwalking`, which would skip the survivable branch and mask the bug
behind an ordinary death.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch). Stop when the form the function is
working on is no longer the hero's form:

```c
        if (gy.youmonst.data != uptr)
            return;
```

placed at three sub-block boundaries — after the gloves block (before the
shield), before the boots block, and before the eyewear block. Checking at
*boundaries* rather than mid-block matters: each sub-block pairs an `_off()`
with a `dropp()`, and bailing between them would leave an item half-removed.

**Invariant preserved:** `break_armor()` only ever strips gear the hero's
*current* form cannot wear.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt. Same keystream:

| | unpatched | patched |
|---|---|---|
| shield stripped from the reverted human | yes | **no** |
| water walking boots stripped from the reverted human | yes | **no** |
| `You fall into the molten lava!` / `You burn to a crisp...` | yes | **no** |
| outcome | dead | survives, taking ordinary `d(6,6)` lava damage |

Everything up to the revert is identical; the patch changes only what happens
after it.

Applying this patch alone does not disturb the other two bundles: the bug 06
witnesses still show their two `touch_artifact` blasts.

## Reproducing

```
bash bugs/08-break-armor-stale-form/repro.sh
```

Re-records `session.json` through a freshly built NetHack recorder binary and
asserts that the hero's shield and water walking boots are stripped after the
revert and that the run ends in death. It exits non-zero if they survive — i.e.
if the patch is already applied.

## Related

Two other defects live in the same re-entrancy window and have their own
patches: [bug 06](../06-polymon-nested-rehumanize/) (`polymon()` continuing
past a nested `rehumanize()`) and
[bug 07](../07-polyself-light-delete-before-create/)
(`del_light_source()` before the source exists). All three are independent —
each fix leaves the other two symptoms intact — and the patches apply in any
order.

Bug 06 adds a guard *after* `break_armor()` returns; this bundle closes the
interior, which that guard cannot reach.
