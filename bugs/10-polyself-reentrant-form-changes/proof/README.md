# Polymorph reentrancy proof

This directory is a verification-only companion to NetHack PR #1681. It does
not modify `nethack-c/upstream/`.

The pilot checks a deliberately narrow ownership property:

> If a nested callback installs another hero form, an interrupted `polymon()`
> or `break_armor()` invocation must not apply another effect owned by the
> superseded form generation.

It also checks that hero-form light bookkeeping is complete before any
reentrant boundary, cleanup is not repeated for one form generation, and an
equipment block is not begun using a cached form from an older generation.

## Run

Docker is the only host dependency:

```sh
bash bugs/10-polyself-reentrant-form-changes/proof/run-cbmc.sh
```

The script pins `diffblue/cbmc:6.10.0`.  It runs positive checks and negative
controls.  CBMC exits 0 for each expected proof and 10 for each expected
counterexample; any other outcome fails the script.

## Source mapping

The distilled model preserves the control boundaries relevant to PR #1681:

| model boundary | NetHack 5.0 operation |
|---|---|
| `POLY_BREAK_ARMOR` | `break_armor(); drop_weapon(1);` |
| `POLY_EXPELS` | `expels(...)` |
| `POLY_DISMOUNT` | `instapetrify(...)` / `dismount_steed(...)` |
| `POLY_SPOTEFFECTS` | `spoteffects(TRUE)` |
| `POLY_RETOUCH` | `retouch_equipment(2)` |
| `ARMOR_AFTER_GLOVES` | `drop_weapon(0); Gloves_off(); dropp(...)` |
| `ARMOR_BEFORE_BOOTS` | completed shield/helmet blocks |
| `ARMOR_BEFORE_EYEWEAR` | completed boots block |

`install_form()` models the patched adjacent sequence
`set_uasmon(); uasmon_light(old_light);`.  The negative control
`install_form_without_light_bookkeeping()` models the old split where
`polyself()` deferred the light transition until `made_change:`.

The model uses a ghost `form_epoch`.  It changes on every modeled form
installation, including installation of the same form.  This detects the ABA
case that a comparison of `u.umonnum` or `gy.youmonst.data` cannot detect by
itself.

## What is proved

Within this finite, loop-free abstraction, CBMC exhaustively checks every
nondeterministic callback outcome at each modeled boundary:

- immediate light bookkeeping preserves the form/light invariant;
- an epoch guard prevents stale effects under arbitrary nested changes;
- the PR's identity guards prevent stale effects if callbacks satisfy a
  no-same-form-reinstallation (no-ABA) contract;
- omitting any of the five `polymon()` guards or three `break_armor()` guards
  admits a concrete ordinary form-change counterexample;
- the old delayed light bookkeeping admits the delete-before-create state.

Frama-C/WP proves the invariant itself.  `polyself_acsl.c` opens with the
invariant in words and states its three facts as contracts:

- `install_form()`: the counter goes up by exactly one, and the light
  matches the new form;
- `callback()`: any number of installations, of any forms, in any order, each
  finished by its own installer (a loop with an invariant);
- `checkpoint()`: continue exactly when nothing was installed; a call that
  continues still `owns(g)`, and one that stops is `stale(g)`;
- `owned_effect()`: `requires owns(g)`, the invariant, checked by WP at every
  place the `polymon()` and `break_armor()` models act for their form;
- `cleanup_form()`: at most once per generation (bug 06).

WP checks every function against its own contract: **158/158** goals (108 by
Qed, 42 by Alt-Ergo, 8 trivially), with no property left assumed.
`run-wp.sh` then makes ten small edits that must each make WP fail: each of
the eight checkpoints has its answer ignored in turn (WP cannot prove the
next `owns(g)`, or after `spoteffects()` the cleanup-once precondition);
`install_form()` stops bumping the counter; and the identity guard loses its
"no callback reinstalls the owner's form" promise, leaving exactly its
`assert owns(g)` unproved.

(An earlier `run-wp.sh` passed `-wp-fct` with only the two top-level entry
points and reported 76/76; WP then assumed the contracts of the functions
they call, so the boundary lemma was never checked.)

There are no loops in the CBMC model, so no behavior is excluded by an
unwind bound.  `--unwinding-assertions` remains enabled to make that fact checked by
CBMC rather than assumed.

## What the proof rests on

The model is connected to NetHack by three premises, each checked by an audit
or by review rather than by the provers:

1. **Every form installation goes through `set_uasmon()`, and `set_uasmon()`
   bumps the counter.**  `audit-form-transitions.mjs` fails if a new write to
   `u.umonnum` or `gy.youmonst.data`, or a new `set_uasmon()` call, appears
   without review; `audit-patch.mjs` checks the bump is in `set_uasmon()`.
2. **Every bump inside the window belongs to an installer that finishes its
   own form's setup** (a nested `polymon()` or `polyman()`).  The only
   refresh-only callers of `set_uasmon()`, `set_ulycn()` (eating, quaffing,
   attacking, praying) and the were-change refresh in `moveloop_core()`,
   cannot run inside `polymon()` or `break_armor()`.  If one ever could, the
   guard would still stop the stale work, but nobody would finish it.
3. **A guard follows every re-entrant boundary.**  The eight boundaries are the
   model's `POLY_*`/`ARMOR_*` list above; `audit-patch.mjs` applies the PR's
   patches and checks all eight generation guards exist, and the CBMC
   guard-necessity controls show each one is needed.

## What it does not prove

This is a modular proof of the reentrancy protocol and its reviewed source
refinement, not a claim that every unrelated NetHack property has been
formally verified. In particular:

- callback bodies are over-approximated as nondeterministic form changes;
- it does not model every global mutated by polymorphing;
- the source mapping is checked by the transition-site inventory and patch
  shape audit, rather than by translating all of NetHack's unrelated C code.

This boundary is intentional: the result is an unbounded proof of the stated
ownership/light/cleanup properties under arbitrary form-installation choices,
plus negative controls showing that each guard is needed. It is not a blanket
proof of all NetHack behavior.

## Interactive explainer

The [interactive proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/) (source in [`explainer/`](explainer/))
walks through this proof in six parts and links each step to the NetHack
source. Its in-page model is a transcription of `polyself_model.c`, checked
against every expected `run-cbmc.sh` outcome by `explainer/test-model.mjs`.
