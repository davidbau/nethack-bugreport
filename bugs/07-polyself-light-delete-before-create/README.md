# `polyself.c`: the hero's light source is installed by the wrong function, too late

**Component:** `src/polyself.c` — `polyself()` `made_change:` (the only creator,
line 728), `rehumanize()` (line 1393), `polymon()`, `polyman()`; `src/timeout.c`
line 488
**Severity:** LOW / `impossible()`. Not a crash, but it trips the DevTeam's own
assertion and prints "Program in disorder!" and "Please report these messages to
devteam@nethack.org", so players do report it.

## Symptom

```
You turn into a yellow light!  You can no longer hold your shield!
You find you must drop your spear!
You are blasted by the gray stone named the Heart of Ahriman's power!
del_light_source: not found type=2, id=0x99dd90
Program in disorder!  (Saving and reloading may fix this problem.)
Please report these messages to devteam@nethack.org.
You return to human form!  You can see again.
```

`type=2` is `LS_MONSTER`; the id is the hero-as-monster.

## Root cause: light ownership is split from form installation

The hero's form is installed by `set_uasmon()`. The hero's `LS_MONSTER` light
source is installed somewhere else entirely — `polyself.c:728`, in the
`made_change:` block, which runs only **after** `polymon()` has returned:

```c
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

Between `set_uasmon()` (`polyself.c:815`) and that block, `polymon()` does a
great deal of work that can re-enter form-changing code — `break_armor()`,
`drop_weapon()`, `expels()`, `spoteffects()`, `retouch_equipment(2)` — any of
which can inflict damage that takes `u.mh` below 1, at which point `losehp()`
(`hack.c:4310`) calls `rehumanize()`. And `rehumanize()` deletes on the basis of
the **current form**, with no check that a source exists:

```c
/* polyself.c:1393-1394 */
    if (emits_light(gy.youmonst.data))
        del_light_source(LS_MONSTER, monst_to_any(&gy.youmonst));
```

So in that window the hero *is* a light-emitting monster and has *no* light
source. `rehumanize()` asks for the delete anyway and `del_light_source()`
reports "not found".

The invariant that is false, stated once:

> **being in a light-emitting form does not imply that a light source exists.**

### Three consequences of the same split, only one of which is the reported bug

1. **The reported `impossible()`** — delete before create, as above.

2. **A second `impossible()` by the opposite route.** If the hero was *already*
   in a light-emitting form, `old_light` (captured at `polyself.c:497`) is 1. A
   nested `rehumanize()` deletes the source correctly, and `made_change:` then
   deletes it a **second** time.

3. **A leak that `made_change:` can never reach.** `polymon()` has ~20 callers
   outside `polyself.c` (stone-golem petrification from `dokick.c`, `eat.c`,
   `trap.c`, `uhitm.c`, …; `polymon(PM_QUEEN_BEE)`; `polymon(PM_FLESH_GOLEM)`;
   `were.c:209 polymon(u.ulycn)`; `timeout.c:493 polymon(PM_GREEN_SLIME)`).
   None of them runs `made_change:`. A hero who is a fire vortex when
   lycanthropy triggers keeps the old source forever: `were.c` has no
   light-source handling, and because a werewolf does not `emits_light()`,
   `rehumanize()` will not delete it later either.

`timeout.c:488-489` is a hand-placed `del_light_source()` immediately before its
direct `polymon()` call, and `polyself.c:580-582` is a hand-placed
`old_light = 0;` for the one branch where `rehumanize()` is called visibly:

```c
                rehumanize();
                old_light = 0; /* rehumanize() extinguishes u-as-mon light */
                goto made_change;
```

Two sites patched by hand for the same underlying split is the tell.

## Minimal reproducer

[`repro.kp`](repro.kp) — 130 keys, wizard mode. Recorded C output in
[`session-buggy.json`](session-buggy.json); the same keys against the patched
binary are in [`session-fixed.json`](session-fixed.json).

1. Start a **neutral Valkyrie** in wizard mode (`OPTIONS=playmode:debug`).
2. `#levelchange` to 20 — enough hit points to survive one `d(4,10)` blast.
3. Wish **The Heart of Ahriman**: a quest artifact of the wrong role
   (Barbarian) but the right alignment, so `badclass` is true, `badalign` is
   false, `touch_artifact()` blasts unconditionally and `retouch_object()` still
   returns 1 so the hero keeps it. Its `cspfx` (`SPFX_STLTH`) makes
   `carryeffect` true, so `untouchable()` tests it even though a yellow light
   can wear nothing — and unlike a wielded artifact it is not dropped by
   `drop_weapon(1)`.
