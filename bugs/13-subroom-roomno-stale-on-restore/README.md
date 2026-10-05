**Title:** After a level is reloaded, subroom squares can belong to the wrong subroom: a shop stops being a shop

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(checked 2026-09-25); recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/13-subroom-roomno-stale-on-restore`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/13-subroom-roomno-stale-on-restore).

### Symptom

Seed 895, wizard mode, Valkyrie. Dlvl 17 has a "Twin businesses" pair (armor
and weapon shop) at the far left and a "Nesting rooms" room in the middle. On
the first visit the armor shop works:
["Welcome to Ayancik's used armor dealership!"](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=138),
[`bronze plate mail (for sale, 533 zorkmids)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=140).
After leaving to Dlvl 18 and coming back:
[no greeting, `You see here a bronze plate mail.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=183),
[`e - a bronze plate mail.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=184)
(picked up free), and in the ordinary middle room
[`This shop seems to be untended.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session.json#step=198)
Walking down the stairs and back gives the same result; the level teleports
in the session only reach the level quickly.

It needs subrooms in two or more parent rooms, not created in left-to-right
order of their parents. Level-teleporting through Dlvl 2-20 on 900 seeds
(about 18,000 levels) found three such levels; one had a shop among its
subrooms, the one recorded here.

### Cause

`topologize()` stamps each square with its room's slot in `svr.rooms[]`
([`mklev.c:1603`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L1603)), and `in_rooms()` maps it straight back ([`hack.c:3505-3508`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/hack.c#L3505-L3508)).
Subrooms share `svr.rooms[]` as its upper half ([`decl.c:1169`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/decl.c#L1169)) and get slots in creation order ([`add_subroom()`, `mklev.c:322`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L322)).
`sort_rooms()` ([`mklev.c:1301`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L1301), [`mklev.c:210-228`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L210-L228)) reorders only main rooms. `save_rooms()`
writes each sorted main room followed by its subrooms ([`mkroom.c:844-871`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkroom.c#L844-L871)), and
`rest_room()` puts them into consecutive slots ([`src/mkroom.c:875-906`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkroom.c#L875-L906)):

```c
        r->sbrooms[i] = &gs.subrooms[gn.nsubroom];
        rest_room(nhfp, &gs.subrooms[gn.nsubroom]);
```

The map's `roomno` values are not changed, so the squares now name other
subrooms, and the mismatch persists for the rest of the game. On Dlvl 17 the
armor shop moves from slot 2 to 0 and the middle nested room from 0 to 2
(read from a build with logging in `save_rooms()`/`rest_rooms()`). The shop's
squares then belong to an ordinary room, so `costly_spot()` finds no shop
([`shk.c:5350-5363`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5350-L5363)); the middle room's squares read as the armor shop, whose
shopkeeper is resident of slot 2, so `u_entered_shop()` calls
`deserted_shop()` ([`shk.c:721-747`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L721-L747)).

### Fix

Restore each subroom into its creation slot, which is already saved in
`roomnoidx` (set by `do_room_or_subroom()`, [`mklev.c:259`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mklev.c#L259)):

```diff
-        r->sbrooms[i] = &gs.subrooms[gn.nsubroom];
-        rest_room(nhfp, &gs.subrooms[gn.nsubroom]);
-        gs.subrooms[gn.nsubroom++].resident = (struct monst *) 0;
+        rest_room(nhfp, &tmproom);
+        sidx = tmproom.roomnoidx - (MAXNROFROOMS + 1);
+        if (sidx < 0 || sidx >= MAXNROFROOMS) {
+            impossible("rest_room: bad subroom index %d", sidx);
+            sidx = gn.nsubroom;
+        }
+        gs.subrooms[sidx] = tmproom;
+        gs.subrooms[sidx].resident = (struct monst *) 0;
+        r->sbrooms[i] = &gs.subrooms[sidx];
+        gn.nsubroom++;
```

The save format does not change, and a level already restored once by an
unpatched game is put right, since its map and `roomnoidx` both still refer to
creation slots. Full diff: [`proposed-fix.patch`](proposed-fix.patch);
[commit 34928fe03](https://github.com/davidbau/NetHack/commit/34928fe03b426cee973c6aaebabbed9112e4f722)
([`mkroom.c:875-902`](https://github.com/davidbau/NetHack/blob/34928fe03b426cee973c6aaebabbed9112e4f722/src/mkroom.c#L875-L902)).
Alternatives: remap subroom squares after reading, as `sort_rooms()` does for
main rooms, or save subrooms in slot order (changes the save layout).

### Repro

`repro.sh` re-records `session.json` and exits 0 on the stock behaviour, 1 on
the patched behaviour. Stock and patched recordings are identical through
step 180. Patched second visit:
["Welcome again to Ayancik's used armor dealership!"](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=181),
[`(for sale, 533 zorkmids)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=183),
[`e - a bronze plate mail (unpaid, 533 zorkmids).`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=185)
(then dropped), and
[nothing in the middle room](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/13-subroom-roomno-stale-on-restore/session-fixed.json#step=198).
