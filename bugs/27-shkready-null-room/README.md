# Starting the tutorial reports "untrustworthy null shkp" and "Program in disorder!"

On a development build of the current `NetHack-5.0` branch, a new player who
answers **y** to "Do you want a tutorial?" usually gets this before the
tutorial starts:

```
Entering the tutorial.--More--
untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)--More--
Program in disorder!  (Saving and reloading may fix this problem.)--More--
Please report these messages to devteam@nethack.org.--More--
```

and the same three messages again for each further occurrence: once for every
random item the tutorial's large box was generated with. A large box gets 0-3
random items (0-5 if it was generated locked), so about three games in four
show it, up to five times in a row. The game then continues normally; nothing
is damaged. The `paniclog` gets one line per occurrence:

```
5.0.1-0 20261001 143515 1026 -: impossible untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)
```

It is the first thing a new player sees after choosing the tutorial on any build
of the branch from git, because the check that raises it is compiled in while
`NH_DEVEL_STATUS` is not `NH_STATUS_RELEASED` or `NH_STATUS_POSTRELEASE`, and
the branch is at `NH_STATUS_WIP` (5.0.1 work in progress). A release build
would not show it.

The same thing happens when the Castle's chest, or either of the chests in
Vlad's Tower, is generated with random contents, since those levels also give
a container scripted contents.

