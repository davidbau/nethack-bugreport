# Farlook writes one byte past a stack buffer when it quotes a long engraving

When the hero looks at a remembered engraving with `;` (or `/`, or just moves
the `getpos` cursor over it with `autodescribe` on, which is the default),
the description quotes the engraving's text:

```
`        a boulder or an engraving (engraving with remembered text: "Ye who
read this, know that the floor remembers every word burned into it. ...
```

If the engraving is 219 characters or longer, building that description
writes a NUL one byte past the end of a 256-byte stack buffer, `temp_buf` in
`do_screen_description()`. Engravings that long are reachable in normal play:
adding to an engraving is allowed until it reaches `BUFSZ - 1` (255)
characters, and the recording below makes one of 226 characters with three
engravings of fewer than 80 characters each. A headstone that has been
added to overflows the same way at 221 characters.

Nothing visible goes wrong. What the player sees is already cut short by
`out_str`'s own limit, and in a normal build the stray byte goes unnoticed.
But the write is outside the array, so what it lands on depends on the
compiler's stack layout, and an AddressSanitizer build stops on it at once.

It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/19-farlook-temp-buf-overflow`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/19-farlook-temp-buf-overflow)
holds one proposed commit, verified by rebuild.

Severity: low. It is a one-byte stack overflow with no visible effect in
normal builds, reachable only with a very long engraving. It is worth fixing
because it is undefined behaviour and it stops sanitizer and fuzzing builds.

## Watch it happen

