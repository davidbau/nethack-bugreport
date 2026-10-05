**Title:** Two Lua callbacks on one event run in an order that changes from run to run

**Version:** `NetHack/NetHack@16ff59115` (5.0.0 as released, Lua 5.4.8) and
the `NetHack-5.0` tip (Lua 5.5.1); the patch applies to both.

### Symptom

Callbacks registered with `nh.callback()` for one event run one after another,
and any can stop the rest by returning false. With two or more on one event,
the order changes between runs of the same binary with the same save file. The
bytes saved for Lua variables also differ between two saves of the same state
(the table read back is the same).

This is latent in the shipped game: the only registrant, the tutorial, puts one
function on `cmd_before` and one on `end_turn`. Anything that registers a
second function on an event gets an order that varies.

### Cause

`dat/nhcore.lua` keys an event's callbacks by function name and runs them with
`pairs()`:

```lua
   nh_lua_variables[cbname][fn] = true;          -- nh_callback_set
...
   for k, v in pairs(nh_lua_variables[cbname]) do   -- nh_callback_run
      if (not _G[k](table.unpack{...})) then
         return false;
```

`pairs()` visits string keys in hash-slot order, and Lua seeds its string hash
per state: `luai_makeseed()` (`lstate.c` in 5.4, `lauxlib.c` in 5.5) mixes the
time and some addresses unless the embedding program defines its own. NetHack
does not. `table_stringify()` in `dat/nhlib.lua`, which
`get_variables_string()` uses to save `nh_lua_variables`, has the same
`pairs()` loop.

### Fix

Run callbacks in sorted order of their names, and have `table_stringify()`
write keys in sorted order:

```diff
    for k, v in pairs(nh_lua_variables[cbname]) do
+      names[#names + 1] = k;
+   end
+   table.sort(names);
+   for _, k in ipairs(names) do
       if (not _G[k](table.unpack{...})) then
```

The stored form (name -> `true`) is unchanged, so existing saves read back the
same. Registration order would need a sequence number in the saved value, a
save-content change left to the DevTeam. Defining `luai_makeseed` as a constant
would also fix the order, but only for NetHack's own interpreter build, and it
makes Lua's string hashing predictable. Full diff:
[`proposed-fix.patch`](proposed-fix.patch).

With the patch, eight callbacks on `cmd_before` run alphabetically and
`get_variables_string()` gives the same string on every run. The tutorial's
`cmd_before` callback still works: `S` does nothing in the tutorial, and asks
"Really save?" outside it.

### Repro

`bash bugs/15-lua-callback-order/repro.sh` builds a standalone interpreter from
the recorder build's `lib/lua-5.4.8` and runs [`order.lua`](order.lua) five
times; it builds a table shaped like the callback table and prints the
`pairs()` order. It exits 0 if the runs disagree:

```
delta,epsilon,alpha,zeta,eta,theta,gamma,beta
epsilon,beta,gamma,zeta,eta,delta,alpha,theta
alpha,gamma,zeta,delta,eta,beta,theta,epsilon
theta,delta,epsilon,beta,alpha,eta,zeta,gamma
beta,theta,eta,alpha,zeta,gamma,delta,epsilon
5 distinct orders in 5 runs
```
