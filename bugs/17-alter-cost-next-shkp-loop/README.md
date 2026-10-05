**Title:** `alter_cost()` can loop forever: it passes the current shopkeeper back to `next_shkp()`

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(`shk.c:3267` there; checked 2026-09-25); identical in
`NetHack/NetHack@16ff59115` (5.0.0 as released). Fix branch:
[`bugreport/17-alter-cost-next-shkp-loop`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/17-alter-cost-next-shkp-loop).

### Symptom

Latent: we have not made it happen in a game, and the bundle has no recording
of the hang. If two shopkeepers on a level have non-empty bills and the object
whose price changes (enchanting worn unpaid armor or a wielded unpaid weapon,
recharging, remove curse, blessing unpaid water, naming an artifact) is on the
bill of the one later in `fmon`, `alter_cost()` never returns and the game
hangs.

### Cause

[`src/shk.c:3236-3256`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3236-L3256):

```c
    for (shkp = next_shkp(fmon, TRUE); shkp; shkp = next_shkp(shkp, TRUE))
        if ((bp = onbill(obj, shkp, TRUE)) != 0) {
```

`next_shkp()`
([`shk.c:214-231`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L214-L231))
starts its search at its argument, so for a live shopkeeper with a bill it
returns that shopkeeper again; if `obj` is not on his bill, the loop never
advances. Every other walk in `shk.c` steps past the current one, with
`shkp->nmon` (lines
[962](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L962-L963),
[970](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L970-L971),
[1019](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1019-L1020),
[1095](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1095-L1096),
[1209](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1209-L1210),
[1335](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1335-L1336),
[1761](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1761-L1762),
[1801](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1801-L1802),
[3217](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3217-L3218),
[3278](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3278-L3279),
[4860](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L4860-L4861),
[5993](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5993-L5994))
or a saved next pointer
([2519](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2519-L2520),
[2556](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2556-L2557)).
The next walk, in `unpaid_cost()` (line 3278), is the same loop written
correctly. Callers: `recharge()` (`read.c:797`, `832`),
`seffect_enchant_armor()` (`read.c:1247`, `1283`), `seffect_remove_curse()`
(`read.c:1565`), `chwepon()` (`wield.c:966`, `1028`), `oname()`
(`do_name.c:410`), `H2Opotion_dip()` (`potion.c:1576`),
`bill_dummy_object()` (`mkobj.c:735`).

**Reachability.** A bill is normally emptied when the hero leaves the shop
(`u_left_shop()` -> `rob_shop()` -> `setpaid()`), except via the early return
when the shopkeeper is not in his shop
([`shk.c:594-596`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L594-L596)).
Moving a resident shopkeeper out with `rloc()` goes through `rloc_to_core()`,
which calls `make_angry_shk()` and empties the bill
([`teleport.c:1734-1740`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/teleport.c#L1734-L1740)).
In wizard mode, a wand of teleportation at the shopkeeper (it also took stock,
so he returned angry) and a wished teleportation trap on his post (he never
stepped on it) both failed. Not examined: other ways out of a shop, bones,
variants. `bill_dummy_object()`'s `alter_cost(dummy, -cost)` would hang if
`addtobill()` declined the dummy while some shopkeeper had a bill, which seems
to need the same precondition.

### Fix

```diff
-    for (shkp = next_shkp(fmon, TRUE); shkp; shkp = next_shkp(shkp, TRUE))
+    for (shkp = next_shkp(fmon, TRUE); shkp;
+         shkp = next_shkp(shkp->nmon, TRUE))
```

[`proposed-fix.patch`](proposed-fix.patch); fixed
[`shk.c:3246-3247`](https://github.com/davidbau/NetHack/blob/e5aad0a4e13b71f8e5f350ad3c13403352158fa3/src/shk.c#L3246-L3247),
[commit e5aad0a4e](https://github.com/davidbau/NetHack/commit/e5aad0a4e13b71f8e5f350ad3c13403352158fa3).

### Repro

`repro.sh` compiles and runs [`repro.c`](repro.c), which holds `next_shkp()`
and the `alter_cost()` loop with cut-down structures, on two billed
shopkeepers:

```
upstream, object on Jonzac's bill (first):  Jonzac   after 1 step
upstream, object on Ayancik's bill (second): still on Jonzac after 1000 steps -- infinite loop
proposed, object on Ayancik's bill (second): Ayancik  after 2 steps
```

It then checks your tree's `alter_cost()`: exit 0 for the upstream loop step,
1 for the patched form.

The single-bill case is unchanged. Seed 5, wizard mode, Dlvl 2, Siirt's armor
shop: wearing an unpaid chain mail (100 zorkmids) and reading blessed enchant
armor gives
[`Siirt's chain mail glows silver for a while.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session.json#step=76)
and
[`f - a +4 chain mail (being worn)  153 zorkmids`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session.json#step=79),
the same
[with the patch](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session-fixed.json#step=79);
the recordings differ only in `shk.c` line numbers in RNG annotations.
