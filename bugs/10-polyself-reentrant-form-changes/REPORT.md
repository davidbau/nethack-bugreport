# Formal verification report

This report checks the re-entrant polymorph fix described in `README.md`.
For a visual walkthrough of the same argument, with the model running in the
browser and every boundary linked to the source, see the
[interactive proof explainer](https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/).
The question is narrow: after a callback changes the hero's form, can the
old operation continue applying effects that belong to the old form?

## What is being proved

The proof checks four properties:

1. Form-dependent light bookkeeping is done immediately when a form is
   installed.
2. Every `polymon()` and `break_armor()` boundary stops if a nested callback
   installed any new form.
3. Cleanup is not repeated for the same form installation.
4. Every direct form-installation site is covered by the generation update.

The generation counter makes the key property simple: even if the hero goes
from form A to form B and back to form A, the generation number is different.
The outer operation therefore detects the change.

## What does ABA mean here?

ABA is a standard concurrency/re-entrancy pattern. Code observes state `A`, a
nested call changes it to `B`, and the nested call changes it back to `A`.
Comparing only the final form number cannot detect that anything happened.
Here, a trap-triggered `polyself()` call can reinstall the same monster form.
The generation counter records the event even when the form number is again
unchanged.

## How the proof works

The proof uses two complementary approaches:

- **CBMC** (C Bounded Model Checker) explores every choice in a small C model,
  including arbitrary nested form installations and ABA. It also runs
  negative tests: removing a guard or using identity-only checks produces a
  counterexample.
- **ACSL/WP** uses annotations written in ACSL (the ANSI/ISO C Specification
  Language). Frama-C's WP ( weakest-precondition ) engine turns those
  annotations into mathematical proof obligations and discharges them with
  Qed and Alt-Ergo. Every function in the model is checked against its own
  contract, and nothing is left assumed: **488/488** obligations. This
  includes a boundary at which one callback may install any number of forms
  (a loop with an invariant), and a WP negative control in which the identity
  guard, allowed a same-form reinstall, leaves its key assertion unproved.

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
