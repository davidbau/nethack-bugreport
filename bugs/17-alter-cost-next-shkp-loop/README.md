# `alter_cost()` can loop forever: it passes the current shopkeeper back to `next_shkp()`

`alter_cost()` updates the price on a shop bill when an unpaid object becomes
worth more: enchanting worn unpaid armor, enchanting a wielded unpaid weapon,
recharging, removing a curse, blessing unpaid water, naming an artifact. It
walks the shopkeepers who have bills to find the one holding the object. Its
loop step hands the current shopkeeper back to `next_shkp()`, and
`next_shkp()` starts its search *at* the monster it is given. So if the first
shopkeeper with a bill does not have the object on it, the loop gets the same
shopkeeper back on every step and never ends. The game hangs.

**We have not been able to make this happen in a game.** It needs two
shopkeepers on the level with non-empty bills at once, with the object on the
bill of the one later in the monster list. Normal play settles a bill as soon
as the hero leaves the shop (see "Reachability"). So this is reported as a
latent defect: a one-line loop error that turns into a hang as soon as
anything lets two bills coexist. This bundle has no recording of the hang.
Its `repro.c` runs the loop itself, and its recordings show that the fix
leaves the normal case unchanged.

The affected code is `alter_cost()` in `src/shk.c`. It is present at the
`NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(`shk.c:3267` there), checked 2026-09-25, and is identical in NetHack 5.0.0 as
released, `NetHack/NetHack@16ff59115`. The branch
[`bugreport/17-alter-cost-next-shkp-loop`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/17-alter-cost-next-shkp-loop)
holds one proposed commit, verified by rebuild.

Severity: low / latent. It would be a hang if reached, but we found no way to
reach it.

## What the code is doing

```c
void
alter_cost(
    struct obj *obj,
    long amt) /* if 0, use regular shop pricing, otherwise force amount;
                 if negative, use abs(amt) even if it's less than old cost */
{
    struct bill_x *bp = 0;
    struct monst *shkp;
    long new_price;

    for (shkp = next_shkp(fmon, TRUE); shkp; shkp = next_shkp(shkp, TRUE))
        if ((bp = onbill(obj, shkp, TRUE)) != 0) {
            ...
            break; /* done */
        }
    return;
}
```

Source: [`src/shk.c:3236-3256`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3236-L3256).

```c
staticfn struct monst *
next_shkp(struct monst *shkp, boolean withbill)
{
    for (; shkp; shkp = shkp->nmon) {
        if (DEADMONSTER(shkp))
            continue;
        if (shkp->isshk && (ESHK(shkp)->billct || !withbill))
            break;
    }
    ...
    return shkp;
}
```

Source: [`src/shk.c:214-231`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L214-L231).

`next_shkp()` returns its argument whenever that argument is a live
shopkeeper with a bill. `alter_cost()` only reaches its loop step with such a
shopkeeper, one whose bill did not contain `obj`, so `next_shkp(shkp, TRUE)`
returns `shkp` again. `onbill()` fails again, and so on forever.

Every other walk over shopkeepers in `shk.c` steps past the current one before
calling `next_shkp()` again, with `shkp->nmon` (lines
[962-963](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L962-L963),
[970-971](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L970-L971),
[1019-1020](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1019-L1020),
[1095-1096](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1095-L1096),
[1209-1210](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1209-L1210),
[1335-1336](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1335-L1336),
[1761-1762](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1761-L1762),
[1801-1802](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1801-L1802),
[3217-3218](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3217-L3218),
[3278-3279](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3278-L3279),
[4860-4861](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L4860-L4861),
[5993-5994](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L5993-L5994))
or with a saved next pointer
([2519-2520](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2519-L2520),
[2556-2557](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2556-L2557)).
The walk directly after `alter_cost()`, in `unpaid_cost()` (line 3278), is the
same loop written correctly.

`alter_cost()` is called from `recharge()` (`read.c:797`, `832`),
`seffect_enchant_armor()` (`read.c:1247`, `1283`), `seffect_remove_curse()`
(`read.c:1565`), `chwepon()` (`wield.c:966`, `1028`), `oname()`
(`do_name.c:410`), `H2Opotion_dip()` (`potion.c:1576`) and
`bill_dummy_object()` (`mkobj.c:735`).

## Reachability

The loop hangs only if the first shopkeeper in `fmon` order who has a
non-empty bill does not have `obj` on it. With one shopkeeper holding a bill,
that shopkeeper owns the unpaid object and is found on the first step. So the
hang needs a second bill to exist at the same time.

A bill does not normally survive the hero leaving the shop. `u_left_shop()`
calls `rob_shop()`, which calls `setpaid()` and empties it. The exception is
`u_left_shop()`'s early return when the shopkeeper is not in his shop:

```c
    shkp = shop_keeper(*leavestring ? *leavestring : *u.ushops0);
    if (!shkp || !inhishop(shkp))
        return; /* shk died, teleported, changed levels... */
