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

Frama-C/WP proves the generation-guard protocol with arbitrary nested form
installations, including explicit same-form ABA reinstallations. The current
entry points discharge **76/76** WP obligations with Qed or Alt-Ergo. The
earlier restricted no-ABA transition model remains in the source for
comparison, but is not used as the final safety argument.

There are no loops in the model, so no behavior is excluded by an unwind
bound.  `--unwinding-assertions` remains enabled to make that fact checked by
CBMC rather than assumed.

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

## Interactive explainer (draft)

[`explainer/`](explainer/) walks through this proof interactively and links
each step to the NetHack source. Its README lists open questions that need
CBMC and Frama-C runs.