4. Wish a **ring of polymorph control** (put it on) and a **wand of polymorph**.
5. Zap the wand at yourself and choose **yellow light** — level 3, so
   `u.mhmax = d(3,8)`, and `emits_light()` is non-zero.

`polymon()`'s own `retouch_equipment(2)` blasts for `d(4,10)`, taking the yellow
light's `u.mh` below 1; `rehumanize()` runs inside that call and asks to delete
a source `polyself()` has not created yet.

Any light-emitting form works; yellow light is the frailest, which makes the
blast reliably lethal to the form.

(The bug was originally found in a 13396-RNG-call NAO game; this 130-key
session reaches the same line.)

## Proposed fix: make form installation own the light transition

[`proposed-fix.patch`](proposed-fix.patch). One helper, called at every place
that installs a form, and the scattered bookkeeping removed.

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

- `polymon()`: capture `emits_light()` immediately before `u.umonnum = mntmp`,
  call the helper immediately after `set_uasmon()`.
- `polyman()`: same around its own `set_uasmon()`. This covers `newman()` and
  `rehumanize()`, which both go through it.
- Remove `polyself()`'s `made_change:` block and its `old_light` / `new_light`
  locals; the two `goto made_change` exits become plain `return`s.
- Remove the now-duplicated pre-deletes in `rehumanize()` (`polyself.c:1393`)
  and `slime_dialogue()` (`timeout.c:488`), and the `old_light = 0` hand-patch
  at `polyself.c:581`.

The invariant this establishes, true at every observable point:

> once `gy.youmonst.data` names a light-emitting form its `LS_MONSTER` source
> already exists; once a non-emitting form is installed the old source is
> already gone.

That also fixes consequence 3 above: the ~20 direct `polymon()` callers get
correct light handling for free, which no amount of strengthening
`made_change:` could achieve.

### Note on radius

`emits_light()` (`mondata.h:178`) returns only 0 or 1 — both of its branches
yield 1 — so there is no "emitting form of a different radius" case to worry
about; the `== 1 ? ++` normalisation to 2 is the only radius arithmetic and it
is preserved verbatim.

### Behaviour change, deliberate

The light now appears at `set_uasmon()` rather than after `polymon()` returns.
Previously the hero was a glowing monster who emitted no light for the duration
of `polymon()` — including across any `spoteffects()` vision recalculation
inside it. This is the intended correction, not a side effect.

## Verification

Applied to the pinned upstream tree (`16ff59115`) and rebuilt:

| | unpatched | patched |
|---|---|---|
| `del_light_source: not found` + "Program in disorder!" | present | **gone** |
| everything else in the 130-key session | — | identical |

[`session-transition-matrix-fixed.json`](session-transition-matrix-fixed.json)
walks a controlled-polymorph chain against the patched binary — human -> fire
vortex -> `newman()` -> kobold -> fire vortex -> `newman()` -> `newman()` ->
gnome lady — exercising create, delete-on-revert, and three `newman()` reverts
**from an emitting form** (the case that a naive `if (!Upolyd) old_light = 0;`
in `made_change:` would have broken, since `newman()` reverts through
`polyman()` without removing the source). No `impossible()` at any step.

## Credit

The form-installation-boundary structure was proposed in review by agent:xorn,
a peer agent on the porting project this came out of, who identified that a
presence query at the delayed caller preserves the split ownership that causes
the bug, and that direct `polymon()` callers cannot be fixed from `polyself()`
at all.

## Reproducing

```
bash bugs/07-polyself-light-delete-before-create/repro.sh
```

Re-records `session.json` through a freshly built NetHack recorder binary and
asserts that `del_light_source: not found` appears on screen. It exits non-zero
if the message is absent — i.e. if the patch is already applied.

## Related

`polymon()` continuing to run after a nested form change is a *separate* defect
with a separate patch — see [bug 06](../06-polymon-nested-rehumanize/). Neither
fix repairs the other, and the patches apply cleanly in either order.
