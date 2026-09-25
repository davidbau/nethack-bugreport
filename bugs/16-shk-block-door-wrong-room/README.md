# A shopkeeper at his post never blocks a diagonal move through a broken shop door

When a shop's door is broken (or is a doorless doorway), diagonal moves through
it are allowed, and two functions in `shk.c` exist to have the shopkeeper stop
the two diagonal moves he cares about:

- `block_door()`: a hero who owes money stepping diagonally out of the shop
  onto the door;
- `block_entry()`: an invisible or riding hero, or one carrying a pick-axe or
  mattock, stepping diagonally off the door into the shop.

Both print `<Shopkeeper> blocks your way!` and refuse the move. In practice
neither fires. The recorded game shows both moves going through while the
shopkeeper stands at his post beside the door:

- with an unpaid long sword, the hero steps diagonally past Siirt onto the
  broken door (`"wizard!  Please pay before leaving."`) and walks off with it
  (`You stole 20 zorkmids worth of merchandise.`);
- with a pick-axe, after Siirt has said `"Will you please leave your pick-axe
  outside?"`, the hero steps diagonally past him into the shop.

With the fix, both moves are met with `Siirt blocks your way!`.

The two functions pass a room number to `IS_SHOP()` without removing the
`ROOMOFFSET` that room numbers on the map carry, so they test the room three
slots further along in `svr.rooms[]`. Unless that room happens to be a shop
too, they give up before looking at the shopkeeper.

The affected code is `block_door()` and `block_entry()` in `src/shk.c`. It is
present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(`shk.c:5817` and `shk.c:5858` there), checked 2026-09-25, and was recorded
against `NetHack/NetHack@16ff59115`, NetHack 5.0.0 as released. The same test is
already in the oldest revision of `shk.c` in the DevTeam's git history
(January 2002). The branch
[`bugreport/16-shk-block-door-wrong-room`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/16-shk-block-door-wrong-room)
holds one proposed commit, verified by rebuild.

Severity: low. It needs a broken or doorless shop door, which the player can
cause (kicking it in, force bolt, striking) and which stays broken until the
shopkeeper repairs it. It makes leaving a shop with unpaid goods easier than
intended, and lets a pick-axe into the shop. The usual consequences of theft
(angry shopkeeper, Kops) still follow.

## Watch it happen

Seed 5, wizard mode, Valkyrie, Dlvl 2: Siirt's used armor dealership, door in
the west wall. In both sessions the hero teleports onto the door and turns it
into a broken door with a wizard-mode terrain wish (`^W` `broken door`), which
stands in for kicking it in without making Siirt ask for damages.

Leaving with an unpaid item ([`session.json`](session.json)):

