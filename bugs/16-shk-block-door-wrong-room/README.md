**Title:** A shopkeeper at his post never blocks a diagonal move through a broken shop door

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(`shk.c:5817` and `shk.c:5858` there; checked 2026-09-25); recorded against
`NetHack/NetHack@16ff59115` (5.0.0 as released). The test is in the oldest
`shk.c` in the git history (January 2002). Fix branch:
[`bugreport/16-shk-block-door-wrong-room`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/16-shk-block-door-wrong-room).

### Symptom

Through a broken or doorless shop door, `block_door()` should stop a hero who
owes money stepping diagonally out onto the door, and `block_entry()` an
invisible or riding hero, or one carrying a pick-axe or mattock, stepping
diagonally in, with `<Shopkeeper> blocks your way!`. Neither fires.

Seed 5, wizard mode, Valkyrie, Dlvl 2, Siirt's used armor dealership; the door
is made broken with `^W` `broken door`. Leaving ([`session.json`](session.json)):
[the hero with an unpaid long sword stands diagonally inside the door next to Siirt](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=80),
[steps onto the door ("Please pay before leaving.")](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=81)
and [`You stole 20 zorkmids worth of merchandise.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=85)
Entering ([`session-entry.json`](session-entry.json)): after
[`"Will you please leave your pick-axe outside?"`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry.json#step=38)
the hero [steps diagonally past Siirt into the shop](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry.json#step=57).

### Cause

[`src/shk.c:5787-5823`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5787-L5823),
and the same test in `block_entry()`
([`shk.c:5836-5838`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5836-L5838)):

```c
    int roomno = *in_rooms(x, y, SHOPBASE);
    if (roomno < 0 || !IS_SHOP(roomno))
        return FALSE;
```

`in_rooms()` returns `levl[][].roomno` values
([`hack.c:3498-3523`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3498-L3523)),
which carry `ROOMOFFSET` (3,
[`include/mkroom.h:91`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/mkroom.h#L91)),
but `IS_SHOP()` takes a `svr.rooms[]` index
([`shk.c:56`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L56)).
The rest of each function uses `roomno` correctly (compared with `*u.ushops`,
passed to `shop_keeper()`). Other callers subtract first:
[`inside_shop()`, `shk.c:573`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L573),
[`clear_no_charge_obj()`, `shk.c:367-368`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L367-L368),
[`move_update()`, `hack.c:3609`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3609).

Here the shop is `svr.rooms[8]` of 9 rooms, so the test reads `svr.rooms[11]`,
not a shop, and the callers in `test_move()`
([`hack.c:1141`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L1141),
[`hack.c:1209`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L1209))
allow the move. `crawl_destination()`
([`hack.c:4095`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4095))
also calls `block_door()`. The `roomno < 0` test never fires either: with no
shop `in_rooms()` returns an empty string, so `roomno` is 0; the fix must not
index `svr.rooms[-3]`.

### Fix

In both functions, as `inside_shop()` does:

```diff
-    if (roomno < 0 || !IS_SHOP(roomno))
+    if (roomno < ROOMOFFSET || !IS_SHOP(roomno - ROOMOFFSET))
         return FALSE;
```

[`proposed-fix.patch`](proposed-fix.patch); fixed
[`shk.c:5796`](https://github.com/davidbau/NetHack/blob/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5/src/shk.c#L5796),
[`shk.c:5837`](https://github.com/davidbau/NetHack/blob/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5/src/shk.c#L5837),
[commit b96713d84](https://github.com/davidbau/NetHack/commit/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5).
Since `*in_rooms(x, y, SHOPBASE)` only returns shop rooms,
`if (roomno < ROOMOFFSET) return FALSE;` alone would behave the same. Players
will notice shopkeepers blocking where they did not before.

### Repro

`repro.sh` re-records both sessions and exits 0 when both moves succeed, 1
when both are blocked. Patched:
[`Siirt blocks your way!` leaving](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-fixed.json#step=81)
and
[entering](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry-fixed.json#step=57).
Stock and patched recordings are identical up to the refused move (step 80 and
step 56).
