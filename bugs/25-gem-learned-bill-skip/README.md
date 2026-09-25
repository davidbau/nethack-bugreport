# Identifying a gem does not reprice it on a shop bill that has a used up item

Shopkeepers price unidentified gems high: in this game Akalapi asks 800
zorkmids for a "white gem", real or not. When the hero identifies the gem type
while the gem is still unpaid, `gem_learned()` is supposed to reprice it, and
normally it does: identify a worthless piece of white glass and its bill price
drops to 5 zorkmids.

But if the bill already has a **used up** item on it ahead of the gem, for
example a shop scroll the hero has read or shop food the hero has eaten, the
gem is not repriced. The glass is shown and charged as
`an uncursed worthless piece of white glass (unpaid, 800 zorkmids)`.

The affected code is `gem_learned()` in `src/shk.c`. It is present at the
`NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/25-gem-learned-bill-skip`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/25-gem-learned-bill-skip)
holds one proposed commit, verified by rebuild.

Severity: low. The hero is overcharged for an identified gem, but only when a
used up item is ahead of it on the same bill and the gem type is identified
while the gem is unpaid.

## Watch it happen

Wizard mode, seed 6260: level-teleport to Minetown, walk into Akalapi's general
store, pick up a scroll and read it (gold detection), then wish for a worthless
piece of white glass, sell it to Akalapi for 7 gold, pick it back up, and read
a scroll of identify.

- [**Step 83**: the glass is billed as `a white gem (unpaid, 800 zorkmids)`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=83)
- [**Step 117**: identified as worthless glass, still `800 zorkmids`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=117)
- [**Step 122**: `Ix` shows the used up scroll on the bill](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=122)
- [**Control, stock build, scroll not read, step 114**: `5 zorkmids`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session-unread.json#step=114)
- [**Patched, step 117**: `5 zorkmids`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session-fixed.json#step=117)

The control is the same keystream without reading the shop scroll. The scroll
is still on the bill, but as an ordinary unpaid item in inventory, and the
glass is repriced. The only thing that stops the repricing is a used up entry
ahead of the gem.

## Reproducing it

```
bash bugs/25-gem-learned-bill-skip/repro.sh
```

That re-records [`session.json`](session.json) through the recorder binary and
reads the price on the line printed after the scroll of identify. It exits 0
for 800 zorkmids (the bug) and 1 for 5 zorkmids (as with the patch applied).

## What the code is doing

```c
    for (shkp = next_shkp(fmon, TRUE); shkp;
         shkp = next_shkp(shkp->nmon, TRUE)) {
        ct = ESHK(shkp)->billct;
        bp = ESHK(shkp)->bill_p;
        while (--ct >= 0) {
            obj = find_oid(bp->bo_id);
            if (!obj) /* shouldn't happen */
                continue;
            if ((oindx != STRANGE_OBJECT) ? (obj->otyp == oindx)
                                          : (obj->oclass == GEM_CLASS))
                bp->price = get_cost(obj, shkp);
            ++bp;
        }
    }
```

Source: [`src/shk.c:3217-3230`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3217-L3230).

`continue` goes back to `--ct >= 0` without reaching `++bp`, so the loop looks
at the same bill entry again on every remaining iteration. Once it reaches an
entry whose object cannot be found, no later entry on that bill is examined.

The comment says that cannot happen, but it can. When an unpaid item is used
up, `obfree()` sets `bp->useup` and moves the object to the `billobjs` list
([`shk.c:1224-1233`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1224-L1233);
`addtobill()` and `sub_one_frombill()` make used up entries too). `find_oid()`
searches every list *except* that one, and says so
([`shk.c:2771-2775`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2771-L2775)):

```c
/*
 * Look for o_id on all lists but billobj.  Return obj or NULL if not found.
```

`bp_to_obj()`, next to it, is the lookup that checks `bp->useup` and searches
`billobjs`. So every used up entry takes the `continue` path. The bill is in
the order items were added, so a used up item picked up before the gem blocks
the gem.

The stale price is what the hero pays: `dopayobj()` charges
`bp->price * quan`
([`shk.c:2253`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2253)),
and the `(unpaid, N zorkmids)` text and `Iu` both read `bp->price` through
`unpaid_cost()`. `gem_learned()` is called from `discover_object()` and
`undiscover_object()` in `o_init.c`
([489](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L489),
[521](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L521)),
so forgetting a gem type is affected in the same way.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): advance the pointer in the loop
header so every entry is examined once, and replace the comment with the real
reason an entry is not found.

```c
        for (ct = ESHK(shkp)->billct, bp = ESHK(shkp)->bill_p; ct > 0;
             --ct, ++bp) {
            /* used up items are on the billobjs list, which find_oid()
               doesn't search, so they won't be found and aren't repriced */
            obj = find_oid(bp->bo_id);
            if (!obj)
                continue;
            if ((oindx != STRANGE_OBJECT) ? (obj->otyp == oindx)
                                          : (obj->oclass == GEM_CLASS))
                bp->price = get_cost(obj, shkp);
        }
```

Fixed code:
[`shk.c:3217-3230`](https://github.com/davidbau/NetHack/blob/c7aa8a2cc74bf5190bcf1d9a99a711fdccc4d98f/src/shk.c#L3217-L3230)
· diff:
[commit c7aa8a2cc](https://github.com/davidbau/NetHack/commit/c7aa8a2cc74bf5190bcf1d9a99a711fdccc4d98f).

This keeps the current rule that used up gems are not repriced; the patch only
stops them from blocking the entries after them. **An alternative** is to use
`bp_to_obj(bp)` instead of `find_oid(bp->bo_id)`, so that a used up gem is
repriced too. Which is right is a pricing decision for the DevTeam; either
way the pointer has to advance.

## Verification

Rebuilt and re-recorded, same seed, same datetime, same keystream:

| | stock | patched |
|---|---|---|
| steps recorded | 123 | 123 |
| RNG entries | 8,963 | 8,963 (identical) |
| step 83, glass picked up | `a white gem (unpaid, 800 zorkmids)` | same |
| step 117, glass identified | `(unpaid, 800 zorkmids)` | `(unpaid, 5 zorkmids)` |
| step 119, `Iu` | `800 zorkmids` | `5 zorkmids` |

The screens differ only in the price text (steps 117 to 121), and the RNG
streams are identical. Reverting the source and rebuilding reproduced the
stock recording byte-for-byte, which is the control that the patched run
differed because of the patch rather than the rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from
Claude Opus 5.5. It surfaced while porting `gem_learned()`, where the
`continue` visibly skips the `++bp`. It was first noted as probably harmless
because of the "shouldn't happen" comment; checking when `find_oid()` can
actually fail showed that used up bill entries always reach it.
