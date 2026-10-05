**Title:** Re-entrant polymorphing can finish the wrong form change

**Version:** `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0),
checked 2026-09-18. Explanatory bundle for bugs
[06](../06-polymon-nested-rehumanize/),
[07](../07-polyself-light-delete-before-create/) and
[08](../08-break-armor-stale-form/).

### Symptom

After installing a new form, `polymon()` removes unusable equipment, drops
weapons, and handles traps, terrain and artifact retouching. Those steps can
cause damage or another polymorph while the first change is still running, and
the outer operation then continues with the old form's assumptions:

- a light source is deleted before it has been created
  ([bug 07](../07-polyself-light-delete-before-create/));
- end-of-polymorph cleanup runs twice, giving duplicate artifact blasts and
  damage ([bug 06](../06-polymon-nested-rehumanize/));
- `break_armor()` strips equipment for a monster form after the hero has
  already reverted to human form ([bug 08](../08-break-armor-stale-form/)).

### Cause

`polymon()` and `break_armor()` keep acting after a callback has installed
a different form. Comparing identity (`u.umonnum != mntmp`) does not detect
this: the form can change away and back to the same number (an ABA
transition). The [older analysis](README-old.md) covers that approach and its
history.

### Fix

[`proposed-fix.patch`](proposed-fix.patch) keeps form state consistent
immediately (the light source is updated in the same step as the form) and
marks each form installation with a monotonic runtime counter:

```c
static unsigned long uasmon_generation;
```

Every form installation increments it, including reinstalling the same form.
A long-running operation saves the counter when it starts and checks it after
every callback that can change the form; if it changed, the operation stops
and the new form owns the rest of the work. The counter is runtime-only: a
re-entrant call chain cannot cross a save or restore, so it is not saved.

### Verification

The [verification report](REPORT.md) summarizes the formal analysis. The
[interactive proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/)
walks through it in six short parts: the three bugs as timelines, the
invariant the patch keeps (a call acts for its form only while no form has
been installed since it started), the model, every path through it, the
invariant proved, and what the proof rests on.

Run the complete, pinned CBMC/ACSL proof and source audit with:

```sh
bash proof/verify.sh
```

The report explains the proof scope, the tools, and the machine-readable
results in `verification-manifest.json`. The per-bug repros and recorded
sessions are in bundles 06, 07 and 08.

### Status

Reported upstream as [#1682](https://github.com/NetHack/NetHack/issues/1682),
with [PR #1681](https://github.com/NetHack/NetHack/pull/1681), which covers
all three defects.
