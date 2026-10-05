**Title:** A fixed crysknife on the floor takes another 10% chance of turning into a worm tooth every time its level is loaded

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25; recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). The call dates from 2002 (`316a94d50f`). Fix branch:
[`bugreport/20-crysknife-reload-reversion`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/20-crysknife-reload-reversion).

**Symptom**

A fixed crysknife has a 10% chance of reverting to a worm tooth when
dropped. The chance is taken again each time its level is read back in: on
each return to the level, on each save (`dosave0()` reads every stored
level), and on each restore (every stored level once, the current level
twice). After `n` loads a knife survives with probability `0.9^n`; twenty
loads leave about one in eight. A save and restore also consumes random
numbers for every fixed crysknife on any stored level.

In the recording, a wizard-mode Valkyrie drops five fixed crysknives (+0 to
+4, so they do not stack) on level 2's up stairs, goes up and down twelve
times looking with `:`, then saves, restores and returns once more:

- [Stock, step 128](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=128): after the drop, five crysknives
- [Stock, step 134](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=134): first return, the +3 knife is a worm tooth
- [Stock, step 200](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#step=200): after twelve returns, three worm teeth
- [Patched, step 200](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session-fixed.json#step=200): five crysknives
- [Stock, segment 2, step 5](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session.json#seg=2&step=5): after save, restore and a return, four worm teeth (the save reverted one)
- [Patched, segment 2, step 5](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/20-crysknife-reload-reversion/session-fixed.json#seg=2&step=5): five crysknives

Each `>` back to level 2 logs one `rn2(10) @ obj_no_longer_held(do.c:911)`
per fixed crysknife still there (step 132: `6, 2, 8, 0, 2`; the 0 reverts).

**Cause**

`place_object()` calls `obj_no_longer_held()` unconditionally
([`mkobj.c:2328-2331`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/mkobj.c#L2328-L2331)),
which rolls `!rn2(10)` for a fixed crysknife
([`do.c:904-919`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/do.c#L904-L919)).
Drop paths rely on this (`steal.c:834`: `/* obj_no_longer_held(obj); --
done by place_object */`). But `getlev()` calls `find_lev_obj()`
([`restore.c:1168`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L1168)),
which rebuilds the floor with `place_object()`
([`restore.c:94-97`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L94-L97)),
so objects already on the floor, and inside floor containers, are rolled
again. `getlev()` runs on arrival at a visited level, per stored level in a
save
([`save.c:185-215`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/save.c#L185-L215)),
and in a restore
([`restore.c:873`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L873),
[`811`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L811),
[`898`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/restore.c#L898)).
An ordinary crysknife reverts on its first drop, so only fixed ones are
affected.

**Fix**

```diff
-    obj_no_longer_held(otmp);
+    /* objects being read back in from a level file were already on the
+       floor, so don't give a fixed crysknife another chance to revert */
+    if (!program_state.in_getlev)
+        obj_no_longer_held(otmp);
```

Commit [64b11e7e2](https://github.com/davidbau/NetHack/commit/64b11e7e251cd2856ea564d5a7b46ca449e8bdba);
also `proposed-fix.patch`. `in_getlev` covers level changes, saves and
restores; `find_lev_obj()` is the only `place_object()` caller inside
`getlev()`. Bones objects were already passed through
`obj_no_longer_held()` when the bones were made
([`bones.c:280`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/bones.c#L280)).
`level_status.loading`, now on the `NetHack-5.0` branch, could be tested
instead.

**Repro**

```
bash bugs/20-crysknife-reload-reversion/repro.sh
```

re-records [`session.json`](session.json) and checks for
`obj_no_longer_held` draws on steps that only change level. Exit 0: some
(bug); 1: only the five on the drop (patched); 2: scenario did not play out.
Stock makes 46 such draws (5 on the drop, 37 on the twelve returns, 2 on
the save, 1 on the restore, 1 on the return after it) in 6,057 RNG entries;
patched makes 5 in 6,009. Reverting and rebuilding reproduced the stock
recording exactly.
