# The engravings list shows the wrong symbol for an object lying on a long engraving

The `/` command's `e` and `E` choices list the engravings the hero has seen.
When something is lying on an engraving, the line ends with what covers it,
drawn as its map symbol:

```
<48,15> ` remembered text: "...", obscured by )
```

For an engraving of about 190 to 200 characters that symbol comes out wrong.
In the recording below the hero drops a dagger on a 191-character engraving
and the list says:

```
Nearby seen or remembered engravings:

<48,15> ` remembered text: "Ye who read this, know that the floor remembers
every word burned into it. Ye who read this, know that the floor remembers
every word burned into it. Ye who read this, know that the floor rem", obscured
by S
```

The dagger is shown as `S`. A few characters longer and it is shown as `d`,
then `a`, then as raw text such as `\G17`.

The symbol travels through the line as a 10-byte code, `\G` and eight hex
digits, which `putmixed()` turns into one map symbol when it prints the
line. `look_engrs()` guards its line against overflow by cutting it at a
byte count, and for these lengths the cut lands inside that code. The
shortened code still decodes, as a different glyph.

Engravings this long are reachable in normal play: adding to an engraving is
allowed until it reaches 255 characters, and this one is three engravings of
fewer than 70 characters each.

It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/22-look-engrs-glyph-cut`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/22-look-engrs-glyph-cut)
holds one proposed commit, verified by rebuild.

Severity: low and cosmetic. The list shows the wrong symbol for what is
covering one very long engraving; nothing else is affected.

## Watch it happen

- [**Stock 5.0.0**: `obscured by S` for a dagger](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/22-look-engrs-glyph-cut/session.json#step=230)
- [**With the patch applied**: `obscured by )`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/22-look-engrs-glyph-cut/session-fixed.json#step=230)

The scenario, in wizard mode: seed 2, a Valkyrie with `pettype:none`. She
wishes for a wand of fire (`^W`), steps north, burns three engravings of 60,
65 and 66 characters into the floor there (191 characters in all), drops
her dagger on it, steps back south, and presses `/` `e`. Burning is used only
because burned text does not smudge while it is being written; writing in
the dust with fingers gets there too, less predictably.

The same scenario with other lengths, recorded while choosing this one:

| engraving length | shown for the dagger |
|---|---|
| 189, 190 | `)` (correct) |
| 191 | `S` |
| 192 | `d` |
| 193, 194 | `a` |
| 196 | `\G17` (raw text) |
| 200 | nothing after `obscured by` |

## Reproducing it

```
bash bugs/22-look-engrs-glyph-cut/repro.sh
```

That re-records [`session.json`](session.json) through the recorder and reads
the symbol after `obscured by`. It exits 0 when the symbol is not `)` (bug
present), 1 when it is `)` (normally because the patch is applied), and 2 when
the list did not appear.

## What the code is doing

`look_engrs()` in `src/pager.c`
([lines 2170-2219](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2170-L2219))
builds each line in two buffers of `BUFSZ` (256) bytes. `lookbuf` gets the
quoted text, with the text of `add_quoted_engraving()` and then, for a covered
engraving, the covering object's code:

```c
            Sprintf(lookbuf, " (%s", is_headstone ? "grave" : "engraving");
            (void) add_quoted_engraving(x, y, lookbuf, TRUE);
            ...
                (void) strsubst(lookbuf, "(engraving with ", "");
            ...
                /* engraving or grave covered by object(s) */
                Snprintf(eos(lookbuf), sizeof lookbuf - strlen(lookbuf),
                         ", obscured by %s", encglyph(glyph));
```

`outbuf` gets the coordinates and the engraving's own symbol, and then
`lookbuf` is cut so that the two fit together:

```c
                Sprintf(eos(outbuf), "%s ", encglyph(glyph));
                /* guard against potential overflow */
                lookbuf[sizeof lookbuf - 1 - strlen(outbuf)] = '\0';
                Strcat(outbuf, lookbuf);
                putmixed(win, 0, outbuf);
```

`encglyph()`
([`windows.c:1428-1434`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/windows.c#L1428-L1434))
writes `\G`, four hex digits of the per-game `context.rndencode`, and four
hex digits of the glyph. With the default map coordinates `outbuf` is
`"%8s  "` plus a code plus a space, 21 bytes, so the cut is at `lookbuf[234]`.
For an engraving of T characters, `lookbuf` holds
`` remembered text: "<T characters>"`` (T + 20 bytes), then
`", obscured by "` (14), then the 10-byte code, which therefore occupies bytes
T + 34 to T + 43. For T from 191 to 199 the cut falls inside it.

`decode_glyph()`
([`windows.c:1439-1463`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/windows.c#L1439-L1463))
reads up to four digits for the check value and up to four for the glyph,
stopping at the first character that is not a hex digit, which here is the
end of the string. So when all four check digits survive (T from 191 to 194)
it accepts the code and draws the glyph made of however many glyph digits
are left: a different, smaller glyph number. The dagger's glyph cut to three
digits is an `S`, to two a `d`, to one or none glyph 0, `a`. When the check
digits themselves are cut (T from 195 to 199) the check fails and
`decode_mixed()` prints the code as text.

The guard was written for plain text; the covering object's code was added
to `lookbuf`, the buffer it cuts, rather than to the part it keeps.
`look_traps()` has the same shape
([`pager.c:2102`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2102),
[`pager.c:2128`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/pager.c#L2128)),
but its text is a trap name, far too short to reach the cut.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): keep the `, obscured by` suffix
in its own buffer, cut only the engraving text, and append the suffix
whole.

```c
                /* engraving or grave covered by object(s); kept separate
                   from lookbuf so that truncating the engraving text can't
                   cut the encoded glyph in half */
                Sprintf(obscbuf, ", obscured by %s", encglyph(glyph));
    ...
                /* guard against potential overflow */
                lookbuf[sizeof lookbuf - 1 - strlen(outbuf)
                        - strlen(obscbuf)] = '\0';
                Strcat(outbuf, lookbuf);
                Strcat(outbuf, obscbuf);
```

Diff:
[commit 1079647d5](https://github.com/davidbau/NetHack/commit/1079647d5ab5ba6f8a83353456369fa1d803f620).
`obscbuf` is `QBUFSZ` and cleared for each location. The line still fits in
`outbuf`: 21 + at most 210 + 24 = 255 bytes.

The cost is that the engraving text is cut 24 bytes sooner when something
covers it, which here drops the closing quote (`...floor rem, obscured by )`
instead of `...floor rem", obscured by S`). Showing less of an overlong
engraving seemed better than showing the wrong object. A smaller change
would be to drop the suffix when it does not fit whole, at the cost of not
saying the engraving is covered.

## Verification

Rebuilt and re-recorded. Same seed, datetime and keystream:

| | stock | patched |
|---|---|---|
| steps recorded | 231 | 231 |
| RNG entries | 2,784 | 2,784 |
| RNG identical, step by step | yes | yes |
| screens that differ | | only the last, the engravings list |
| shown for the dagger | `S` | `)` |

Reverting the source and rebuilding reproduced the stock recording byte for
byte, which is the control that the patched run differed because of the
patch rather than because of the rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from
Claude Opus 5.5. It surfaced while porting the engravings list: to match C's
truncation byte for byte the port had to count the 10-byte glyph code as C
does, which showed that the cut can land inside it.
