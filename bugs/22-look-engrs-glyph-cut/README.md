**Title:** The engravings list shows the wrong symbol for an object lying on a long engraving

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/22-look-engrs-glyph-cut`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/22-look-engrs-glyph-cut).

**Symptom**

`/` `e` (or `E`) ends a covered engraving's line with `obscured by` and the
covering object's map symbol. With a dagger on a 191-character engraving:

```
<48,15> ` remembered text: "Ye who read this, know that the floor remembers
every word burned into it. Ye who read this, know that the floor remembers
every word burned into it. Ye who read this, know that the floor rem", obscured
by S
```

By engraving length the dagger shows as: 189-190 `)` (correct), 191 `S`,
192 `d`, 193-194 `a`, 196 `\G17` (raw text), 200 nothing. Adding to an
engraving is allowed up to 255 characters; this one is three engravings of
60, 65 and 66 characters.

- [Stock 5.0.0: `obscured by S`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/22-look-engrs-glyph-cut/session.json#step=230)
- [Patched: `obscured by )`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/22-look-engrs-glyph-cut/session-fixed.json#step=230)

**Cause**

`look_engrs()`
([`pager.c:2170-2219`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2170-L2219))
appends the covering object's code to `lookbuf`, then cuts `lookbuf` by
byte count:

```c
                Snprintf(eos(lookbuf), sizeof lookbuf - strlen(lookbuf),
                         ", obscured by %s", encglyph(glyph));
    ...
                lookbuf[sizeof lookbuf - 1 - strlen(outbuf)] = '\0';
                Strcat(outbuf, lookbuf);
```

`encglyph()`
([`windows.c:1428-1434`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/windows.c#L1428-L1434))
writes 10 bytes: `\G`, four hex digits of `context.rndencode`, four of the
glyph. `outbuf` is 21 bytes, so the cut is at `lookbuf[234]`; for a
T-character engraving the code occupies bytes T + 34 to T + 43, so for T
from 191 to 199 the cut lands inside it. `decode_glyph()`
([`windows.c:1439-1463`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/windows.c#L1439-L1463))
stops at the first non-hex character: with all four check digits intact
(T 191-194) it decodes the remaining glyph digits as a smaller glyph number
(three digits `S`, two `d`, one or none glyph 0 `a`); with the check digits
cut (T 195-199) `decode_mixed()` prints the code as text.
`look_traps()`
([`pager.c:2102`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2102),
[`2128`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2128))
has the same shape, but trap names are too short to reach the cut.

**Fix**

Keep the suffix in its own `QBUFSZ` buffer (cleared per location), cut only
the engraving text, and append the suffix whole:

```diff
-                Snprintf(eos(lookbuf), sizeof lookbuf - strlen(lookbuf),
-                         ", obscured by %s", encglyph(glyph));
+                Sprintf(obscbuf, ", obscured by %s", encglyph(glyph));
 ...
-                lookbuf[sizeof lookbuf - 1 - strlen(outbuf)] = '\0';
+                lookbuf[sizeof lookbuf - 1 - strlen(outbuf)
+                        - strlen(obscbuf)] = '\0';
                 Strcat(outbuf, lookbuf);
+                Strcat(outbuf, obscbuf);
```

Commit [1079647d5](https://github.com/davidbau/NetHack/commit/1079647d5ab5ba6f8a83353456369fa1d803f620);
full diff in `proposed-fix.patch`. The line still fits: 21 + at most 210 +
24 = 255 bytes. The text is cut 24 bytes sooner when covered, here dropping
the closing quote (`...floor rem, obscured by )`). Alternatively, the
suffix could be dropped when it does not fit whole.

**Repro**

```
bash bugs/22-look-engrs-glyph-cut/repro.sh
```

re-records [`session.json`](session.json) (wizard mode, seed 2, Valkyrie
with `pettype:none`: wish for a wand of fire, burn the three engravings to
the north, drop the dagger on them, step back, `/` `e`) and reads the symbol
after `obscured by`. Exit 0: not `)` (bug); 1: `)` (patched); 2: the list
did not appear. Both recordings have 231 steps and 2,784 identical RNG
entries; only the last screen differs. Reverting and rebuilding reproduced
the stock recording byte for byte.