- [the hero, with an unpaid long sword, stands diagonally inside the door next to Siirt at his post](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=80)
- [**stock**: the diagonal move succeeds, "Please pay before leaving."](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=81),
  then [`You stole 20 zorkmids worth of merchandise.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session.json#step=85)
- [**patched**: `Siirt blocks your way!`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-fixed.json#step=81)

Entering with a pick-axe ([`session-entry.json`](session-entry.json)):

- [`"Will you please leave your pick-axe outside?"`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry.json#step=38)
- [**stock**: the hero steps diagonally past Siirt into the shop](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry.json#step=57)
- [**patched**: `Siirt blocks your way!`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/16-shk-block-door-wrong-room/session-entry-fixed.json#step=57)

## What the code is doing

```c
/* used in domove to block diagonal shop-exit */
/* x,y should always be a door */
boolean
block_door(coordxy x, coordxy y)
{
    int roomno = *in_rooms(x, y, SHOPBASE);
    struct monst *shkp;

    if (roomno < 0 || !IS_SHOP(roomno))
        return FALSE;
    if (!IS_DOOR(levl[x][y].typ))
        return FALSE;
    if (roomno != *u.ushops)
        return FALSE;

    shkp = shop_keeper((char) roomno);
    ...
```

Source: [`src/shk.c:5787-5823`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5787-L5823).
`block_entry()` has the same test
([`src/shk.c:5836-5838`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5836-L5838)).

`in_rooms()` returns `levl[][].roomno` values
([`hack.c:3498-3523`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3498-L3523)),
which are offset:

```c
#define ROOMOFFSET  3 /* (levl[x][y].roomno - ROOMOFFSET) gives svr.rooms[]
                       * index, for inside-squares and non-shared boundaries */
```

([`include/mkroom.h:91`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/mkroom.h#L91)),
while `IS_SHOP()` takes a `svr.rooms[]` index
([`shk.c:56`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L56)):

```c
#define IS_SHOP(x) (svr.rooms[x].rtype >= SHOPBASE)
```

The rest of each function treats `roomno` correctly as an offset value: it is
compared with `*u.ushops` and passed to `shop_keeper()`, which subtracts
`ROOMOFFSET` itself. Only the `IS_SHOP()` test is off by three. Every other
place that feeds a room number to `IS_SHOP()` subtracts first:
[`inside_shop()`, `shk.c:573`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L573),
[`clear_no_charge_obj()`, `shk.c:367-368`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L367-L368),
and [`move_update()`, `hack.c:3609`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3609).

In the recorded game the shop is `svr.rooms[8]` on a level with 9 rooms, so
both functions test `svr.rooms[11]`, which is past the end of the level's rooms
and not a shop. The tests at `shk.c:5796` and `5837` return `FALSE`, and their
callers in `test_move()`
([`hack.c:1141`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L1141),
[`hack.c:1209`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L1209))
allow the diagonal move through the broken door. (`crawl_destination()`,
[`hack.c:4095`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L4095),
also calls `block_door()`, for crawling out of water and for travel.)

The `roomno < 0` test also never fires: `in_rooms()` returns an empty string
when there is no shop, so `roomno` is 0, not negative. That case is harmless
today (`shop_keeper(0)` returns null), but it matters for the fix, which must
not index `svr.rooms[-3]`.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch), in both functions:

```c
-    if (roomno < 0 || !IS_SHOP(roomno))
+    if (roomno < ROOMOFFSET || !IS_SHOP(roomno - ROOMOFFSET))
         return FALSE;
```

which is the form `inside_shop()` already uses. Fixed code:
[`shk.c:5796`](https://github.com/davidbau/NetHack/blob/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5/src/shk.c#L5796),
[`shk.c:5837`](https://github.com/davidbau/NetHack/blob/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5/src/shk.c#L5837)
· diff:
[commit b96713d84](https://github.com/davidbau/NetHack/commit/b96713d8427714b7eb2dcd46feb828bfe9d2c8a5).

**An alternative:** `*in_rooms(x, y, SHOPBASE)` only ever returns a room whose
type is a shop, so the `IS_SHOP()` test is redundant once `roomno` is known to
be non-zero. `if (roomno < ROOMOFFSET) return FALSE;` alone would behave the
same. The version above keeps the test and makes it correct.

The fix makes the shopkeeper block more often than the stock game does. That
is what the functions are for, but it is a behaviour change players will
notice.

## Verification

Stock and patched builds, same seed, same datetime, same keystreams:

| | stock | patched |
|---|---|---|
| **leaving** (`session.json`): steps | 87 | 87 |
| RNG entries | 5,806 | 5,357 |
| identical through | step 80 (5,357 RNG entries) | step 80 |
| diagonal move onto the door | succeeds, "Please pay before leaving." | `Siirt blocks your way!` |
| next step west | `You stole 20 zorkmids worth of merchandise.` | into the wall, nothing |
| **entering** (`session-entry.json`): steps | 60 | 60 |
| RNG entries | 5,348 | 5,312 |
| identical through | step 56 (5,312 RNG entries) | step 56 |
| diagonal move off the door | hero is inside the shop with the pick-axe | `Siirt blocks your way!` |

The patched runs use no RNG after the refused move, because a blocked move
takes no time. Reverting the source and rebuilding reproduced both stock
recordings byte-for-byte, which is the control: the patched runs differed
because of the patch, not because of the rebuild.

`repro.sh` re-records both sessions and exits 0 when it sees both moves
succeed, 1 when it sees both blocked.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced during a line-by-line comparison of `shk.c` with the
port: the two `IS_SHOP()` calls were the only ones in the file whose room
number had not had `ROOMOFFSET` removed.
