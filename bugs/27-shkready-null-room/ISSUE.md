**Title:** Starting the tutorial: impossible "untrustworthy null shkp; level_status.shkready is FALSE"

**Version:** `NetHack-5.0` head `193d5396a` (2026-09-30), 5.0.1-0 Work-in-progress, built from git on Linux with `sys/unix/hints/linux.501`. Introduced by 055caaffb ("revisit shop_keeper() readiness").

**Steps to reproduce**

1. Build the `NetHack-5.0` head: `(cd sys/unix && sh setup.sh hints/linux.501) && make fetch-lua && make install`
2. Start a new game with no config file: `HOME=$(mktemp -d) ./playground/nethack`
3. Name `tester`; `y` to "Shall I pick ... for you?", Enter to accept; space, space for the two `--More--`.
4. `y` to "Do you want a tutorial?"

**What happens**

In about three games in four:

```
Entering the tutorial.--More--
untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)--More--
Program in disorder!  (Saving and reloading may fix this problem.)--More--
Please report these messages to devteam@nethack.org.--More--
```

repeated once for each random item the tutorial's large box (tut-1.lua, at <41,6>) was generated with, up to 5 times. The game then continues normally. In wizard mode, `#wizloaddes castle` or `#wizloaddes tower1` shows the same whenever the chest gets random contents.

**Cause**

`create_object()` empties a container that has scripted `contents` (`delete_contents()` -> `obfree()` on each random item). `obfree()` does `shkp = shop_keeper(*u.ushops)`, which is `shop_keeper(0)` when the hero is not in a shop. The readiness check added in 055caaffb fires for any null result while `level_status.shkready` is FALSE, including `rmno < ROOMOFFSET`, where null is always correct; during makelevel() that is every such item.

Backtrace: `shop_keeper` <- `obfree` <- `delete_contents` <- `create_object` <- `lspo_object` <- (Lua) <- `load_special` <- `makemaz` <- `makelevel` <- `mklev` <- `goto_level` <- `deferred_goto` <- `maybe_do_tutorial`.

**Suggested fix** (src/shk.c, `shop_keeper()`): only check readiness when `rmno` names a room.

```diff
-    } else {
+    } else if (rmno >= ROOMOFFSET) {
+        /* only a lookup of an actual room can be premature; for rmno
+           that names no room (0 from an empty u.ushops or in_rooms()),
+           a null result is correct no matter how far along the level is */
         if (!level_status.shkready) {
```

A recording of a new game on the head (seed 1) can be stepped through at https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session.json#step=4 and the same game with the patch at https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session-fixed.json#step=4 (the two draw identical random numbers; only the messages differ). With the patch, 0 of 8 scripted tutorial starts show the message (6 of 8 without it). A scripted reproducer, the full analysis and the patch are at https://github.com/davidbau/nethack-bugreport/tree/main/bugs/27-shkready-null-room; the change alone is on https://github.com/davidbau/NetHack/tree/fix-shkready-null-room.
