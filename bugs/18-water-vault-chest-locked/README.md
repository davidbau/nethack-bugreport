**Title:** The water-surrounded vault's escape chest is meant to be unlocked when the escape item is glass, but can be locked

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/18-water-vault-chest-locked`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/18-water-vault-chest-locked).

**Symptom**

In the `Water-surrounded vault` themed room, one chest holds an escape item.
When that item is glass, `themerms.lua` means to leave the chest unlocked,
because kicking a locked chest open is likely to shatter it
(`dokick.c:436-439`). The chest instead keeps its random lock state (locked
80% of the time). With a crystal wand as the escape item, `#loot` says:

```
Hmmm, the chest turns out to be locked.
```

This happens in about 1 vault in 28 (the item is glass only when it is one
of the two wands and its shuffled appearance is "glass" or "crystal"), and
then the chest is locked 4 times in 5.

- [Stock 5.0.0: `#loot` finds the chest locked](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/18-water-vault-chest-locked/session.json#step=22)
  (step 23: `You see here a locked chest.`)
- [Patched: the chest opens and holds a crystal wand](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/18-water-vault-chest-locked/session-fixed.json#step=23)

**Cause**

`dat/themerms.lua`
([lines 791-802](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/dat/themerms.lua#L791-L802)):

```lua
            if itmcls[ "material" ] == "glass" then
                  -- explicitly force chest to be unlocked
                  box = des.object({ id = "chest", coord = chest_spots[1],
                                    olocked = "no" });
```

`des.object()` reads the key `locked`
([`sp_lev.c:3642`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L3642)),
not `olocked` (the `struct obj` field name), so `tmpobj.locked` stays `-1`.
`create_object()` applies it only when it is 0 or 1
([`sp_lev.c:2286-2287`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L2286-L2287)),
so the chest keeps `mksobj()`'s `otmp->olocked = !!(rn2(5))`
([`mkobj.c:1012`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkobj.c#L1012)).

**Fix**

```diff
                   box = des.object({ id = "chest", coord = chest_spots[1],
-                                    olocked = "no" });
+                                    locked = false });
```

Commit [50dd50e46](https://github.com/davidbau/NetHack/commit/50dd50e46b16113f73e839e5ee5b3ad6fe6f2348);
also `proposed-fix.patch`.

The value must be the Lua boolean `false`: a string does not work, because
`get_table_boolean()`
([`nhlua.c:1079-1104`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/nhlua.c#L1079-L1104))
returns a string's position in its list (`"no"` is 3, `"false"` is 1), which
`create_object()` ignores or inverts; see bug 33
([`../33-lua-boolean-strings-inverted/`](../33-lua-boolean-strings-inverted/)).
In a debug build, `locked = "no"` and `locked = "false"` both left this chest
locked; `locked = false` and `locked = 0` unlocked it.

**Repro**

```
bash bugs/18-water-vault-chest-locked/repro.sh
```

It sets `THEMERM='Water-surrounded vault'` (the wizard-mode themed-room
debug hook, read by `nh.debug_themerm()`), re-records
[`session.json`](session.json) with seed 13 (`^F`, `^T` onto the escape
chest at x=40, y=14, `#loot`, `:`), and checks for the "turns out to be
locked" message. It exits 0 if the chest is locked (bug present), 1 if the
`#loot` menu opens (patched), 2 if the scenario did not reach the chest.
`THEMERM` is stored under `recorded_with.env` in the session; replaying
without it generates a different level.

The patched recording used the same binary with only `themerms.lua`
replaced. Both runs make the same 2,841 RNG calls, identical step by step
(`mksobj()` still rolls `rn2(5)`); only the last two screens differ.
Restoring the stock file reproduced `session.json` byte for byte.
