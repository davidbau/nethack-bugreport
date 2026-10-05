**Title:** Starting the tutorial reports "untrustworthy null shkp" and "Program in disorder!"

**Version:** `NetHack-5.0` head
[`193d5396a`](https://github.com/NetHack/NetHack/tree/193d5396a) (2026-09-30),
built clean from git with the stock Linux hints. Introduced by
[`055caaffb`](https://github.com/NetHack/NetHack/commit/055caaffb) ("revisit
shop_keeper() readiness", 2026-05-31), so it is not in the base the other
reports here were recorded against. Bug 28 ([28-hiders-unhidden-on-level-load](../28-hiders-unhidden-on-level-load/))
is another consequence of the same commit.

The ready-to-file issue text, with the symptom, cause and fix, is in
[`ISSUE.md`](ISSUE.md). This page adds the recordings, repro details and
supporting facts.

### Symptom details

The check is compiled in while `NH_DEVEL_STATUS` is not `NH_STATUS_RELEASED`
or `NH_STATUS_POSTRELEASE`; the branch is at `NH_STATUS_WIP`, so every build
from git shows it and a release build would not. A large box gets 0-3 random
items (0-5 if generated locked), so about three games in four show it. The
`paniclog` gets one line per occurrence:

```
5.0.1-0 20261001 143515 1026 -: impossible untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)
```

The Castle's chest and either chest in Vlad's Tower do the same when generated
with random contents.

Recordings from the head, seed 1, answering **y** to the tutorial:

- [Head: the three messages four times, steps 4 to 15](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session.json#step=4)
- [Head with the patch: straight into the tutorial at step 4](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/27-shkready-null-room/session-fixed.json#step=4)

Both draw the same 3,493 random numbers in the same order. The recorder is the
head plus this repository's four recording patches (seed and clock, RNG log,
screen capture), which do not touch game logic.

### Cause details

`dat/tut-1.lua` places the box with scripted contents:

```lua
des.object({ coord = { 41,6 }, id = "large box", broken = true, trapped = false,
             contents = function(obj)
                des.object({ id = "secret door detection", class = "/", spe = 30 }); end
});
```

`create_object()` (`sp_lev.c`) calls `delete_contents(otmp)` for
`SP_OBJ_CONTAINER` before running `contents`; `obfree()` then does
`shkp = shop_keeper(*u.ushops)` with `level_status` at
`(making 1, loading 0, shkready 0, ready 0)`. Full stack (from a backtrace hook
in `shop_keeper()`, the same every time): `shop_keeper` <- `obfree` <-
`delete_contents` <- `create_object` <- `lspo_object` <- (Lua) <-
`load_special` (tut-1.lua) <- `makemaz` <- `makelevel` <- `mklev` <-
`goto_level` <- `deferred_goto` <- `maybe_do_tutorial`.

### Fix

[`proposed-fix.patch`](proposed-fix.patch) (diff in `ISSUE.md`) applies to the
head. It is on the
[`fix-shkready-null-room`](https://github.com/davidbau/NetHack/tree/fix-shkready-null-room)
branch (this change alone) and the
[`teleport-bugfixes`](https://github.com/davidbau/NetHack/tree/teleport-bugfixes)
branch of `davidbau/NetHack`.

### Repro

By hand, on Linux:

```
git clone -b NetHack-5.0 https://github.com/NetHack/NetHack.git && cd NetHack
(cd sys/unix && sh setup.sh hints/linux.501)
make fetch-lua && make install          # installs into ./playground
HOME=$(mktemp -d) ./playground/nethack
```

Name `tester` (not `player`, which asks again), `y` and Enter to pick a
character, space twice, then `y` to the tutorial. If nothing shows, the box
had no random items; start another game.

Scripted:

```
bash bugs/27-shkready-null-room/repro.sh                # clone and build the head
bash bugs/27-shkready-null-room/repro.sh ~/src/NetHack  # or build a given checkout
GAMES=20 bash bugs/27-shkready-null-room/repro.sh
```

It plays `GAMES` (default 10) new games as above, each with an empty `HOME`,
counts occurrences in `paniclog`, and exits 0 if any game shows the message.
With 8 games: head 6 of 8 (x1, x5, x1, x1, x2, x1), ending
`=== the message appeared in 6 of 8 games`; patched 0 of 8. All 16 entered
the tutorial.

In wizard mode, `#wizloaddes castle` (or `tower1`) on the head showed the
message 1 of 5 tries each; patched, 0 of 6 tries each.
