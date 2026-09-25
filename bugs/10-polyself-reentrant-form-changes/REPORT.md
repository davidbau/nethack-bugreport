# Formal verification report

This report checks the re-entrant polymorph fix described in `README.md`.
For a visual walkthrough of the same argument, with the model running in the
browser and every boundary linked to the source, see the
[interactive proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/).
The question is narrow: after a callback changes the hero's form, can the
old operation continue applying effects that belong to the old form?

## What is being proved

The patch keeps one invariant:

> **A running `polymon()` or `break_armor()` may act for its form only while
> it owns it: while no form has been installed since it saved its
> generation.**

Three facts keep it true:

1. **The counter only goes up.** Every form installation adds one, inside
   `set_uasmon()`, and the counter never wraps (the patch panics first).
2. **So an equal counter means nothing happened.** If the counter still
   equals a call's saved generation, no form has been installed since: the
   call *owns* the form. Once anything is installed the saved value is below
   the counter for good: the call is *stale*.
3. **Only an owner acts.** After every callback that could install a form,
   a checkpoint returns if the call has gone stale.

Each bug is a stale call that kept acting. Bug 08: `break_armor()` stripped a
human's gear by a newt's rules. Bug 06: `polymon()` repeated the cleanup its
successor had already run. Bug 07 breaks a second, smaller invariant, that a
light source exists exactly when the installed form glows; the patch updates
the light in the same step as the form.

**Why a counter, not the form number (ABA).** A callback can change the form
and change it back (a polymorph trap can even reinstall the same form). The
form number is then unchanged, so comparing it cannot express "nothing was
installed since". The counter can.

## How the proof works

The proof uses two complementary approaches:

- **CBMC** (C Bounded Model Checker) explores every choice in a small C model,
  including arbitrary nested form installations and ABA. It also runs
  negative tests: removing a guard or using identity-only checks produces a
  counterexample.
- **ACSL/WP** uses annotations written in ACSL (the ANSI/ISO C Specification
  Language). Frama-C's WP ( weakest-precondition ) engine turns those
  annotations into mathematical proof obligations and discharges them with
  Qed and Alt-Ergo. The ACSL file states the three facts as contracts
  (`install_form()`, `checkpoint()`, and `owned_effect()`, whose
  precondition `owns(g)` is the invariant itself), lets a callback install
  any number of forms, and checks every function with nothing left assumed:
  **158/158** obligations. Ten deliberate breakages must make WP fail: each
  of the eight checkpoints ignored in turn, the counter not bumped, and the
  identity guard allowed a same-form reinstall.

The source audits then connect the model to the pinned NetHack source. They
inventory all direct form writes and `set_uasmon()` edges, enumerate 21 direct
`polymon()` callers, and include the trap route that demonstrates reachable
ABA. The audits fail if a new installation edge appears without review. The
patch audit applies the two patches that make up PR #1681 and checks the
shape the model assumes: `set_uasmon()` bumps the counter, and all eight
generation guards are present with no identity guard left behind.

The model is only as good as three premises that the provers do not see:
every form installation goes through `set_uasmon()`; every counter bump that
can happen inside the window belongs to an installer that finishes its own
form's setup; and a guard follows every re-entrant boundary.
[`proof/README.md`](proof/README.md) says how each is checked.

Run everything from the repository root:

```sh
bash bugs/10-polyself-reentrant-form-changes/proof/verify.sh
```

The tools are pinned to CBMC 6.10.0 and Frama-C 32.1 with Alt-Ergo 2.5.4.
The machine-readable inputs and results are in
[`verification-manifest.json`](verification-manifest.json).

## Scope

This is a modular proof of the ownership, re-entrancy, light-bookkeeping, and
cleanup properties. It is not a proof of every unrelated NetHack behavior or
of arbitrary C function-pointer behavior. The exact patch candidate and the
source pin audited by the scripts are recorded in `proof/`.
