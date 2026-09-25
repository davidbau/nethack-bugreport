# Proof explainer (draft)

An interactive, nine-part explanation of how bug 10's fix is verified: the
re-entrancy bugs, the CBMC model, negative controls, ABA and the generation
counter, Frama-C/WP weakest preconditions, and the source audits. Every part
links into annotated excerpts of the NetHack source at the proof's pin
(`16ff59115`).

Open `index.html` in a browser (it is self-contained). The same page is
published as a private claude.ai artifact.

**Status: draft.** It was written on a machine without Docker, so neither
CBMC nor Frama-C was run. The CBMC half is solid, because the page runs a
transcription of the model that reproduces `run-cbmc.sh`'s expected results.
The WP half is hand-written and needs checking against real tool output.
See [Open questions](#open-questions-for-a-machine-with-docker).

## Files

| file | what it is |
|---|---|
| `template.html` | the page: CSS, prose, and all view code. Placeholders `/*__MODEL_JS__*/`, `/*__SRC_DATA__*/`, `/*__MODEL_SRC__*/` are filled by the build. It has no `<html>`/`<head>`, because the artifact host supplies them; the build wraps it for standalone use. |
| `model.js` | a JavaScript transcription of `../polyself_model.c`. It takes explicit choice lists in place of `nondet_uint()`, records a trace, and explores the whole choice tree. |
| `test-model.mjs` | `node test-model.mjs` checks `model.js` against the 18 expected pass/fail outcomes in `../run-cbmc.sh`. |
| `build.py` | extracts and annotates the NetHack excerpts (boundary tags, notes, patch lines added and removed) and writes `index.html`. |
| `index.html` | built output. Commit it after rebuilding. |

Rebuild:

```sh
python3 build.py                                # if nethack-c/upstream is at the pin
python3 build.py --nethack-repo ~/src/NetHack   # else, any clone containing 16ff59115
node test-model.mjs
```

The annotations live in `build.py`. Each one names a line by a text match
within an excerpt, so a wrong match fails the build rather than silently
moving. The patch lines shown as additions follow `../generation-guard.patch`
applied on top of `../../proposed-fix.patch`.

## What is solid and what is hand-made

- **Solid:** explainers 3, 4 and 5 run `model.js`. `test-model.mjs` shows it
  agrees with every expected CBMC outcome, so the paths, counterexamples and
  path counts shown are faithful to the model.
- **Hand-made from reading:** explainer 1's scenario timelines (written from
  `../../README-old.md` and the three bug bundles, not generated from the
  recordings); explainer 7's WP steps (a simplified `boundary()` that leaves
  out `light_consistent` and `valid_form`, with formulas written by hand);
  explainer 8's "bumps the generation?" column; and explainer 9's review
  notes.

## Open questions for a machine with Docker

Run `bash ../verify.sh` first and keep its full output. Then:

1. **Does the 76/76 WP run prove the boundary lemma?** This is the most
   important question. `../run-wp.sh` passes
   `-wp-fct verify_polymon_generation_arbitrary_aba,verify_break_armor_generation_arbitrary_aba`.
   If `-wp-fct` restricts goal generation to those functions, as I believe,
   then the contracts of `generation_boundary_arbitrary_aba()` (including its
   `assert choice == 0`), `install_form()` and `reset_world()` are assumed and
   never checked against their bodies. Run WP a second time with those three
   functions added to `-wp-fct` (or with no `-wp-fct`), and record the goal
   counts and any unproved goals.
   - If the extra goals all prove, update `REPORT.md`,
     `verification-manifest.json` and `run-wp.sh` to use the wider set, and
     soften the caveat in explainer 9.
   - If some fail, that is a real finding: report it to the user before
     changing anything.
2. **What are the 76 goals?** Capture the per-goal list, with the goal name,
   its kind (ensures, assert, call precondition, assigns, rte) and which prover
   closed it, using `-wp-print`, `-wp-out <dir>`, or `-then -report`. Use it to
   (a) replace explainer 7's hand-written obligation categories with the real
   breakdown, and (b) check that the hand-written backward steps match what WP
   generates for `generation_boundary_arbitrary_aba`. Explainer 7 claims that
   "Qed, then Alt-Ergo if needed" closes it; confirm which one does.
3. **Show the identity guard failing in WP.** Explainer 7's identity mode says
   the goal is unprovable when `choice` may be 3. Run WP on a variant of
   `identity_boundary_no_aba` with `requires 0 <= choice <= 3` and record what
   WP reports (Unknown or Timeout). Quote that output in the page.
4. **Real CBMC traces.** Rerun a few negative controls with `--trace`, at
   least "polymon identity guard does not itself exclude ABA" and one
   "omitted guard". Add a collapsible "CBMC's own trace" panel next to the
   page's step-through version in explainer 3 or 5, and confirm the trace
   follows the same path.
5. **`audit-patch.mjs`.** No script runs it, and it checks the identity-guard
   patch shape. Decide with the user whether to update it for
   `generation-guard.patch` and add it to `verify.sh`.
6. **Check the explainer's factual claims against the source and the
   recordings:**
   - explainer 1, bug 08: the lava and water-walking-boots story, and the
     step numbers in the session-viewer links;
   - explainer 1, bug 06: whether `rehumanize()` itself runs `encumber_msg()`
     and `retouch_equipment()` (the page says it does, via `polyman()`);
   - explainer 8: the "reviewed purpose" rows are quoted from
     `audit-form-transitions.mjs`, but the "bumps the generation?" column is
     my reading of `generation-guard.patch`;
   - the manifest's count of 21 direct `polymon()` callers
     (`node ../audit-callgraph.mjs` prints it).
7. **Cleanup-once under WP.** Explainer 9 says only CBMC checks it. Either add
   a WP entry point that calls `cleanup_current_form()` or keep the caveat.

## Editing notes

- Style follows the CS7150 class demos (`cs7150.github.io/classdemos`): a warm
  neutral palette, system font, one figure per explainer with a `.cap`
  caption, and an index list. Dark mode is handled by tokens on `:root`.
- The views are one page with hash routing (`#window`, `#model`, `#path`,
  `#cbmc`, `#controls`, `#aba`, `#wp`, `#audits`, `#scope`). Each view builds
  itself on first visit through `INIT[id]`.
- `SourceView(host, {key})` renders an annotated excerpt; `focus(tag)` opens
  a tagged line. Tags are `B0`–`B7` (boundaries), `B2g`/`B4g`/`B5g` (guards
  placed away from their boundary), `install`, `cleanup`, `aba`, `removed`,
  `fixme`, `reent`.
- To republish the artifact after editing, publish `index.html` or the built
  template to the same artifact URL (ask the user for it).
