**Title:** `des.map` with rows of different lengths reads past the end of the map string

**Version:** `NetHack-5.0` tip `a9f93bb00`. The indexing came in with the Lua
level loader (`fd55d9118`, "Use lua for special level files") and moved into
`mapfrag_get()` in `c9b21e36a`.

**Symptom**

A `des.map` (or `replace_terrain`/`selection.match` mapfragment) whose rows
differ in length gets the wrong terrain in every row after a short one, and
the last rows come from heap bytes past the end of the map string; a byte
that `splev_chr2typ()` maps to terrain puts that terrain on the level, so the
result can vary between builds and runs. Loading this with `#wizloaddes` in
an ASan build:

```lua
des.map([[
---
|.|
|...........|
---
]]);
```

```
ERROR: AddressSanitizer: heap-buffer-overflow ...
    #0 in mapfrag_get src/sp_lev.c:271
    #1 in lspo_map src/sp_lev.c:6290
0x... is located 0 bytes after 32-byte region
```

The shipped `dat/*.lua` maps are all rectangular, so stock levels are not
affected; user and variant level files are.

**Cause**

`mapfrag_fromstr()` (src/sp_lev.c:227) keeps the map as the string it was
given and takes the width from the widest row (`str_lines_maxlen()`, line 236).
`mapfrag_get()` (line 271) reads cell `(x, y)` with

```c
    return splev_chr2typ(mf->data[y * (mf->wid + 1) + x]);
```

which assumes every row is `wid` characters plus a newline. In the example
the string is 26 bytes and `wid` is 13, so row 1 is read from offset 14
(inside row 2) and rows 2 and 3 from offsets 28 and 42.

**Fix**

`mapfrag_fromstr()` copies the rows into a buffer of `hei * (wid + 1)`
bytes, padding each short row with spaces:

```diff
+    tmps = mf->data;
+    dst = mf->data =
+        (char *) alloc((unsigned) (mf->hei * (mf->wid + 1) + 1));
+    for (src = tmps; *src; ) {
+        char *s1 = strchr(src, '\n');
+        int len = s1 ? (int) (s1 - src) : (int) strlen(src);
+
+        (void) memcpy(dst, src, len);
+        (void) memset(dst + len, ' ', mf->wid - len);
+        dst += mf->wid;
+        *dst++ = '\n';
+        src += len + (s1 ? 1 : 0);
+    }
+    *dst = '\0';
+    free(tmps);
```

This fixes all three callers (`lspo_map()`, `lspo_replace_terrain()`,
`l_selection_match()`) at once; bounding the index in `mapfrag_get()` would
stop the over-read but leave the later rows shifted.

**Repro**

`bash repro.sh [nethack-src]` builds with `WANT_ASAN=1` and runs
`#wizloaddes` on the script above in a pty-driven wizard-mode game.

On the tip it prints the ASan report above and `BUG CONFIRMED --
mapfrag_get() read past the end of the ragged map` (exit 0); with
`proposed-fix.patch`, `not seen -- the ragged map loaded with no ASan report`
(exit 1).
