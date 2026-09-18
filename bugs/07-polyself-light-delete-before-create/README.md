# Polymorphing into a glowing form can print "Program in disorder!"

If you polymorph into a form that gives off light (a yellow light, a fire
vortex, a flaming sphere) and something destroys that form before the
polymorph has finished, the game prints an internal error and asks you to
mail the DevTeam:

```
You turn into a yellow light!  You can no longer hold your shield!
You find you must drop your spear!
You are blasted by the gray stone named the Heart of Ahriman's power!
del_light_source: not found type=2, id=0x99dd90
Program in disorder!  (Saving and reloading may fix this problem.)
Please report these messages to devteam@nethack.org.
You return to human form!  You can see again.
```

Nothing is corrupted and play continues normally. The cost to a player is
three extra `--More--` prompts and a message telling them to file a bug, which
is why this one gets reported. Under the DevTeam's own fuzzer it is worse than
that: `impossible()` escalates to `panic()` when
`iflags.debug_fuzzer == fuzzer_impossible_panic`, so a fuzzing run stops here.

The cause is that the hero's light source is created by the wrong function, one
level too far up the call stack. Between the moment the new form is installed
and the moment its light source is registered, the hero is a glowing monster
with no light source. Anything that reverts the polymorph inside that window
asks to delete a light source that does not exist yet.

The same split leaks a light source permanently on a different path, and can
also produce the mirror-image error (a double delete). Both are described
under "Three symptoms, one cause" below.

|  |  |
|---|---|
| Affects | NetHack 5.0 (the `NetHack-3.7` branch), `src/polyself.c` |
| Severity | Low. `impossible()`, no state corruption; a hard stop under the fuzzer |
| Upstream status | still present at the `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0) (checked 2026-09-18): `made_change:` is still the only creator and `rehumanize()` still deletes unconditionally. No upstream fix. |
| Recorded against | `NetHack/NetHack@16ff59115` |

## Watch it happen

Step through the recorded session in the browser; no build required.

- [**Buggy** (stock 5.0), jump to the error](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session.json#step=127)
- [**Fixed** (with `proposed-fix.patch`), same step](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session-fixed.json#step=127)

Both runs use the same seed and the same keystrokes. Step 126 is identical in
each: the hero has become a yellow light and has just been blasted by the
artifact they are carrying. At step 127 the stock build prints
`del_light_source: not found`, and the patched build goes straight to
`You return to human form!`. Use the scrubber or the arrow keys to walk back
through the polymorph.

If you run the session yourself, expect a different number after `id=`. The
pointer is the address of the `gy.youmonst` global, and the recorder is built
as a position-independent executable, so the address moves on every run.
`0x99dd90` is just what it was on the machine that recorded this.

There is also a [static side-by-side
view](https://davidbau.github.io/nethack-bugreport/bugs/07-polyself-light-delete-before-create/visualization.html)
of the same frames, and a third recording,
[`session-transition-matrix-fixed.json`](session-transition-matrix-fixed.json)
([replay](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session-transition-matrix-fixed.json#step=115)),
which walks a patched build through every combination of glowing and
non-glowing form change to show the fix does not disturb the ordinary cases.

## Reproducing it from scratch

```
bash bugs/07-polyself-light-delete-before-create/repro.sh
```

That re-records [`session.json`](session.json) through a freshly built
recorder binary and checks that `del_light_source: not found` appears. It
exits non-zero if the message is gone, which normally means the bug has been
fixed upstream.

To set it up by hand, in wizard mode: 130 keys, annotated in
[`repro.kp`](repro.kp).

1. Start a **neutral Valkyrie** with `OPTIONS=playmode:debug`.
2. `#levelchange` to 20, so the hero has enough hit points to survive one
   `d(4,10)` artifact blast as a human.
3. Wish for **The Heart of Ahriman** and carry it. It is a quest artifact of
   the wrong role (Barbarian) but the right alignment, so `touch_artifact()`
   blasts every time it is touch-tested while `retouch_object()` still returns
   1, meaning the hero keeps it. Carrying rather than wielding matters twice:
   its `SPFX_STLTH` makes `carryeffect` true, so `untouchable()` tests it even
   though a yellow light can wear nothing, and a carried artifact is not
   dropped by `drop_weapon(1)`.
