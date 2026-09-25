# After the first revisit, subroom squares can belong to the wrong subroom: a shop stops being a shop

Subrooms (the rooms-inside-rooms that themed rooms such as "Twin businesses",
"Fake Delphi" and "Nesting rooms" create) can come back from a level save in
different slots of `svr.rooms[]` from the ones they were created in. The map
still points at the old slots. So from the first time the hero leaves such a
level and comes back, every square inside a subroom may be read as belonging
to a different subroom.

When one of the subrooms is a shop, the player can see it. In the recorded
game, on the second visit to Dlvl 17:

- the hero steps into the armor shop they were welcomed into a moment ago and
  gets no greeting; `:` shows `You see here a bronze plate mail.` where the
  first visit said `(for sale, 533 zorkmids)`; picking it up gives
  `e - a bronze plate mail.`, not `(unpaid, 533 zorkmids)`. The goods are free.
- the hero steps into an ordinary room nested in the middle of the map and is
  told `This shop seems to be untended.`

Nothing needs to be done to the level between the two visits except leave it
and come back.

It needs a level where subrooms exist in two or more parent rooms and were not
created in left-to-right order of their parents. That is rare in ordinary
games. We level-teleported through Dlvl 2-20 on 900 seeds, about 18,000
generated levels in all, and found three such levels. Only one of them had a
shop among its subrooms, and that is the level recorded here. When it does
happen, it changes play, not just messages.

The affected code is `rest_room()` in `src/mkroom.c`. It is present at the
`NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/13-subroom-roomno-stale-on-restore`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/13-subroom-roomno-stale-on-restore)
holds one proposed commit, verified by rebuild.

Severity: low overall (rare), but gameplay-affecting when it occurs: shop
goods can be taken without being billed, and a room that is not a shop acts
like a deserted one.

## Watch it happen

Seed 895, wizard mode, Valkyrie. The session level-teleports down one level at
a time to Dlvl 17 and magic-maps it. Dlvl 17 has a "Twin businesses" pair
(armor shop and weapon shop) at the far left and a "Nesting rooms" room in the
middle. Then it teleports the hero into the armor shop and into the middle
subroom, visits Dlvl 18, returns, and repeats both visits with the same keys.

- [**First visit, stock**: "Welcome to Ayancik's used armor dealership!"](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=138),
  then [`bronze plate mail (for sale, 533 zorkmids)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=140)
- [**Second visit, stock**: no greeting, `You see here a bronze plate mail.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=183),
  [`e - a bronze plate mail.` (picked up free)](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=184),
  and in the ordinary middle room
  [`This shop seems to be untended.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=198)
- [**Second visit, patched**: "Welcome again to Ayancik's used armor dealership!"](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=181),
  [`(for sale, 533 zorkmids)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=183),
  [`e - a bronze plate mail (unpaid, 533 zorkmids).`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=185)
  (the session then drops it again, so nothing is stolen), and
  [nothing in the middle room](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=198)

The level teleports and the `^T` teleports are only there to reach the level
quickly and land on the same squares both times; a player who walks down the
stairs, leaves and comes back gets the same effect, because it is caused by the
level being written out and read back.

## What the code is doing

