**Title:** Lua boolean options given as strings are inverted: `locked = "true"` makes an unlocked chest

**Version:** `NetHack-5.0` tip `a9f93bb00`. The code is unchanged since
`fd55d9118` ("Use lua for special level files", 2019).

**Symptom**

Every boolean field of `des.monster()`, `des.object()`, `des.trap()` and
the rest also accepts "true", "false", "yes" or "no", and those strings come
out wrong. A des-file run with `#wizloaddes` that creates 8 chests for each
form of `des.object({ id = "chest", locked = V })` reports:

```
  locked = true     -> 8/8 chests locked
  locked = false    -> 0/8 chests locked
  locked = "true"   -> 0/8 chests locked
  locked = "false"  -> 8/8 chests locked
  locked = "yes"    -> 6/8 chests locked
  locked = "no"     -> 7/8 chests locked
```

No shipped `dat/*.lua` passes a string to a boolean field. The one string
boolean there, `olocked = "no"` in `themerms.lua`, uses a key
`des.object()` does not read; the fix for that (bug 18,
`18-water-vault-chest-locked`) uses `locked = false`, not `"no"`.

**Cause**

`src/nhlua.c:1078-1086`:

```c
    /* static const int boolstr2i[] = { TRUE, FALSE, TRUE, FALSE, -1 }; */
    ...
    if (ltyp == LUA_TSTRING) {
        ret = luaL_checkoption(L, -1, NULL, boolstr);
        /* nhUse(boolstr2i[0]); */
```

`luaL_checkoption()` returns the index of the string in
`{ "true", "false", "yes", "no" }`, so "true" gives 0, "false" 1, "yes" 2
and "no" 3. The table that maps indexes to `TRUE`/`FALSE` was never used
and was later commented out to quiet compiler warnings. What the wrong
values do depends on the caller: a plain truth test (`invisible`,
`buried`, `lit`) sees "true" as false and the other three as true; a 1-bit
field (`peaceful`, `asleep`, `female`) keeps the low bit, so "true" and
"yes" give 0; fields that accept only 0 or 1 and otherwise stay random
(`locked`, `trapped`, sp_lev.c:2287) invert "true"/"false" and ignore
"yes"/"no".

**Fix**

```diff
-    /* static const int boolstr2i[] = { TRUE, FALSE, TRUE, FALSE, -1 }; */
+    static const int boolstr2i[] = { TRUE, FALSE, TRUE, FALSE, -1 };
...
-        ret = luaL_checkoption(L, -1, NULL, boolstr);
-        /* nhUse(boolstr2i[0]); */
+        ret = boolstr2i[luaL_checkoption(L, -1, NULL, boolstr)];
```

This uses the mapping the code already declares; `luaL_checkoption()`
raises a Lua error for any other string, so the index is always 0-3.

**Repro**

`bash repro.sh [srcdir]` builds the `NetHack-5.0` head (or the given tree)
and runs the script above with `#wizloaddes` in a wizard-mode game. On the tip it prints the table above
and `=== BUG: locked="true" makes unlocked chests and locked="false"
locked ones` (exit 0). With the patch every string form matches its Lua
boolean (8, 0, 8, 0, 8, 0 locked) and it prints `=== OK: string booleans
match the Lua booleans` (exit 1).
