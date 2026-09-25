# Proof explainer

A six-part interactive explanation of how bug 10's fix is verified. Every part
links into annotated excerpts of the NetHack source at the proof's pin
(`16ff59115`), with PR #1681 shown as a diff.

1. **The bugs**: bugs 06, 07 and 08 as timelines of `polymon()` and
   `break_armor()`, stock and fixed.
2. **The model**: the real `polymon()` beside `polyself_model.c`.
3. **Every path**: the full tree of callback outcomes for each guard, and all
   18 `run-cbmc.sh` checks, including the negative controls. Any leaf opens
   that path step by step.
4. **ABA**: why a generation counter rather than the form number.
5. **What WP adds**: the lemma for every input and any number of nested
   installations, and the WP negative control.
6. **What the proof rests on**: the three premises, the reviewed form-write
   sites, and the scope.

Published at
<https://davidbau.github.io/nethack-bugreport/bugs/10-polyself-reentrant-form-changes/proof/explainer/>;
`index.html` is self-contained and also opens straight from a checkout.

## Files

| file | what it is |
|---|---|
| `template.html` | the page: CSS, prose, and all view code. Placeholders `/*__MODEL_JS__*/`, `/*__SRC_DATA__*/`, `/*__MODEL_SRC__*/` are filled by the build. |
| `model.js` | a JavaScript transcription of `../polyself_model.c`. It takes explicit choice lists in place of `nondet_uint()`, records a trace, and explores the whole choice tree. |
| `test-model.mjs` | `node test-model.mjs` checks `model.js` against the 18 expected outcomes in `../run-cbmc.sh`. |
| `build.py` | extracts and annotates the NetHack excerpts (boundary tags, notes, patch lines) and writes `index.html`. |
| `index.html` | built output. Commit it after rebuilding. |

Rebuild:

```sh
python3 build.py                                # if nethack-c/upstream is at the pin
python3 build.py --nethack-repo ~/src/NetHack   # else, any clone containing 16ff59115
node test-model.mjs
```

Each annotation in `build.py` names a line by a text match within an excerpt,
so a wrong match fails the build rather than silently moving. The patch lines
follow `../../proposed-fix.patch` followed by `../generation-guard.patch`
(the four commits of PR #1681).

## What is generated and what is written by hand

- **Generated from the model:** parts 3 and 4 run `model.js`, which
  `test-model.mjs` shows agrees with every expected CBMC outcome, so their
  paths, counterexamples and counts are faithful to the model.
- **Quoted from the real tools:** part 5's numbers (488/488 goals: 433 Qed,
  47 Alt-Ergo, 8 trivial; the one unproved goal of the negative control) are
  from `../run-wp.sh` with Frama-C 32.1.
- **Written by hand, then checked:** part 1's timelines (each session-viewer
  link was checked to land on the step it describes), part 6's premises and
  site classifications (from `../audit-form-transitions.mjs` and a review of
  every `set_uasmon()` caller).

## Still open

- **Real CBMC traces.** Part 3 steps through the model's own trace. A
  collapsible panel with CBMC's `--trace` output for one negative control
  would show the tool's counterexample next to it.

## Editing notes

- The views are one page with hash routing (`#window`, `#model`, `#cbmc`,
  `#aba`, `#wp`, `#audits`, and the drill-down `#path`). Each view builds
  itself on first visit through `INIT[id]`; `VIEWS` entries with `sub:true`
  are routable but not listed in the index or pager.
- `SourceView(host, {key})` renders an annotated excerpt; `focus(tag)` opens
  a tagged line. Tags are `B0`–`B7` (boundaries), `B2g`/`B4g`/`B5g` (guards
  placed away from their boundary), `install`, `cleanup`, `aba`, `removed`,
  `fixme`, `reent`.
- Dark mode is handled by tokens on `:root`.
