**Title:** `S_lava`, `S_ant`, `S_human` and `S_mimic` in a symset or `SYMBOLS=` set a different symbol

**Version:** `NetHack-5.0` tip `a9f93bb00`. Introduced by `1de1b531b`
("Some optimizations of the glyph lookup").

### Symptom

A symbol name that is a prefix of another symbol name resolves to the
longer one:

| name | sets |
|------|------|
| `S_lava` | `S_lavawall` |
| `S_ant` | `S_anti_magic_trap` |
| `S_human` | `S_HUMANOID` |
| `S_mimic` | `S_MIMIC_DEF` |

Effects with the shipped `dat/symbols`:

- DECgraphics, IBMgraphics and AmigaFont: the `S_lava` line sets the lava
  wall symbol, and molten lava keeps the default `}` (instead of the DEC
  diamond, the IBM `≈`, or the Amiga `*`).
- RogueEpyx: `S_human: \x01` sets the humanoid class, so on the Rogue level
  the hero is `@` instead of the smiley, and `h` monsters show as `\x01`.
- Blank: ants, humans, mimics and lava keep their usual symbols.

In a config file, `SYMBOLS=S_ant:x` changes the anti-magic field trap and
leaves ants as `a`.

### Cause

`match_sym()` (src/symbols.c:860) looks the name up with
`search_loadsyms()`, a `bsearch()` over a sorted index of `loadsyms[]`.
The comparator, `symparse_find()` (src/symbols.c:958), compares the first
`bstr->len` characters and then returns 0:

```c
    for (i = 0; i < bstr->len; ++i) {
        ...
        if (c1 != c2) {
            return c1 - c2;
        }
    }

    return 0;
```

It never checks that the table name ends at `len`, so every name that
begins with the key compares equal, and `bsearch()` returns whichever of
them it probes first. The linear search it replaced required
`len >= strlen(sp->name)`, an exact match.

### Fix

```diff
     }
 
-    return 0;
+    /* a table name that continues past bstr->len sorts after bstr */
+    return -(int) (*rec)->name[i];
 }
```

A longer table name now compares greater than the key, which is how
`symparse_compare()` orders a name and its prefix in the index, so the
search finds only the exact name.

### Repro

`bash repro.sh [nethack-source-dir]` builds the game and links a small
harness against its object files. The harness looks up every name in
`loadsyms[]` with `match_sym()`, and passes every non-UTF8 `S_` line of
`dat/symbols` to it as `parse_sym_line()` does. On `a9f93bb00` it lists
the four names above and the eight misapplied lines, then:

```
  DECgraphics  S_lava: \xe0                       -> sets S_lavawall
  AmigaFont    S_lava: '*'                        -> sets S_lavawall
8 of 551 S_ lines in dat/symbols set a different symbol
=== BUG SEEN: match_sym() resolved a name to a longer name that begins with it
```

and exits 0. With `proposed-fix.patch` it prints `0 of 196` and `0 of 551`,
then `=== not seen: every name resolved to itself`, and exits 1.
