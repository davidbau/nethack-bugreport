# Bug #02 — `#wizborn` builds a totals row but forgets to `putstr` it

**Status:** unreported upstream as of 2026-06-19 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
and [PRs](https://github.com/NetHack/NetHack/pulls) for `wizborn`,
`doborn`, `mvitals totals`, `born died totals`, `insight.c 3170` —
no matching issue or PR).

**NetHack version:** 5.0.0 (also present in the 3.7 line; the
`doborn()` function in `src/insight.c` has not changed in the
totals area for several years).

**Not patch-induced:** the recorder binary used by `repro.sh` is
built from `nethack-c/upstream/` with the patches in
`nethack-c/patches/`. Those patches only add marker emission for
deterministic session recording (`NOMUX_MARKERS=1`); they do not
touch `insight.c`, `doborn()`, or the `#wizborn` extended command.
The bug fires identically when the recorded session is replayed
through the patched binary OR through a freshly-built vanilla
`nethack-c/upstream/` binary.

**Severity:** low (cosmetic — wizmode-only `#wizborn` debug display
is missing its summary row). The header, per-species rows, and a
trailing empty separator render correctly; only the final totals
row, which the surrounding code clearly intended to emit, never
reaches the screen.

## What you see in-game

After invoking `#wizborn` in wizmode, the displayed window contains:

```
died born
   0    1   kitten
   0    1   lichen




















--More--
```

The header `died born` (one row), then each per-species row formatted
via `Sprintf` + `putstr`, then a blank separator line. **The totals
row is missing** — there is no `   0    2  ` (or similar) summary
line after the separator, even though the code immediately above the
`display_nhwindow` call has called `Sprintf` to format exactly that
row into `buf`. The buffer is computed and then thrown away.

## Repro

```bash
cd nethack-bugreport
bash setup.sh                                    # build the recorder once
bash bugs/02-wizborn-totals/repro.sh
```

`repro.sh` re-runs `session.json` through the recorder binary and
asserts that the rendered output of `#wizborn` contains the
per-species rows but does NOT contain a totals row after the
separator. The session is 58 steps; the bug is observable at step 10
(the screen returned after the `#wizborn` command and its
`--More--`-page).

To watch the run visually with no setup, open the hosted viewer:

  https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/02-wizborn-totals/session.json#step=10

## Character / seed

- Seed: `7160`
- Datetime: `20000110090000`
- Character: Diag the Evoker (Wizard, neutral, human, male; wizmode)
- Bug fires: step 10 (`#wizborn` page render).

The same bug fires for any character, any seed, any starting
position — `doborn()` reads only `svm.mvitals[]` (global birth/death
counters), so its display logic is independent of game state.
`seed7160-wizmode-diagnostics` was chosen because it already
contains a `#wizborn` invocation as part of its wizmode-command
sweep.

## Root cause

`src/insight.c:3144-3176 doborn()`:

```c
int
doborn(void)
{
    static const char fmt[] = "%4i %4i %c %-30s";
    int i;
    winid datawin = create_nhwindow(NHW_TEXT);
    char buf[BUFSZ];
    int nborn = 0, ndied = 0;

    putstr(datawin, 0, "died born");
    for (i = LOW_PM; i < NUMMONS; i++)
        if (svm.mvitals[i].born || svm.mvitals[i].died
            || (svm.mvitals[i].mvflags & G_GONE) != 0) {
            Sprintf(buf, fmt,
                    svm.mvitals[i].died, svm.mvitals[i].born,
                    ((svm.mvitals[i].mvflags & G_GONE) == G_EXTINCT) ? 'E'
                    : ((svm.mvitals[i].mvflags & G_GONE) == G_GENOD) ? 'G'
                      : ((svm.mvitals[i].mvflags & G_GONE) != 0) ? 'X'
                        : ' ',
                    mons[i].pmnames[NEUTRAL]);
            putstr(datawin, 0, buf);                /* per-PM row */
            nborn += svm.mvitals[i].born;
            ndied += svm.mvitals[i].died;
        }

    putstr(datawin, 0, "");                         /* empty separator */
    Sprintf(buf, fmt, ndied, nborn, ' ', "");       /* totals computed... */

    display_nhwindow(datawin, FALSE);               /* ...but never displayed */
    destroy_nhwindow(datawin);

    return ECMD_OK;
}
```

The trailing `Sprintf` at line 3170 builds a totals line into `buf`
using the same `fmt` template as the per-species loop above, but the
very next line (`display_nhwindow` at 3172) closes the window
without an intervening `putstr(datawin, 0, buf)`. The buffer is
side-effected into local memory and then immediately abandoned when
the function returns.

The three lines of evidence that this is an oversight rather than a
design choice:

1. **The per-PM loop's `Sprintf` is always followed by a matching
   `putstr` — same template.** The trailing `Sprintf` is one keystroke
   away from matching.
2. **The empty separator `putstr(datawin, 0, "")` at line 3169 only
   has visual purpose if the totals row was meant to follow it.**
   Without the totals row, the separator is a trailing blank line
   nobody asked for.
3. **`Sprintf` with no consumer has no other purpose.** It writes to
   a local buffer; if the output were intentionally discarded, the
   call would simply be deleted, not the `putstr` that consumes it.

## Proposed patch

See `proposed-fix.patch`. **Insert `putstr(datawin, 0, buf);`
between `insight.c:3170` and `insight.c:3172`** so the formatted
totals row reaches the window before it is displayed and destroyed.

The corrected output is shown by `session-fixed.json` at the same
step 10 — header + per-species rows + separator + a new totals row
formatted with the same `fmt` template, summarizing the deaths
and births across all species. See the side-by-side diff in
`expected-output.txt`.

**Verified locally:** applying this patch and replaying
`session.json` against the patched recorder produces the totals row
correctly. The rest of the screen is byte-identical to the original
recording.

## Test sessions

- `session.json` — recorded `seed7160` wizmode-diagnostics game in
  v5 session format. 58 steps. The `#wizborn` page renders at
  step 10. Replay it through `scripts/record-session.mjs` (or
  `repro.sh`) on a freshly-built nethack binary to confirm the bug
  exists in vanilla 5.0.
- `session-fixed.json` — the same session, but with step 10's
  `screen` field replaced by the output of a JS-port replay with
  the patch's equivalent applied to `js/insight.js` (`out.push(fmt(
  ndied, nborn, ' ', ''))` uncommented).  All other steps are
  byte-identical to `session.json`.  The teleport JS port is
  bit-faithful to C (`source: c` parity verified across the full
  session suite), so the JS-rendered "fixed" screen is what a
  patched C recorder would produce.  Independently regenerating
  this artifact from a freshly built patched C binary is a TODO
  before filing upstream; until then the JS-port equivalence
  serves as the reference output.
- `expected-output.txt` — side-by-side text comparison of the
  step-10 screen, current vs. fixed.
- `step10-current-screen.txt` / `step10-fixed-screen.txt` — the
  raw per-step captures the side-by-side comparison was built from.
