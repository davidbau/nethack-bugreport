# Two Lua callbacks on one event run in an order that changes from run to run

NetHack lets Lua code register functions to run on game events through
`nh.callback()`. The callbacks registered for one event are run one after
another, and any of them can stop the rest by returning false. With two or more
on the same event, which one runs first is not fixed: it changes from one run
of the game to the next, on the same binary, with the same save file.

The same thing makes the bytes written for Lua variables into a save file
differ between two saves of the same game state. The table read back is the
same; only the order inside the saved string changes.

This is latent in the shipped game. `nh.callback()` accepts four event names,
and the only registrant is the tutorial, with one function on `cmd_before` and
one on `end_turn`. Anything that registers a second function on an event
(a variant, a mod, or the DevTeam adding another use) inherits an order that
varies.

## Reproducing it

```
bash bugs/15-lua-callback-order/repro.sh
```

That builds a standalone interpreter from the Lua the recorder build embeds
(`lib/lua-5.4.8`) and runs [`order.lua`](order.lua) five times. The script
builds a table shaped like the callback table (function name -> `true`) and
prints the order `pairs()` visits it in. It exits 0 if the runs disagree:

```
delta,epsilon,alpha,zeta,eta,theta,gamma,beta
epsilon,beta,gamma,zeta,eta,delta,alpha,theta
alpha,gamma,zeta,delta,eta,beta,theta,epsilon
theta,delta,epsilon,beta,alpha,eta,zeta,gamma
beta,theta,eta,alpha,zeta,gamma,delta,epsilon
5 distinct orders in 5 runs
```

The Lua at the current `NetHack-5.0` tip (5.5.1) behaves the same way.

## What the code is doing

`dat/nhcore.lua` keeps an event's callbacks in a table keyed by function name
and runs them with `pairs()`:

```lua
function nh_callback_set(cb, fn)
   ...
   nh_lua_variables[cbname][fn] = true;
end

function nh_callback_run(cb, ...)
   ...
   for k, v in pairs(nh_lua_variables[cbname]) do
      if (not _G[k](table.unpack{...})) then
         return false;
      end
   end
   return true;
end
```

`pairs()` visits a table's string keys in the order of their hash slots. Lua
randomizes its string hash per state: `luai_makeseed()` (`lstate.c` in 5.4,
`lauxlib.c` in 5.5) mixes the time and a few addresses, relying on address
space layout randomization, unless the embedding program defines its own.
NetHack does not, so the slot order, and with it the callback order, is new on
every run.

`table_stringify()` in `dat/nhlib.lua`, which `get_variables_string()` uses to
write `nh_lua_variables` into the save file, walks tables with the same
`pairs()` loop.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): run the callbacks in sorted order of
their names, and have `table_stringify()` write keys in sorted order.

The stored form is unchanged (function name -> `true`), so saves written before
the change read back the same. Sorting by name is the smallest change that
makes the order fixed. Running callbacks in registration order would be more
natural, but it needs the stored value to carry a sequence number, which is a
change to what is saved; that is a choice for the DevTeam.

Defining `luai_makeseed` to a constant would also fix the order, but only for
the interpreter NetHack builds, and it would also make Lua's string hashing
predictable, which is what the seed is there to prevent.

## Verification

With the patch applied, a script that loads `nhlib.lua` and `nhcore.lua`,
registers eight callbacks on `cmd_before`, runs the event and prints
`get_variables_string()` gives the same callback order (alphabetical) and the
same saved string on every run. Built from the `NetHack-5.0` tip with the
patch, the tutorial's `cmd_before` callback still runs: in the tutorial `S`
does nothing (the callback refuses `save`), while the same keys outside the
tutorial ask "Really save?". The patch applies to both the pinned base
(`16ff59115`) and the `NetHack-5.0` tip.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis and patch from Claude Opus 5.5.
It surfaced because the port must reproduce the C game's behavior exactly, and
the saved Lua variables were the one part of a save file that differed between
two saves of the same game.
