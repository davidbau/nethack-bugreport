**Title:** Farlook writes one byte past a stack buffer when it quotes a long engraving

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/19-farlook-temp-buf-overflow`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/19-farlook-temp-buf-overflow).

**Symptom**

Farlook on a remembered engraving (`;`, `/`, or the `getpos` cursor with
`autodescribe`, the default) quotes its text. If the engraving is 219
characters or longer (a headstone: 221), `do_screen_description()` writes a
NUL one byte past the 256-byte stack buffer `temp_buf`. Adding to an
engraving is allowed up to 255 characters; the recording builds one of 226
from three engravings of 72, 75 and 79 characters.

Nothing visible goes wrong in a normal build (the displayed text is already
cut by `out_str`'s limit). An AddressSanitizer build stops at once
([`asan-stock.txt`](asan-stock.txt)):

```
ERROR: AddressSanitizer: stack-buffer-overflow ...
WRITE of size 2 at ... thread T0
    #0 ... in strcat
    #1 ... in do_screen_description recorder/src/pager.c:1613:17
    #2 ... in auto_describe recorder/src/getpos.c:649:9
    [784, 1040) 'temp_buf' (line 1597) <== Memory access at offset 1040 overflows this variable
```

- [Farlook, stock 5.0.0](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session.json#step=264)
  (normal build); the overflow already happens at
  [step 263](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session.json#step=263),
  when the cursor moves onto the engraving.
- [Patched, ASan build](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session-fixed.json#step=264):
  no report, every step identical to the stock recording.

**Cause**

`pager.c:1610-1613`
([source](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L1597-L1615)):

```c
                Sprintf(temp_buf, " (%s", *firstmatch);
                (void) add_quoted_engraving(cc.x, cc.y, temp_buf, FALSE);
                Strcat(temp_buf, ")");
```

`add_quoted_engraving()`
([`pager.c:1657-1665`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L1657-L1665))
fills `buf` up to `BUFSZ - 1` characters. `" (engraving"` (11) plus
`" with remembered text: \""` (24) plus 219 characters plus the quote is
255, so `Strcat()` puts `)` in `temp_buf[255]` and the NUL in
`temp_buf[256]`. The other caller, `look_engrs()`, adds no paren and is not
affected by this (it has [bug 22](../22-look-engrs-glyph-cut/)).

**Fix**

```diff
                 (void) add_quoted_engraving(cc.x, cc.y, temp_buf, FALSE);
+                /* a long engraving can fill temp_buf; leave room for ')' */
+                temp_buf[sizeof temp_buf - 2] = '\0';
                 Strcat(temp_buf, ")");
```

Commit [2ef159dd8](https://github.com/davidbau/NetHack/commit/2ef159dd82bcd1ad2b0c7b8f307126885fa8ebeb);
also `proposed-fix.patch`. This is the idiom `look_engrs()` and
`look_traps()` use. The displayed text does not change: `out_str`'s
`strncat()` cap already cuts before the paren. Capping
`add_quoted_engraving()` at `BUFSZ - 2` would also work but shortens
`look_engrs()`'s text by one character.

**Repro**

```
bash bugs/19-farlook-engraving-overflow/repro.sh
```

compiles and runs [`repro.c`](repro.c), a copy of the two functions' string
handling, which reports that upstream overflows for every engraving text of
219 characters or more (grave: 221) and the patched code for none, then
checks your tree's `src/pager.c`. To run the game itself, build the recorder
with `-fsanitize=address -fno-omit-frame-pointer` in `CFLAGS` and
`-fsanitize=address` in `LINK` and `LFLAGS` (`sys/unix/hints/linux-minimal`),
keep the install path under 128 characters, and run

```
NETHACK_ASAN_INSTALL=<that build's .../games/lib/nethackdir> \
    bash bugs/19-farlook-engraving-overflow/repro.sh
```

It re-records `session.json` (wizard mode, seed 2, Valkyrie with
`pettype:none`: wish for a wand of fire, burn three engravings to the north,
step back, `;` `k` `.`) and looks for the report. Exit 0: bug confirmed;
1: not reproduced (normally, patched); 2: could not tell. Stock ASan aborts
at step 263 of 265; patched ASan runs all 265 with the same 2,845 RNG
entries, and reverting and rebuilding gives the same report again.