Main rooms and subrooms share one array. `gs.subrooms` is the upper half of
`svr.rooms[]`
([`decl.c:1169`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/decl.c#L1169)):

```c
    gs.subrooms = &svr.rooms[MAXNROFROOMS + 1];
```

`topologize()` stamps each square of a room or subroom with its slot
([`mklev.c:1603`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L1603)):

```c
    int roomno = (int) ((croom - svr.rooms) + ROOMOFFSET);
```

and `in_rooms()`, which the shop code and many other callers use to ask what
room a square is in, turns that number straight back into a slot
([`hack.c:3505-3508`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3505-L3508)):

```c
#define goodtype(rno) \
    (!typewanted                                                   \
     || (typefound = svr.rooms[rno - ROOMOFFSET].rtype) == typewanted  \
     || (typewanted == SHOPBASE && typefound > SHOPBASE))
```

So a square's room is whatever currently occupies the slot it was stamped with.

Subrooms are given slots in the order they are created
([`add_subroom()`, `mklev.c:322`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L322)).
After all the rooms are made, `makelevel()` calls `sort_rooms()`
([`mklev.c:1301`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L1301),
[`mklev.c:210-228`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L210-L228)),
which sorts the *main* rooms by `lx` and renumbers their squares. It leaves the
subrooms where they are, which is correct at that point: the parents' `sbrooms[]`
pointers still point at them, and their squares still carry their slots.

The save walks the sorted main rooms and writes each one's subrooms after it
([`mkroom.c:844-871`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkroom.c#L844-L871)).
The restore reads them back into consecutive slots from a counter
([`mkroom.c:875-906`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkroom.c#L875-L906)):

```c
staticfn void
rest_room(NHFILE *nhfp, struct mkroom *r)
{
    short i;

    Sfi_mkroom(nhfp, r, "room-mkroom");

    for (i = 0; i < r->nsubrooms; i++) {
        r->sbrooms[i] = &gs.subrooms[gn.nsubroom];
        rest_room(nhfp, &gs.subrooms[gn.nsubroom]);
        gs.subrooms[gn.nsubroom++].resident = (struct monst *) 0;
    }
}
```

That is: the restored slot order is the sorted-parent order, not the creation
order. The map's `roomno` values are read back unchanged. Whenever the two
orders differ, the first restore moves subrooms to new slots and leaves the map
pointing at the old ones. Later saves and restores keep the new order, so the
mismatch lasts for the rest of the game.

## The case recorded here

At creation, Dlvl 17 of seed 895 has four subrooms. The "Nesting rooms" room
in the middle of the map was made first, the "Twin businesses" pair at the far
left second:

| slot | before the first save | after the first restore |
|---|---|---|
| 0 | middle nested room, x=40 (ordinary) | armor shop, x=4 |
| 1 | room nested inside it, x=45 (ordinary) | weapon shop, x=10 |
| 2 | armor shop, x=4 | middle nested room, x=40 (ordinary) |
| 3 | weapon shop, x=10 | room nested inside it, x=45 (ordinary) |

The armor shop's squares are stamped with slot 2, so after the restore they
belong to an ordinary room. `costly_spot()` then finds no shop there
([`shk.c:5350-5363`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5350-L5363)),
no price is shown, and pickup adds nothing to the bill. The middle room's
squares are stamped with slot 0, which is now the armor shop's record. Entering
it looks like entering a shop, but the shopkeeper is registered as the resident
of slot 2, so `shop_keeper()` finds nobody and `u_entered_shop()` calls
`deserted_shop()`
([`shk.c:721-747`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L721-L747)).

The table was read from a build with a logging line added to `save_rooms()`
and `rest_rooms()`, not from the recordings themselves.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): put each subroom back into the
slot it was created in. The creation slot is already in the saved record:
`do_room_or_subroom()` sets `croom->roomnoidx = (croom - svr.rooms)`
([`mklev.c:259`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L259)),
and `sort_rooms()` only reads it for main rooms. `rest_room()` reads the whole
`struct mkroom`, including that field, but does not use it.

```c
    for (i = 0; i < r->nsubrooms; i++) {
        struct mkroom tmproom;
        int sidx;

        /* Put each subroom back into the slot it was created in. ... */
        rest_room(nhfp, &tmproom);
        sidx = tmproom.roomnoidx - (MAXNROFROOMS + 1);
        if (sidx < 0 || sidx >= MAXNROFROOMS) {
            impossible("rest_room: bad subroom index %d", sidx);
            sidx = gn.nsubroom;
        }
        gs.subrooms[sidx] = tmproom;
        gs.subrooms[sidx].resident = (struct monst *) 0;
        r->sbrooms[i] = &gs.subrooms[sidx];
        gn.nsubroom++;
    }
```

Fixed code:
[`mkroom.c:875-902`](https://github.com/davidbau/NetHack/blob/34928fe03b426cee973c6aaebabbed9112e4f722/src/mkroom.c#L875-L902)
· diff:
[commit 34928fe03](https://github.com/davidbau/NetHack/commit/34928fe03b426cee973c6aaebabbed9112e4f722).

The save format does not change, so existing save and bones files load with
the fix. A level that an unpatched game has already restored once is also put
right, because its map and its `roomnoidx` values both still refer to the
creation slots. Nested subrooms work because the recursive call fills in
`tmproom.sbrooms[]` with pointers into `gs.subrooms[]` before the copy.

**Alternatives.** `rest_rooms()` could instead remap the subroom squares on
the map after reading, the way `sort_rooms()` remaps main-room squares. That
touches every square and does the same job. Or `save_rooms()` could write the
subrooms in slot order, but that changes the save file layout.

## Verification

Stock and patched builds, same seed, same datetime, same keystream:

| | stock | patched |
|---|---|---|
| steps recorded | 200 | 200 |
| RNG entries | 58,042 | 58,220 |
| identical through | step 180 (57,879 RNG entries) | step 180 |
| second visit, entering the armor shop | no greeting | "Welcome again to Ayancik's used armor dealership!" |
| `:` on the plate mail | `You see here a bronze plate mail.` | `... (for sale, 533 zorkmids).` |
| picking it up | `e - a bronze plate mail.` | `e - a bronze plate mail (unpaid, 533 zorkmids).` |
| entering the middle subroom | `This shop seems to be untended.` | nothing |

The two recordings are identical up to the moment the hero reaches the shop
again. After that they differ only because a shopkeeper who knows the hero
is in his shop acts differently. Reverting the source and rebuilding reproduced
the stock recording byte-for-byte, which is the control: the patched run
differed because of the patch, not because of the rebuild.

`repro.sh` re-records `session.json` and exits 0 when it sees the stock
behaviour, 1 when it sees the patched behaviour.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced as a random-number divergence on a revisited level: C
made a "monster standing in a shop" roll for a monster in an ordinary closet.
The JavaScript port restored subrooms in creation order, so its closet was
still a closet.
