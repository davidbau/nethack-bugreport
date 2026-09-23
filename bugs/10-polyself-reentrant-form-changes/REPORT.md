# Polymorph reentrancy verification report

Status: complete for the stated protocol properties.

This report accompanies the proposed fix for NetHack issue #1681. The
reproducible commands and pinned inputs are in `proof/`.

## Conclusion

The identity-only guards in the original patch are insufficient. CBMC finds a
counterexample when a nested callback performs an ABA transition (form A to B
and back to A), and the source audit finds a reachable trap-triggered
`polyself()` route that can reinstall the same form number.

The verified design is a monotonic `uasmon_generation` serial. Every semantic
hero-form installation increments the serial, including same-form
reinstallation. Each reentrant operation saves the serial and rejects stale
work when it changes. The serial is runtime state and is not saved.

## Claims and evidence

| ID | Claim | Evidence | Result |
|---|---|---|---|
| P1 | Arbitrary nested form installation, including ABA, invalidates stale generation ownership. | `proof/polyself_acsl.c`, Frama-C/WP entry points | 76/76 proved |
| P2 | The same generation protocol covers all five `polymon()` and three `break_armor()` boundaries. | `proof/polyself_model.c`, CBMC epoch runs | pass |
| P3 | Every direct semantic form-write and `set_uasmon()` edge is inventoried. | `proof/audit-form-transitions.mjs`, `proof/audit-callgraph.mjs` | pass; 16 sites, 21 direct `polymon()` callers |
| P4 | The trap-triggered same-form route defeats identity comparison. | `proof/audit-patch.mjs`, CBMC negative control | expected counterexample |
| P5 | Immediate light bookkeeping and cleanup generation invariants hold. | CBMC positive controls | pass |
| P6 | Removing any individual guard admits stale work. | CBMC negative controls | 8 expected counterexamples |

## Reproduction

Run the complete suite from the repository root:

```sh
bash bugs/10-polyself-reentrant-form-changes/proof/verify.sh
```

The suite uses Docker-pinned CBMC 6.10.0 and Frama-C 32.1 with Alt-Ergo.
`verification-manifest.json` records the commands, versions, source pin, and
expected outcomes in machine-readable form.

## Scope and limitation

This is a modular proof of the ownership, reentrancy, light-bookkeeping, and
cleanup properties. It is not a proof of every unrelated NetHack behavior.
The call-graph audit is conservative and source-based: it rejects newly
appearing direct installation sites, enumerates all direct `polymon()` callers,
and requires review when `set_uasmon()` edges change. It does not claim that a
general C compiler or arbitrary function-pointer analysis has been verified.
