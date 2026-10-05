**Title:** Identifying a gem does not reprice it on a shop bill that has a used up item ahead of it

**Version:** NetHack 5.0.0 as released (`NetHack/NetHack@16ff59115`, where it
was recorded). Present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25.

### Symptom

An unidentified "white gem" on the bill costs 800 zorkmids. Identifying it
while unpaid normally reprices worthless glass to 5. If a **used up** item
(a read shop scroll, eaten shop food) is ahead of the gem on the bill, the gem
keeps its price and is charged as
`an uncursed worthless piece of white glass (unpaid, 800 zorkmids)`.

Wizard mode, seed 6260: level-teleport to Minetown, in Akalapi's store pick up
and read a scroll (gold detection), wish for worthless white glass, sell it
for 7 gold, pick it back up, read identify.

- [Step 83](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=83): `a white gem (unpaid, 800 zorkmids)`
- [Step 117](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=117): identified as glass, still `800 zorkmids`
- [Step 122](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session.json#step=122): `Ix` shows the used up scroll
- [Control, scroll not read, step 114](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session-unread.json#step=114): `5 zorkmids` (the scroll is on the bill as an ordinary unpaid item)
- [Patched, step 117](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/25-gem-learned-bill-skip/session-fixed.json#step=117): `5 zorkmids`

### Cause

`gem_learned()`,
[`src/shk.c:3217-3230`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L3217-L3230):

```c
        while (--ct >= 0) {
            obj = find_oid(bp->bo_id);
            if (!obj) /* shouldn't happen */
                continue;
            ...
            ++bp;
        }
```

`continue` skips `++bp`, so once an entry's object is not found, no later
entry on that bill is examined. It does happen: a used up entry's object is on
`billobjs` (`obfree()`,
[`shk.c:1224-1233`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L1224-L1233);
also `addtobill()`, `sub_one_frombill()`), and `find_oid()` searches every list
but that one
([`shk.c:2771-2775`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2771-L2775)).
`bp_to_obj()` is the lookup that handles `bp->useup`.

`dopayobj()` charges `bp->price * quan`
([`shk.c:2253`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/shk.c#L2253)),
and the `(unpaid, N zorkmids)` text and `Iu` read `bp->price` through
`unpaid_cost()`. `gem_learned()` is also called from `undiscover_object()`
([o_init.c:489](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L489),
[521](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/o_init.c#L521)),
so forgetting a gem type is affected the same way.

### Fix

```diff
-        ct = ESHK(shkp)->billct;
-        bp = ESHK(shkp)->bill_p;
-        while (--ct >= 0) {
+        for (ct = ESHK(shkp)->billct, bp = ESHK(shkp)->bill_p; ct > 0;
+             --ct, ++bp) {
+            /* used up items are on the billobjs list, which find_oid()
+               doesn't search, so they won't be found and aren't repriced */
             obj = find_oid(bp->bo_id);
-            if (!obj) /* shouldn't happen */
+            if (!obj)
                 continue;
 ...
-            ++bp;
```

This keeps used up gems unrepriced and stops them blocking later entries.
Alternative: `bp_to_obj(bp)` instead of `find_oid()`, so used up gems are
repriced too; that is a pricing decision for the DevTeam.
[`proposed-fix.patch`](proposed-fix.patch); fixed code
[`shk.c:3217-3230`](https://github.com/davidbau/NetHack/blob/c7aa8a2cc74bf5190bcf1d9a99a711fdccc4d98f/src/shk.c#L3217-L3230),
[commit c7aa8a2cc](https://github.com/davidbau/NetHack/commit/c7aa8a2cc74bf5190bcf1d9a99a711fdccc4d98f),
branch [`bugreport/25-gem-learned-bill-skip`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/25-gem-learned-bill-skip).

### Repro

```
bash bugs/25-gem-learned-bill-skip/repro.sh
```

Re-records [`session.json`](session.json) and reads the price printed after
the scroll of identify: exits 0 for 800 zorkmids (bug), 1 for 5 (patched).

The patched recording has the same 123 steps and identical RNG stream (8,963
entries); only the price text differs (steps 117-121; `Iu` at step 119 shows
5 instead of 800). Reverting and rebuilding reproduces the stock recording
byte-for-byte.
