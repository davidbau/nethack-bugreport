**Title:** `#loot` can lock or unlock a far-away door, even on another level, after an interrupted `#force`

**Version:** `NetHack-5.0` tip `a9f93bb00`. `doforce()` leaves
`xlock.door` set as far back as the repository goes (`3de6c2e9a`, 2002);
`pick_lock()` with no tool (`02207b967`, "autounlock:untrap") lets a later
command run `picklock()` on that context.

**Symptom**

With `OPTIONS=autounlock:untrap`: lock a door with a key while standing on a
locked box, `#force` the box with a blunt weapon and get interrupted, pick the
box up, change level, put it down without `d` (throw it down with `t` `>`),
and `#loot` it:

```
The large box is locked.
You resume your attempt at locking the door.
You succeed in locking the door.
```

The box stays locked. The door at the level-1 door's x,y on the new level,
wherever the hero is, is now locked. If that spot is not a door, its `flags`
are overwritten with `D_LOCKED` or `D_CLOSED`, which for a wall are wall-mode
and `W_NONDIGGABLE` bits (include/rm.h:236-237, 300-301).

**Cause**

`doforce()` sets `gx.xlock.box = otmp` (src/lock.c:743) but leaves
`gx.xlock.door` from the earlier lock-pick, unlike `pick_lock()`, which clears
the other target (lock.c:536-537, 645-646). The level change keeps the context
because the box is carried (`maybe_reset_pick()`, lock.c:282-284, called from
do.c:1612). `xlock.door` points into `levl[][]`, so on the new level it names
the same x,y there.

`#loot` with `autounlock:untrap` calls `pick_lock(NULL, ...)`
(pickup.c:2129); the dummy pick's `otyp` is `STRANGE_OBJECT`, 0, which equals
a blunt `#force`'s `picktyp`, so the resume test (lock.c:380) runs
`picklock()`. `picklock()` checks only the box's position (lock.c:70-74) and
then acts on `xlock.door` because it is non-null (lock.c:139-150).

**Fix**

```diff
             gx.xlock.box = otmp;
+            gx.xlock.door = (struct rm *) 0;
             gx.xlock.chance = objects[uwep->otyp].oc_wldam * 2;
```

This keeps `xlock` to one target, as `pick_lock()` does and
`picklock()` assumes. Clearing the door at line 715
instead would also drop it when the `#force` is declined, which would lose
an interrupted door attempt that the next key apply can resume.

With the fix the same `#loot` resumes the `#force` as an attempt on the box
("You resume your attempt at unlocking the box.") because of the shared
`picktyp` 0; that is a separate question.

**Repro**

`bash repro.sh [nethack-src]` builds the tree and plays the steps above in a
pty-driven wizard-mode game (`#wizloadlua` makes the box, the doors and a
grid bug that interrupts `#force`; `^V` changes level).

On the tip it prints `level 2, before: ... is door, locked=false`, the three
messages above, `locked=true` and `BUG CONFIRMED -- #loot on level 2 locked
the door at X,Y, the x,y of the level-1 door` (exit 0). With
`proposed-fix.patch` the `#loot` unlocks the box and it prints `not seen --
the level-2 door at X,Y is still unlocked` (exit 1).
