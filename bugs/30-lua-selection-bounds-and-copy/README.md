**Title:** Lua selections: `|`, `&`, `~`, `-` drop points set after a clear; cloning a selection holding -1 overflows the heap

**Version:** `NetHack-5.0` tip `a9f93bb00`. The stale bounds come from 5e9ed7a29 ("Some selection optimizations"); the `!= 0` test from deec8317c (issue #1467).

**Symptom**

(a) In a level or theme-room script:

```lua
local s = selection.new()
s:set(5,5); s:set(5,5,0); s:set(20,6)
local u = s | selection.new()   -- u:numpoints() is 0; s:numpoints() is 1
```

Clearing a point that was never set does the same. `selection.filter_mapchar(sel, typ, -1)` sets each point to `rn2(2)`, so its result loses points when combined. This is #1467 again, for selections not made by `selection.match()`.

(b) `w:set(0,0,-1); c = w:clone(); c:set(70,15)` writes past an 8-byte heap block. AddressSanitizer reports a heap-buffer-overflow in `selection_setpoint` on a block allocated by `dupstr` in `l_selection_clone`.

**Cause**

(a) `selection_setpoint()` (selvar.c:191) widens the cached bounds only while `!sel->bounds_dirty`. Once a point has been cleared, later points are not added to the bounds. `l_selection_and/or/xor/sub` (nhlsel.c:289, 314, 340, 369) loop over `rect_bounds(sela->bounds, selb->bounds)` without recalculating, so they skip those points. The test at selvar.c:203, `sel->map[...] != 0`, reads the raw byte, which is `value + 1`. An unset point is 1, so clearing it marks the selection dirty, which the comment says it should not.

(b) A point with value -1 is stored as byte 0 (selvar.c:207). `l_selection_push_new`, `l_selection_push_copy` and `l_selection_clone` (nhlsel.c:104, 121, 146), and `selection_clone` (selvar.c:70), copy the map with `dupstr()`, which stops at that byte. The copy is shorter than `COLNO * ROWNO`, and later reads and writes go past its end.

**Fix**

```diff
-    if (c && !sel->bounds_dirty) {
+    if (c) {
 ...
-    } else if (sel->map[sel->wid * y + x] != 0) {
+    } else if (selection_getpoint(x, y, sel)) {
```

and a `selection_dupmap()` that `memcpy`s `COLNO * ROWNO + 1` bytes, used in the four places that used `dupstr()`. With the bounds widened on every set, they always contain every point, and `bounds_dirty` only means they may be too large. The operators then need no recalculation. See `proposed-fix.patch`.

**Repro**

`bash repro.sh [nethack-source-dir]` builds with `USE_ASAN=1`, starts a wizard-mode game and runs `selbug_a.lua` and `selbug_b.lua` with `#wizloadlua`. On the tip:

```
  (a1) s has 1 point(s); s | selection.new() has 0: BUG, point dropped
  (a2) s has 1 point(s); s | selection.new() has 0: BUG, point dropped
  (b) BUG, AddressSanitizer:
      AddressSanitizer: heap-buffer-overflow on address 0x50200000c146
        #0 selection_setpoint selvar.c:207
      ... is located 1262 bytes after 8-byte region
        #2 dupstr alloc.c:246
        #3 l_selection_clone nhlsel.c:146
=== verdict: BUG SEEN                                   (exit 0)
```

With the patch: both unions have 1 point, the clone has 2, no ASan report, `no bug seen` (exit 1).
