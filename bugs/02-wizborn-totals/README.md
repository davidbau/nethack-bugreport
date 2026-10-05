**Title:** `#wizborn` builds a totals row but never `putstr`s it

**Version:** NetHack 5.0.0 (also in the 3.7 line). Re-checked 2026-09-18:
still present at the `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0).

### Symptom

In wizard mode, `#wizborn` shows the header, the per-species rows and a
blank separator, but no totals row:

```
died born
   0    1   kitten
   0    1   lichen

--More--
```

This happens for any character and seed; `doborn()` reads only
`svm.mvitals[]`.

### Cause

`doborn()` in `src/insight.c:3144-3176` ends with:

```c
    putstr(datawin, 0, "");                         /* separator */
    Sprintf(buf, fmt, ndied, nborn, ' ', "");       /* totals formatted */

    display_nhwindow(datawin, FALSE);               /* buf never put */
    destroy_nhwindow(datawin);
```

The `Sprintf` at line 3170 formats the totals with the same `fmt` as the
per-species rows, each of which is followed by `putstr(datawin, 0, buf)`.
Here the `putstr` is missing, so `buf` is discarded and the separator before
it is a trailing blank line.

### Fix

```diff
     putstr(datawin, 0, "");
     Sprintf(buf, fmt, ndied, nborn, ' ', "");
+    putstr(datawin, 0, buf);

     display_nhwindow(datawin, FALSE);
```

Full diff: `proposed-fix.patch`.

### Repro

```bash
bash setup.sh                                    # build the recorder once
bash bugs/02-wizborn-totals/repro.sh
```

`repro.sh` replays `session.json` (seed 7160, datetime `20000110090000`,
wizard-mode Wizard, 58 steps) through the recorder and checks that the
`#wizborn` page at step 10 has the per-species rows but no totals row after
the separator. The recorder's patches only add session markers
(`NOMUX_MARKERS=1`) and do not touch `insight.c`; the bug fires the same with
a vanilla build.

Viewer:
https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/02-wizborn-totals/session.json#step=10

With the patch, replaying `session.json` adds the totals row and leaves the
rest of the screen byte-identical. Files:

- `session-fixed.json`: `session.json` with step 10's screen replaced by the
  output of the teleport JS port with the equivalent fix. Regenerating it from
  a patched C binary is still a TODO.
- `expected-output.txt`: side-by-side step-10 screen, current vs. fixed.
- `step10-current-screen.txt`, `step10-fixed-screen.txt`: the raw captures.

### Status

Unreported upstream as of 2026-06-19 (searched
[issues](https://github.com/NetHack/NetHack/issues) and
[PRs](https://github.com/NetHack/NetHack/pulls) for `wizborn`, `doborn`,
`mvitals totals`, `born died totals`, `insight.c 3170`).