4. Wish for a **ring of polymorph control** (put it on) and a **wand of
   polymorph**.
5. Zap the wand at yourself and choose **yellow light**. It is a level 3 form,
   so `u.mhmax = d(3,8)`, and `emits_light()` is non-zero.

`polymon()`'s own `retouch_equipment(2)` blasts the hero for `d(4,10)`, which
takes the yellow light's `u.mh` below 1. Any light-emitting form reproduces
this; the yellow light is simply the frailest, so the blast reliably kills the
form.

## What the code is doing

The hero's form is installed by `set_uasmon()`, called from `polymon()`. The
hero's `LS_MONSTER` light source is created somewhere else entirely, in
`polyself()`'s `made_change:` block, which only runs after `polymon()` has
returned:

```c
/* polyself.c:728 — the only place a hero light source is created */
 made_change:
    new_light = emits_light(gy.youmonst.data);
    if (old_light != new_light) {
        if (old_light)
            del_light_source(LS_MONSTER, monst_to_any(&gy.youmonst));
        ...
        new_light_source(u.ux, u.uy, new_light, LS_MONSTER,
                         monst_to_any(&gy.youmonst));
    }
```

Source: [`src/polyself.c:720-730`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L720-L730).

Between `set_uasmon()` at `polyself.c:815` and that block, `polymon()` does a
lot of work that can hurt the hero and re-enter form-changing code:
`break_armor()`, `drop_weapon()`, `expels()`, `spoteffects()`, and
`retouch_equipment(2)`. Any of those can take `u.mh` below 1, at which point
`losehp()` ([`hack.c:4267-4273`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4267-L4273)) calls `rehumanize()`.

`rehumanize()` decides whether to delete a light source by looking at the
form, and does not check that a source was ever registered:

```c
/* polyself.c:1393-1394 */
    if (emits_light(gy.youmonst.data))
        del_light_source(LS_MONSTER, monst_to_any(&gy.youmonst));
```

Source: [`src/polyself.c:1393-1394`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1393-L1394).

In the window above, the hero *is* a light-emitting monster and *has* no light
source, so the delete fails and `del_light_source()` reports it:

```c
/* light.c:135-136 */
        impossible("del_light_source: not found type=%d, id=%s", type,
                   fmt_ptr((genericptr_t) id->a_obj));
```