```

([`shk.c:594-596`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L594-L596)).
If a shopkeeper could be out of his shop, and still holding his bill, while the
hero walked out with his goods, the bill would survive. A second shop's bill on
the same level, belonging to a shopkeeper later in `fmon`, would then be enough
to hang the game at the next enchant, recharge or bless of that second shop's
goods.

The obvious way to get a shopkeeper out of his shop is closed on purpose. Any
`rloc()` that takes a resident shopkeeper out of his shop goes through
`rloc_to_core()`, which calls `make_angry_shk()`
([`teleport.c:1734-1740`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/teleport.c#L1734-L1740)).
That folds the bill into `robbed` and calls `setpaid()`, which empties it. We
tried two routes in wizard mode, on a level with a weapon shop and an armor
shop, and neither got further:

- A wand of teleportation zapped at the shopkeeper. In our attempt the beam
  also teleported some of his stock, which counts as theft, and he came
  straight back, angry. A clean zap would still go through `rloc_to_core()`.
- A wished-for teleportation trap on his post. He never stepped on it (a wished
  trap is already seen), and the hero's exit settled the bill as usual.

We have not looked further: at shopkeepers who leave their shops by other
means, at bones, or at variants. `bill_dummy_object()`'s call,
`alter_cost(dummy, -cost)`, is a second way in. It would hang if
`addtobill()` declined to bill the dummy while some shopkeeper had a bill. As
far as we can see, that also needs an unpaid object to be carried outside a
working shop, which is the same precondition.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch):

```c
-    for (shkp = next_shkp(fmon, TRUE); shkp; shkp = next_shkp(shkp, TRUE))
+    for (shkp = next_shkp(fmon, TRUE); shkp;
+         shkp = next_shkp(shkp->nmon, TRUE))
```

which is the form used by the other walks, including the next one in the file.
Fixed code:
[`shk.c:3246-3247`](https://github.com/davidbau/NetHack/blob/e5aad0a4e13b71f8e5f350ad3c13403352158fa3/src/shk.c#L3246-L3247)
· diff:
[commit e5aad0a4e](https://github.com/davidbau/NetHack/commit/e5aad0a4e13b71f8e5f350ad3c13403352158fa3).

## Verification

**The loop itself.** [`repro.c`](repro.c) contains `next_shkp()` and the
`alter_cost()` loop from `shk.c`, with the structures cut down to the fields
they read. It runs them on a monster list with two billed shopkeepers:

```
upstream, object on Jonzac's bill (first):  Jonzac   after 1 step
upstream, object on Ayancik's bill (second): still on Jonzac after 1000 steps -- infinite loop
proposed, object on Ayancik's bill (second): Ayancik  after 2 steps
```

**The normal case is unchanged.** Seed 5, wizard mode, Dlvl 2, Siirt's armor
shop. The hero picks up a chain mail (unpaid, 100 zorkmids), wears it, and
reads a blessed scroll of enchant armor. `seffect_enchant_armor()` calls
`alter_cost()`, and the bill goes up:

- [`Siirt's chain mail glows silver for a while.`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session.json#step=76)
- [`f - a +4 chain mail (being worn)  153 zorkmids`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session.json#step=79)
  (stock), and the same [with the patch](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/17-alter-cost-next-shkp-loop/session-fixed.json#step=79)

| | stock | patched |
|---|---|---|
| steps recorded | 81 | 81 |
| RNG entries | 5,445 | 5,445 |
| price after enchanting | 153 zorkmids | 153 zorkmids |

The two recordings are identical apart from the `shk.c` line numbers in the
RNG call-site annotations, which move by one because the patch splits a line.
This session has only one shopkeeper with a bill, so it cannot show the hang.
It shows that the patched loop still finds the right shopkeeper.

`repro.sh` compiles and runs `repro.c`, then checks whether your tree's
`alter_cost()` still has the upstream loop step. It exits 0 when it does, 1
when it has the patched form.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced during a line-by-line comparison of `shk.c` with the
port. A JavaScript port that followed this loop exactly would hang too, so the
port uses `shkp.nmon` here, and that was the one place in the function where
it had to depart from C.
