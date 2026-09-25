# The water-surrounded vault's "forced unlocked" escape chest can be locked

The `Water-surrounded vault` themed room is a closed 2x2 room ringed by
moat, holding four chests and an undead monster. One chest always holds an
escape item (a scroll or ring of teleportation, or a wand of teleportation
or digging), so that a hero who ends up inside is not stuck for good. When
that item is made of glass, `themerms.lua` means to make its chest
unlocked, because the other way into a locked chest, kicking it, is likely
to shatter a glass item inside:

```lua
            -- If the escape item is made of glass or crystal, make sure that
            -- the chest isn't locked so that kicking it to gain access to its
            -- contents won't be necessary; otherwise retain lock state from
            -- random creation.
```

It does not work. The chest keeps its random lock state, and chests are
generated locked 80% of the time. In the recording below the escape item is a
crystal wand, and `#loot` on its chest says:

```
Hmmm, the chest turns out to be locked.
```

The cause is a key name: the script passes `olocked = "no"`, and
`des.object()` reads the key `locked`. The unknown key is silently
ignored.

It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/18-water-vault-chest-locked`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/18-water-vault-chest-locked)
holds one proposed commit, verified by re-recording.

Severity: low. The case is uncommon (the escape item is glass only when it
is one of the two wands and that wand's shuffled appearance is "glass" or
"crystal", about 1 vault in 28, and the chest is then locked 4 times in 5),
and a hero with a blade or an unlocking tool can still open the chest
without kicking it. But it is exactly the case the code was written to
handle, and the comment says it is handled.

## Watch it happen

- [**Stock 5.0.0**: `#loot` finds the chest locked](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/18-water-vault-chest-locked/session.json#step=22)
  (step 23 then shows `You see here a locked chest.`)
- [**With the patch applied**: the same chest opens, and holds a crystal wand](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/18-water-vault-chest-locked/session-fixed.json#step=23)

The scenario, in wizard mode: seed 13, with the environment variable
`THEMERM='Water-surrounded vault'` set. `THEMERM` is the DevTeam's own
debugging hook for themed rooms (read by `nh.debug_themerm()` in
`themerms.lua`, wizard mode only); it makes about half of the level's rooms
this vault, so the scenario does not need a seed search through ordinary
play, where the vault is rare. The hero magic-maps the level (`^F`),
teleports onto the escape chest at x=40, y=14 (`^T`), and uses `#loot` and
then `:`. The session file records `THEMERM` under `recorded_with.env`,
because it is not part of the session format; replaying without it
generates a different level.

## Reproducing it

```
bash bugs/18-water-vault-chest-locked/repro.sh
```

That sets `THEMERM`, re-records [`session.json`](session.json) through the
recorder, and checks for the "turns out to be locked" message. It exits 0 if
the chest is locked (bug present), 1 if the `#loot` menu opens instead
(patched), and 2 if the scenario did not reach the chest.

## What the code is doing

The vault, in `dat/themerms.lua`
([lines 791-802](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/dat/themerms.lua#L791-L802)):

```lua
            local itm = obj.new(escape_items[math.random(#escape_items)]);
            local itmcls = itm:class()
            local box
            if itmcls[ "material" ] == "glass" then
                  -- explicitly force chest to be unlocked
                  box = des.object({ id = "chest", coord = chest_spots[1],
                                    olocked = "no" });
            else
                  -- accept random locked/unlocked state
                  box = des.object({ id = "chest", coord = chest_spots[1] });
            end;
```

`itm:class()` reports `objects[].oc_material`
([`nhlobj.c:222`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/nhlobj.c#L222)),
and wand materials are shuffled together with wand appearances
([`o_init.c:141`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L141),
[`o_init.c:339`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L339)),
so a wand of teleportation or digging is glass in any game where it looks
like the "glass" or "crystal" wand
([`objects.h:1449`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/objects.h#L1449),
[`objects.h:1454`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/include/objects.h#L1454)).
The glass branch is reached as intended.

`des.object()` then reads the lock state from the key `locked`
([`sp_lev.c:3642`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L3642)):

```c
        tmpobj.locked = get_table_boolean_opt(L, "locked", -1);
```

There is no `olocked` key (`olocked` is the name of the `struct obj` field),
so `tmpobj.locked` stays `-1`, and `create_object()` applies it only when it
is 0 or 1
([`sp_lev.c:2286-2287`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/sp_lev.c#L2286-L2287)):

```c
    if (o->locked == 0 || o->locked == 1) {
        otmp->olocked = o->locked;
```

The chest keeps the lock state `mksobj()` gave it,
`otmp->olocked = !!(rn2(5))`
([`mkobj.c:1012`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkobj.c#L1012)),
which is locked 80% of the time. Kicking a chest shatters glass contents
([`dokick.c:436-439`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dokick.c#L436-L439)),
which is the outcome the comment was guarding against.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): use the key `des.object()`
reads, with a Lua boolean.

```lua
                  box = des.object({ id = "chest", coord = chest_spots[1],
                                    locked = false });
```

Diff:
[commit 50dd50e46](https://github.com/davidbau/NetHack/commit/50dd50e46b16113f73e839e5ee5b3ad6fe6f2348).

**Why `false` and not `"no"`.** The obvious one-word edit, `olocked` to
`locked` keeping `"no"`, does not work either. `get_table_boolean()`
([`nhlua.c:1079-1104`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/nhlua.c#L1079-L1104))
accepts the strings `"true"`, `"false"`, `"yes"` and `"no"`, but returns
their *position* in its list (`luaL_checkoption()`), so `"no"` comes back as
3 and `"false"` as 1. The table that would map positions to values,
`boolstr2i`, is present but commented out. A value of 3 fails the
`== 0 || == 1` test above and is ignored, so the chest would still be random;
we checked this in a debug build, where `locked = "no"` and
`locked = "false"` both left this chest locked and `locked = false` and
`locked = 0` both unlocked it. No shipped `.lua` file passes a string
boolean today (this line was the only one, and it used the wrong key), so the
string path is latent rather than live. Restoring `boolstr2i` in
`get_table_boolean()` would be a reasonable separate cleanup, but it is not
needed for this fix.

## Verification

Recorded with the same seed, datetime, keystream and `THEMERM` against the
stock data files and against the patched `themerms.lua`. The fix is a data
file change, so the patched run used the same recorder binary with only
`themerms.lua` replaced in its install directory.

| | stock | patched |
|---|---|---|
| steps recorded | 24 | 24 |
| RNG entries | 2,841 | 2,841 |
| RNG identical, step by step | yes | yes |
| `#loot` on the escape chest | `Hmmm, the chest turns out to be locked.` | `Do what with the chest?` |
| `:` look | `You see here a locked chest.` | contents include `a crystal wand` |

The RNG stream is identical because `mksobj()` still makes its `rn2(5)` roll;
the fix only overrides its result. Only the last two screens differ.
Restoring the stock `themerms.lua` in the same install directory and
recording again reproduced `session.json` byte for byte, which is the
control that the difference comes from the patch.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from
Claude Opus 5.5. It surfaced while the port's special-level Lua bindings were
being checked against `sp_lev.c`: the script passes a key that no C code
reads.