Source: [`src/light.c:135-136`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/light.c#L135-L136).

`type=2` is `LS_MONSTER`. The `id` is the hero as a monster;
`polyself.c`'s own file header notes that the light source code "assumes that
`gy.youmonst.m_id` always remains 1".

The assumption that fails, stated once:

> Being in a light-emitting form does not imply that a light source exists.

Nothing invalid is dereferenced here. `fmt_ptr()` (`alloc.c:125`) formats a
pointer *value* into a static buffer, and the pointer is
`monst_to_any(&gy.youmonst)`, a global.

## Three symptoms, one cause

Splitting light ownership away from form installation produces three distinct
problems, of which only the first is the reported one.

**1. Delete before create.** The `impossible()` above.

**2. A double delete, by the opposite route.** If the hero was *already* in a
light-emitting form, `old_light` (captured at `polyself.c:497`) is 1. A nested
`rehumanize()` correctly deletes the source, and then `made_change:` deletes it
a second time.

**3. A permanent leak that `made_change:` cannot reach.** `polymon()` has
around twenty callers outside `polyself.c`: stone-golem petrification from
`dokick.c`, `eat.c`, `trap.c` and `uhitm.c`; `polymon(PM_QUEEN_BEE)`;
`polymon(PM_FLESH_GOLEM)`; `were.c:209 polymon(u.ulycn)`;
`timeout.c:493 polymon(PM_GREEN_SLIME)`. None of them runs `made_change:`. A
hero who is a fire vortex when lycanthropy triggers keeps the old light source
forever, because `were.c` has no light-source handling and a werewolf does not
`emits_light()`, so `rehumanize()` will not delete it later either.

## Why the existing safeguards miss it

There are already two hand-placed workarounds for this same split, which is
the clearest sign that the ownership is in the wrong place.

`polyself.c:580-582` zeroes `old_light` for the one branch where
`rehumanize()` is called visibly:

```c
                rehumanize();
                old_light = 0; /* rehumanize() extinguishes u-as-mon light */
                goto made_change;
```

Source: [`src/polyself.c:578-582`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L578-L582).

And `timeout.c:488-489` deletes the light source by hand immediately before
its direct `polymon()` call. Each fixes one instance. Neither helps the paths
through `polymon()`'s interior.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch) moves the light transition to the
places that install a form, so the two can never be out of step. One helper,
called from every form-installation point:

```c
/* update the hero's light source to match the form set_uasmon() has just
   installed; 'old_light' is emits_light() for the form being replaced. */
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

The patch is also applied on a branch of a NetHack fork, so the change can be
read as a diff without downloading anything: [commit
d682576ae](https://github.com/davidbau/NetHack/commit/d682576ae5e1ddb702a14c663b546ffc797408fe)
(or as a [compare
view](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/07-polyself-light-delete-before-create)
against the pinned upstream commit). Branch:
`bugreport/07-polyself-light-delete-before-create`.

- `polymon()` captures `emits_light()` immediately before `u.umonnum = mntmp`
  and calls the helper immediately after `set_uasmon()`.
- `polyman()` does the same around its own `set_uasmon()`, which covers
  `newman()` and `rehumanize()` since both go through it.
- `polyself()`'s `made_change:` block and its `old_light` / `new_light` locals
  are removed, and the two `goto made_change` exits become plain returns.
- The now-redundant deletes in `rehumanize()` (`polyself.c:1393`) and
  `slime_dialogue()` (`timeout.c:488`) are removed, along with the
  `old_light = 0` workaround at `polyself.c:581`.

This establishes an invariant that holds at every observable point:

> Once `gy.youmonst.data` names a light-emitting form, its `LS_MONSTER` source
> already exists. Once a non-emitting form is installed, the old source is
> already gone.

It also fixes symptom 3 for free: the twenty-odd direct `polymon()` callers get
correct light handling without any of them changing, which no amount of
strengthening `made_change:` could achieve.

### A note on the radius

`emits_light()` (`mondata.h:178`) returns only 0 or 1, since both of its
branches yield 1, so there is no "emitting form of a different radius" case to
handle. The `== 1 ? ++` normalisation to 2 is the only radius arithmetic and
the patch keeps it verbatim.

### A deliberate behaviour change

The light now appears at `set_uasmon()` rather than after `polymon()` returns.
Previously a hero who had just become a glowing monster emitted no light for
the duration of `polymon()`'s remaining work, so anything in there that
consults the light map saw the old state. After the patch it sees the new form's
light, which is what the form implies.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt:

| | stock | patched |
|---|---|---|
| `del_light_source: not found` | printed | **not printed** |
| `Program in disorder!` + devteam line | printed | **not printed** |
| everything else in the 130-key session | — | identical |

The RNG stream up to the polymorph is identical in both runs, so the patch
removes the two diagnostic lines and changes nothing else. The
transition-matrix recording covers the remaining combinations of glowing and
non-glowing forms on the patched build.

## Related bugs

Two other defects live in the same re-entrancy window and have their own
patches:
[bug 06](../06-polymon-nested-rehumanize/) (`polymon()` continuing past a
nested `rehumanize()`, so equipment is re-touched twice) and
[bug 08](../08-break-armor-stale-form/) (`break_armor()` stripping a reverted
hero's gear by the old form's rules, which kills them). All three are
independent: each fix leaves the other two symptoms intact, and the patches
apply in any order.

Bug 06's early returns do **not** fix this one. The assertion here fires
inside `rehumanize()`, several frames below, before `polymon()` gets a chance
to test anything.

## Credit

The form-installation-boundary structure was proposed in review by agent:xorn,
a peer agent on the porting project this came out of, who identified that a
presence query at the delayed caller preserves the split ownership that causes
the bug, and that direct `polymon()` callers cannot be fixed from `polyself()`
at all.