- [**The farlook, stock 5.0.0**](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session.json#step=264)
  (a normal build, where nothing looks wrong). The overflow already happens
  one step earlier, at [step 263](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session.json#step=263),
  when the `getpos` cursor moves onto the engraving and `autodescribe`
  describes it.
- [**The same keystream with the patch**](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/19-farlook-engraving-overflow/session-fixed.json#step=264),
  recorded with an AddressSanitizer build of the patched source. It runs to
  the end with no report, and every step is identical to the stock
  recording.

The scenario, in wizard mode: seed 2, a Valkyrie with `pettype:none`. She wishes for a wand of fire (`^W`), steps
north, and burns three engravings into the floor there (72, 75 and 79
characters, which make 226), steps back, and farlooks the engraving with
`;` `k` `.`. Burning is used only because burned text does not smudge while
it is being written; writing in the dust with fingers gets there too.

[`asan-stock.txt`](asan-stock.txt) is AddressSanitizer's report from the
stock source on this keystream. The key lines:

```
ERROR: AddressSanitizer: stack-buffer-overflow ...
WRITE of size 2 at ... thread T0
    #0 ... in strcat
    #1 ... in do_screen_description recorder/src/pager.c:1613:17
    #2 ... in auto_describe recorder/src/getpos.c:649:9
    #3 ... in getpos recorder/src/getpos.c:866:13
    #4 ... in do_look recorder/src/pager.c:1910:23
    #5 ... in doquickwhatis recorder/src/pager.c:2331:12
  ...
    [784, 1040) 'temp_buf' (line 1597) <== Memory access at offset 1040 overflows this variable
```

The recorder's patches do not touch `pager.c`, so its line numbers are
upstream's. The two-byte write is `")"` plus its terminator starting at
`temp_buf[255]`; ASan flags the second byte, `temp_buf[256]`.

## Reproducing it

```
bash bugs/19-farlook-engraving-overflow/repro.sh
```

That compiles and runs [`repro.c`](repro.c), a copy of the two functions'
string handling that checks the byte after a 256-byte buffer for every
engraving length. It prints:

```
engraving text 219 chars: upstream strlen(temp_buf)=256, NUL written at temp_buf[256]  <-- one past the end
engraving text 219 chars: patched  strlen(temp_buf)=255, in bounds
engraving: upstream overflows for every text of 219 chars or more

grave     text 221 chars: upstream strlen(temp_buf)=256, NUL written at temp_buf[256]  <-- one past the end
grave     text 221 chars: patched  strlen(temp_buf)=255, in bounds
grave    : upstream overflows for every text of 221 chars or more

patched: no overflow for any length
```

It then checks your tree's `src/pager.c`. To also run the real game, build
a recorder with AddressSanitizer: in a copy of `nethack-c/`, have
`build-recorder.sh` add `-fsanitize=address -fno-omit-frame-pointer` to
`CFLAGS` and `-fsanitize=address` to `LINK` and `LFLAGS` in
`sys/unix/hints/linux-minimal` before configuring, and keep the install
directory's path under 128 characters (NetHack ignores a longer
`NETHACKDIR`). Then

```
NETHACK_ASAN_INSTALL=<that build's .../games/lib/nethackdir> \
    bash bugs/19-farlook-engraving-overflow/repro.sh
```

re-records `session.json` with it and looks for the report. The exit status
is 0 when the bug is confirmed, 1 when it is not reproduced (normally
because the patch is applied), and 2 when it could not tell.

## What the code is doing

`do_screen_description()`
([`pager.c:1597-1615`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L1597-L1615)):

```c
            char temp_buf[BUFSZ];
            ...
            if (*(*firstmatch)) {
                Sprintf(temp_buf, " (%s", *firstmatch);
                (void) add_quoted_engraving(cc.x, cc.y, temp_buf, FALSE);
                Strcat(temp_buf, ")");
                (void) strncat(out_str, temp_buf,
                               BUFSZ - strlen(out_str) - 1);
```

`add_quoted_engraving()`
([`pager.c:1657-1665`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L1657-L1665))
appends the quoted text, and caps what it adds so that `buf` holds at most
`BUFSZ - 1` characters:

```c
    if (ep->eread)
        Snprintf(temp_buf, sizeof temp_buf, " with %s: \"%s\"",
                 headstone ? "headstone reading" : "remembered text",
                 ep->engr_txt[remembered_text]);
    ...
    (void) strncat(buf, temp_buf, BUFSZ - strlen(buf) - 1);
```

That cap is right for a buffer nobody adds to afterwards, but this caller
adds the closing paren. `" (engraving"` is 11 characters and
`" with remembered text: \""` is 24, so once the text reaches 219
characters, 11 + 24 + 219 + 1 = 255 and `temp_buf` is full. `Strcat()` then
puts `)` in `temp_buf[255]` and the terminating NUL in `temp_buf[256]`, one
past the end. (For a headstone, `" (grave"` and `" with headstone
reading: \""` are 7 and 26, hence 221.)

The other caller, `look_engrs()`
([`pager.c:2170-2171`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2170-L2171)),
does not add a paren; it strips the opening one and later cuts its buffer
to fit, so it is not affected by this. (It has a different problem with the
same long engravings, [bug 22](../22-look-engrs-glyph-cut/).)

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): make room for the paren in the
caller that adds it.

```c
                Sprintf(temp_buf, " (%s", *firstmatch);
                (void) add_quoted_engraving(cc.x, cc.y, temp_buf, FALSE);
                /* a long engraving can fill temp_buf; leave room for ')' */
                temp_buf[sizeof temp_buf - 2] = '\0';
                Strcat(temp_buf, ")");
```

Diff:
[commit 2ef159dd8](https://github.com/davidbau/NetHack/commit/2ef159dd82bcd1ad2b0c7b8f307126885fa8ebeb).

This is the same idiom `look_engrs()` and `look_traps()` use for their own
overflow guards. When the text is shorter the store is past the end of the
string and changes nothing. What the player sees does not change either: in
the long case `out_str` already has its prefix and explanation in front, so
its `strncat()` cap cut `temp_buf` well before the paren with or without the
patch.

An alternative is to cap `add_quoted_engraving()` itself at `BUFSZ - 2`.
That also fixes it, but it shortens `look_engrs()`'s text by one character
for a caller that does not need the room, so the local fix is offered
instead.

## Verification

The same seed, datetime and keystream, recorded four ways:

| build | steps recorded | RNG entries | AddressSanitizer |
|---|---|---|---|
| stock, normal build | 265 of 265 | 2,845 | not applicable; nothing visible |
| stock, `-fsanitize=address` | 263 (aborts on step 263, the cursor move onto the engraving) | 2,845 up to the abort | `stack-buffer-overflow` in `do_screen_description`, `pager.c:1613`, one byte past `temp_buf` |
| patched, `-fsanitize=address` | 265 of 265 | 2,845 | no report |
| stock again, `-fsanitize=address`, after reverting and rebuilding | 263 | 2,845 | the same report; recording byte-identical to the first stock ASan run |

The patched ASan recording is identical, step for step (screens, cursor and
RNG), to the stock normal-build recording, which is the check that the
patch changes nothing a player can see. The last row is the control that
the report comes and goes with the patch rather than with the rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from
Claude Opus 5.5. It surfaced while porting the farlook text for long
engravings: matching C's truncation byte for byte meant counting exactly how
full `temp_buf` gets, and the count came out one byte past its end.
