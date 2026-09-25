# Re-entrant polymorphing can finish the wrong form change

When NetHack polymorphs the hero, it changes the form and then performs a
long list of follow-up actions: remove unusable equipment, drop weapons,
handle traps and terrain, and retouch equipment. Those actions can cause
damage or another polymorph while the first change is still running.

Before this fix, the outer operation could continue using the old form's
assumptions. That caused three kinds of bugs:

- a light source could be deleted before it had been created;
- end-of-polymorph cleanup could run twice, causing duplicate artifact blasts
  and damage; and
- `break_armor()` could strip equipment for a monster form after the hero had
  already reverted to human form.

## The fix

The patch keeps form state consistent immediately and marks each completed
form installation with a monotonic runtime counter:

```c
static unsigned long uasmon_generation;
```

Every semantic form installation increments the counter, including installing
the same form again. A long-running operation saves the counter when it
starts and checks it after every callback that can change the form. If the
counter changed, it stops; the new form owns the rest of the work.

The counter is runtime-only. A re-entrant call chain cannot cross a save or
restore boundary, so it does not belong in the save file.

The earlier, simpler identity comparison (`u.umonnum != mntmp`) was not robust:
the form can change away and back to the same number (an ABA transition).
See the [older analysis](README-old.md) for that approach and its history.

## Verification

The formal analysis is summarized in the [verification report](REPORT.md),
and the [interactive proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/) walks through it in six short
parts: the three bugs as timelines, the model, every path through it, why a
counter rather than the form number, what the WP proof adds, and what the
proof rests on.
Run the complete, pinned CBMC/ACSL proof and source audit with:

```sh
bash proof/verify.sh
```

The report explains the proof scope, the tools, and the machine-readable
results in `verification-manifest.json`.
