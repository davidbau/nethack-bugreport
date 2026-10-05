**Title:** Monsters hidden under objects are unhidden every time their level is reloaded

**Version:** `NetHack-5.0` tip `a9f93bb00`. Introduced by `055caaffb`
("revisit shop_keeper() readiness", after the 5.0.0 release).

### Symptom

A snake (or other `hides_under()` monster) hiding under an object is visible
again after its level is read back in: on returning to the level by stairs,
after save and restore, and on bones levels. With `repro.sh`, the square
shows the object until the level is reloaded, then the snake:

```
  after #wizloaddes : map shows '(' at <42,10>; farlook: (  ... (a whistle)
  after save/restore: map shows 'S' at <42,10>; farlook: S  a snake (peaceful garter snake, asleep)
  after > and <     : map shows 'S' at <42,10>; farlook: S  a snake (garter snake, asleep)
```

### Cause

`055caaffb` moved `find_lev_obj()` in `getlev()` from just after
`fobj = restobjchn(...)` to after the monster loop (`src/restore.c:1265`),
so that it follows the loop's `set_residency()` calls. Inside that loop,
`hideunder()` (`restore.c:1236`) and `hide_monst()` (`restore.c:1261`) look
at `svl.level.objects[x][y]`, which `find_lev_obj()` has not filled yet.
`hideunder()` finds no object and sets `mundetected = 0`.

Bug 27 ([27-shkready-null-room](../27-shkready-null-room/)) is another
consequence of `055caaffb`.

### Fix

```diff
+    /* find_lev_obj() needs set_residency() for shop_keeper(), and the
+       monster loop below needs svl.level.objects[][] for hideunder() */
+    for (mtmp = fmon; mtmp; mtmp = mtmp->nmon)
+        if (mtmp->isshk)
+            set_residency(mtmp, FALSE);
+    level_status.shkready = 1;
+    find_lev_obj();
     for (mtmp = fmon; mtmp; mtmp = mtmp->nmon) {
 ...
-        if (mtmp->isshk)
-            set_residency(mtmp, FALSE);
 ...
-    level_status.shkready = 1;
-    find_lev_obj();
```

Setting residency in its own loop first keeps the order `055caaffb` wanted
(`set_residency()` before `find_lev_obj()`) and restores the objects before
the hiding code runs, whereas re-hiding after `find_lev_obj()` cannot recover
the cleared `mundetected` and would draw `hide_monst()`'s `rnd(10)` twice.
Full diff with a `fixes5-0-1.txt` entry: `proposed-fix.patch`.

### Repro

`bash repro.sh` clones and builds the `NetHack-5.0` head (or `bash repro.sh
<tree>` builds that tree), sets `WIZARDS=*`, and plays three wizard-mode games
in a pty. It loads a small des file with `#wizloaddes` whose garter snake is
created hidden under a random object, then checks the snake's square with `;`
after a save and restore, and after going down the stairs and back up.

On the tip it prints the output above, `VERDICT: BUG - the hidden snake was
unhidden by reloading its level`, and exits 0. With `proposed-fix.patch`
the object is still shown after both reloads, it prints `VERDICT: no bug -
the snake stayed hidden across both reloads`, and exits 1.
