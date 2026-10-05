**Title:** Polymorphing into a glowing form can print "Program in disorder!" (`del_light_source: not found`)

**Version:** `NetHack-5.0` tip [`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0)
(checked 2026-09-18; `made_change:` is still the only creator and
`rehumanize()` still deletes unconditionally). Recorded against
`NetHack/NetHack@16ff59115`; line numbers below are against that commit.

### Symptom

If a light-emitting form (yellow light, fire vortex, flaming sphere) is
destroyed before the polymorph finishes:

```
You turn into a yellow light!  You can no longer hold your shield!
You find you must drop your spear!
You are blasted by the gray stone named the Heart of Ahriman's power!
del_light_source: not found type=2, id=0x99dd90
Program in disorder!  (Saving and reloading may fix this problem.)
Please report these messages to devteam@nethack.org.
You return to human form!  You can see again.
```

Play continues and nothing is corrupted; under `fuzzer_impossible_panic` it
panics. `id=` is `&gy.youmonst` and varies per run (PIE build).

[Buggy](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session.json#step=127)
/ [fixed](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session-fixed.json#step=127)
at step 127 (identical through 126);
[static side-by-side](https://davidbau.github.io/nethack-bugreport/bugs/07-polyself-light-delete-before-create/visualization.html).

### Cause

`polymon()` installs the form with `set_uasmon()` (`polyself.c:815`), but the
hero's `LS_MONSTER` light source is created only in `polyself()`'s
`made_change:` block
([`720-730`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L720-L730)),
after `polymon()` returns. In between, `break_armor()`, `drop_weapon()`,
`expels()`, `spoteffects()` and `retouch_equipment(2)` can drive `u.mh` below 1,
and `losehp()` ([`hack.c:4267-4273`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4267-L4273))
calls `rehumanize()`, which deletes by form alone
([`1393-1394`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L1393-L1394)):

```c
    if (emits_light(gy.youmonst.data))
        del_light_source(LS_MONSTER, monst_to_any(&gy.youmonst));
```

No source exists yet, so [`light.c:135-136`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/light.c#L135-L136)
calls `impossible()`.

The same split causes two more faults. If the old form already glowed
(`old_light` = 1, line 497), a nested `rehumanize()` deletes the source and
`made_change:` deletes it again. And the ~20 direct `polymon()` callers outside
`polyself.c` (stone-golem petrification, `were.c:209`, `timeout.c:493`, ...)
never run `made_change:`, so a fire vortex hit by lycanthropy keeps its light
source forever. The existing workarounds, `old_light = 0` at
[`580-582`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/polyself.c#L578-L582)
and the manual delete at `timeout.c:488-489`, each cover one path.

### Fix

[`proposed-fix.patch`](proposed-fix.patch) moves the light transition to
where the form is installed. A helper `uasmon_light(old_light)` holds the old
`made_change:` logic; `polymon()` and `polyman()` (so `newman()` and
`rehumanize()`) call it right after `set_uasmon()`:

```diff
+    old_light = emits_light(gy.youmonst.data);
     u.umonnum = mntmp;
     set_uasmon();
+    uasmon_light(old_light);
```

`made_change:`, its locals, the `rehumanize()` and `slime_dialogue()` deletes,
and the `old_light = 0` workaround are removed; the `goto made_change` exits
become returns. The light now appears at `set_uasmon()`, and the direct
callers are covered.
Fork: [commit 9a5fcf78e](https://github.com/davidbau/NetHack/commit/9a5fcf78e91d292faee9295e4a4e6424efec6cc7),
[compare](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/07-polyself-light-delete-before-create),
branch `bugreport/07-polyself-light-delete-before-create`.

With the patch the two diagnostic lines are gone and the rest of the session is
identical. [`session-transition-matrix-fixed.json`](session-transition-matrix-fixed.json)
([replay](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/07-polyself-light-delete-before-create/session-transition-matrix-fixed.json#step=115))
runs the patched build through every glowing/non-glowing form change.

### Repro

`bash bugs/07-polyself-light-delete-before-create/repro.sh` re-records
[`session.json`](session.json) with a freshly built recorder; if
`del_light_source: not found` appears it prints `BUG CONFIRMED` and exits 0,
otherwise exits 1. By hand (130 keys, [`repro.kp`](repro.kp)): neutral
Valkyrie, `playmode:debug`, `#levelchange` 20; wish for and carry The Heart of
Ahriman (wrong role, right alignment: blasts but is kept; carried, its
`SPFX_STLTH` makes it touch-tested); put on a ring of polymorph control; zap a
wand of polymorph at yourself and choose yellow light. `polymon()`'s
`retouch_equipment(2)` blast (`d(4,10)`) kills the `d(3,8)` form.

### Status

Reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682)
with [PR #1681](https://github.com/NetHack/NetHack/pull/1681), together with
[bug 06](../06-polymon-nested-rehumanize/) and
[bug 08](../08-break-armor-stale-form/). The three patches are independent and
apply in any order; bug 06's early returns do not fix this one, since it fires
inside `rehumanize()`. The shared rule and the unified fix are in
[bug 10](../10-polyself-reentrant-form-changes/), with a
[proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/)
whose [first part](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/#window)
draws this bug as a timeline.
