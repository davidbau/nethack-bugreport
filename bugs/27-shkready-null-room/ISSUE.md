**Title:** Starting the tutorial: impossible "untrustworthy null shkp; level_status.shkready is FALSE"

**Version:** `NetHack-5.0` head `193d5396a` (5.0.1-0 WIP, built from git with `hints/linux.501`). Introduced by 055caaffb ("revisit shop_keeper() readiness").

**Symptom.** Answering `y` to "Do you want a tutorial?" in a new game usually gives, before the tutorial starts:

```
untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)--More--
Program in disorder!  (Saving and reloading may fix this problem.)--More--
Please report these messages to devteam@nethack.org.--More--
```

once for each random item in tut-1.lua's large box (0 to 5 of them; 6 of 8 test games showed it). `#wizloaddes castle` or `tower1` does the same when the chest gets random contents. The game then carries on normally.

**How it came about.** `shop_keeper(rmno)` returns `rooms[rmno - ROOMOFFSET].resident`. While a level is still being made or read in by `getlev()`, that pointer may not be set yet, so a lookup made too early wrongly answers "no shopkeeper" (no shop, no bill). 055caaffb added `level_status.shkready` so this can be detected. Any null result while `shkready` is FALSE now raises an `impossible()` in development builds, to flag code that asks too soon.

The check is too wide. A null result is only suspect when `rmno` names a room. When `rmno < ROOMOFFSET` (0 for "not in a room", 1 or 2 for a shared wall), null is the right answer whatever state the level is in. Many callers do pass such values, `shop_keeper(*u.ushops)` and `shop_keeper(*in_rooms(...))`, and do so routinely.

Here it is `obfree()`, which looks for the shopkeeper of the hero's current shop with `shop_keeper(*u.ushops)`. When the hero is in no shop, that is `shop_keeper(0)`. During the tutorial's `makelevel()`, `create_object()` empties the scripted box of its random contents (`delete_contents()` -> `obfree()`), while `shkready` is still FALSE. Each deleted item trips the check:

`shop_keeper` <- `obfree` <- `delete_contents` <- `create_object` <- `lspo_object` <- (tut-1.lua) <- `makelevel` <- `goto_level` <- `deferred_goto` <- `maybe_do_tutorial`

**Fix** (src/shk.c, `shop_keeper()`): apply the readiness check only when `rmno` names a room, i.e. `rmno >= ROOMOFFSET && !level_status.shkready`.

```diff
-    } else {
-        if (!level_status.shkready) {
+    } else if (rmno >= ROOMOFFSET && !level_status.shkready) {
+        /* only a lookup of an actual room can be premature; for rmno
+           that names no room (0 from an empty u.ushops or in_rooms()),
+           a null result is correct no matter how far along the level is */
```

(the body of the old inner `if` moves out one level, unchanged)

This keeps the diagnostic for the case it was written for, a room whose `resident` is not set yet. It also fixes every caller that can pass a non-room, not just `obfree()`. Making `obfree()` skip the call when `*u.ushops` is 0 would hide this one instance but leave the others. With the patch, 0 of 8 tutorial starts show the message (6 of 8 without it), and the random numbers drawn are unchanged.

**Repro and recordings.** A scripted reproducer (`repro.sh`), and recordings of the same game with and without the patch, are at https://github.com/davidbau/nethack-bugreport/tree/main/bugs/27-shkready-null-room. The change alone is on https://github.com/davidbau/NetHack/tree/fix-shkready-null-room.