**Present at:** the `NetHack-5.0` head
[`193d5396a`](https://github.com/NetHack/NetHack/tree/193d5396a) (2026-09-30),
built clean from git with the stock Linux hints. **Introduced by:**
[`055caaffb`](https://github.com/NetHack/NetHack/commit/055caaffb) ("revisit
shop_keeper() readiness", 2026-05-31), so it is not in the base this
repository's other reports were recorded against.

## Watch it happen

Recorded from the `NetHack-5.0` head (`193d5396a`), seed 1, a new game that
answers **y** to the tutorial question:

- [**The head**: four times through the three messages, steps 4 to 15](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session.json#step=4)
- [**The head with the patch**: straight into the tutorial at step 4](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session-fixed.json#step=4)

The two recordings draw the same 3,493 random numbers in the same order; the
patch changes only the messages.  The recorder is the head with the four
recording patches this repository uses (deterministic seed and clock, the RNG
log, and screen capture), rebuilt for the head; they do not touch game logic.

## Reproducing it

By hand, on Linux:

```
git clone -b NetHack-5.0 https://github.com/NetHack/NetHack.git && cd NetHack
(cd sys/unix && sh setup.sh hints/linux.501)
make fetch-lua && make install          # installs into ./playground
HOME=$(mktemp -d) ./playground/nethack
```

With no config file (the empty `HOME`), a new game asks:

1. `Who are you?` -- type `tester` and Enter (not `player`, which the game treats
   as a generic name and asks again);
2. `Shall I pick character's race, role, gender and alignment for you? [ynaq]`
   -- `y`, then Enter to accept the character;
3. two `--More--` prompts (the intro text and the welcome) -- space, space;
4. `Do you want a tutorial?` -- `y`.

`Entering the tutorial.` is then followed by the messages above in about three
games in four. If a game shows nothing, its box had no random items; quit and
start another.

Scripted:

```
bash bugs/27-shkready-null-room/repro.sh                # clone and build the head
bash bugs/27-shkready-null-room/repro.sh ~/src/NetHack  # or build a given checkout
GAMES=20 bash bugs/27-shkready-null-room/repro.sh
```

That builds a clean checkout with the stock Linux hints, plays `GAMES` (default
10) new games exactly as above, each in its own process with an empty `HOME`,
and counts the occurrences in `paniclog`. It exits 0 if any game shows the
message. A run on the head:

```
=== Starting 8 new games and choosing the tutorial
  game  1: in the tutorial: yes  'untrustworthy null shkp' x1
            paniclog: 5.0.1-0 20261001 143515 1026 -: impossible untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)
  game  2: in the tutorial: yes  'untrustworthy null shkp' x0
  game  3: in the tutorial: yes  'untrustworthy null shkp' x5
  game  4: in the tutorial: yes  'untrustworthy null shkp' x1
  game  5: in the tutorial: yes  'untrustworthy null shkp' x1
  game  6: in the tutorial: yes  'untrustworthy null shkp' x2
  game  7: in the tutorial: yes  'untrustworthy null shkp' x1
  game  8: in the tutorial: yes  'untrustworthy null shkp' x0
=== the message appeared in 6 of 8 games
```

## What the code is doing

The call stack when the `impossible()` fires (taken from a build with a
backtrace hook in `shop_keeper()`; the same in every occurrence):

```
shop_keeper       shk.c      the readiness check
obfree            shk.c      shkp = shop_keeper(*u.ushops)
delete_contents   shk.c
create_object     sp_lev.c   o->containment & SP_OBJ_CONTAINER
lspo_object       sp_lev.c   des.object({ ..., contents = function ... })
  (Lua)
load_special      sp_lev.c   tut-1.lua
makemaz           mkmaze.c
makelevel         mklev.c
mklev             mklev.c
goto_level        do.c
deferred_goto     do.c
maybe_do_tutorial allmain.c
```

`dat/tut-1.lua` places a large box with scripted contents:

```lua
des.object({ coord = { 41,6 }, id = "large box", broken = true, trapped = false,
             contents = function(obj)
                des.object({ id = "secret door detection", class = "/", spe = 30 }); end
});
```

`mksobj()` fills the box with random contents when it is made, so
`create_object()` empties it before running the `contents` function:

```c
    /* container */
    if (o->containment & SP_OBJ_CONTAINER) {
        delete_contents(otmp);
```

`delete_contents()` passes each item to `obfree()`, which, after checking for a
shopkeeper with the item on a bill, does:

```c
    /* sanity check, in case obj is on bill but not marked 'unpaid' */
    if (!shkp)
        shkp = shop_keeper(*u.ushops);
```

`u.ushops` is the list of shops the hero is in; outside a shop it is empty, so
this is `shop_keeper(0)`. 055caaffb added a check at the end of
`shop_keeper()` for a null result while the level is still being made:

```c
    shkp = (rmno >= ROOMOFFSET) ? svr.rooms[rmno - ROOMOFFSET].resident : 0;
    if (shkp) {
        ...
    } else {
        if (!level_status.shkready) {
            ...
            impossible("untrustworthy null shkp; level_status.shkready"
                        " is FALSE (%d, %d, %d, %d)", ...);
```

The check is meant for a room whose `resident` may not have been set yet. But
it also fires when `rmno` names no room at all (`rmno < ROOMOFFSET`: 0 for no
room, 1 and 2 for shared walls), where the null result does not depend on the
level's progress and is always correct. While a level is being made
(`level_status` is `(making 1, loading 0, shkready 0, ready 0)`), every item
`obfree()` deletes with the hero outside a shop triggers it.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): only check readiness when `rmno`
names a room.

```c
-    } else {
+    } else if (rmno >= ROOMOFFSET) {
+        /* only a lookup of an actual room can be premature; for rmno
+           that names no room (0 from an empty u.ushops or in_rooms()),
+           a null result is correct no matter how far along the level is */
         if (!level_status.shkready) {
```

This keeps the check for the case it was added for, and fixes every caller that
can pass a non-room (`*u.ushops`, `*in_rooms(...)`), rather than only
`obfree()`. Making `obfree()` skip the call when `*u.ushops` is 0 would also
silence this occurrence, but would leave the other callers.

The patch applies to the `NetHack-5.0` head; it is also on the
[`fix-shkready-null-room`](https://github.com/davidbau/NetHack/tree/fix-shkready-null-room)
branch (this change alone) and the
[`teleport-bugfixes`](https://github.com/davidbau/NetHack/tree/teleport-bugfixes)
branch of `davidbau/NetHack`.

## Verification

`repro.sh` on the head and on the head with the patch, 8 games each:

| | head `193d5396a` | head + patch |
|---|---|---|
| games showing the message | 6 of 8 (x1, x5, x1, x1, x2, x1) | 0 of 8 |
| tutorial entered | 8 of 8 | 8 of 8 |

In wizard mode, `#wizloaddes castle` (or `tower1`) on the head shows the same
message when the chest gets random contents (1 of 5 tries each in our runs);
with the patch, 0 of 6 tries each.

## Credit

Found by AI agents collaborating on a JavaScript port of NetHack 5.0, under
human direction, with the analysis, reproducer and patch from Claude Opus 5.5.
It turned up while smoke-testing a separate change in the tutorial, and was
then confirmed on an unmodified build of the `NetHack-5.0` head.
