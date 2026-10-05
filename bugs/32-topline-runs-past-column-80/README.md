**Title:** tty: a message after a no-history message can be written past column 80

**Version:** `NetHack-5.0` tip `a9f93bb00`. The `show_topl()` path for
`ATR_NOHISTORY` messages dates from 190c90e95 ("tty ^P message recall", 2019).

**Symptom**

Messages shown with `SUPPRESS_HISTORY` (getpos autodescribe, "Unknown
command", "Count:") are written to the top line but not into `gt.toplines`.
If more messages follow before a key is read from the terminal, they are
appended after that text, and the room check does not count it. In the
repro, "Unknown command '^]'." is followed by a 55- and a 10-character
message; the second is written with `ESC[1;81H`, column 81 of an
80-column terminal. A debug-fuzzer run found this: a 32-column travel
autodescribe followed by three monster attacks put the cursor at columns 52, 78 and then 100. In
ordinary keyboard play `tty_nhgetch()` changes `TOPLINE_NEED_MORE` to
`TOPLINE_NON_EMPTY` before the next message, so the bug needs keys that
do not come from the terminal: the debug fuzzer's `randomkey()` or keys
queued with `nh.pushkey()`. A DEBUG build reports the bad position in
`tty_curs()` (wintty.c:2080).

**Cause**

`tty_putstr()` (wintty.c:2297-2299) calls `remember_topl()`, which empties
`gt.toplines`, then `show_topl()`, whose `addtopl()` (topl.c:161) leaves
`toplin == TOPLINE_NEED_MORE` and `cw->curx` at the end of the text. The
next `update_topl()` then concatenates (topl.c:262-273):

```c
        && n0 + (int) strlen(gt.toplines) + 3 < min(CO - 8, TBUFSZ)
        ...
        cw->curx += 2;
        if (!skip)
            addtopl(bp);
```

The length test sees only `gt.toplines`, not the no-history text before
it. When `cw->curx` is 78, `+= 2` makes it 80, which skips `topl_putsym()`'s wrap
test `ttyDisplay->curx == CO - 1` (topl.c:332), and the text runs on past
the edge.

**Fix**

```diff
     if ((ttyDisplay->toplin == TOPLINE_NEED_MORE || skip)
-        && cw->cury == 0
+        && cw->cury == 0 && *gt.toplines
```

An empty `gt.toplines` with `TOPLINE_NEED_MORE` only arises after
`show_topl()` (vpline() drops empty messages); the new message then gets
`--More--` and a fresh line, as when there is no room. Changing the state
`show_topl()` leaves would also change `display_nhwindow(WIN_MESSAGE)`.

**Repro**

`bash repro.sh [source-tree]` builds the tree (default: a shallow clone
of `NetHack-5.0`), starts a wizard-mode game in an 80x24 pty and uses
`#wizloadlua` to queue `^]`, run it with `nh.doturn()`, and issue the two
messages with `nh.pline()`.

At `a9f93bb00` (exit 0):
```
    row 1, column  24: 'The first message here is fifty-five characters in all.'
    row 1, column  81: 'Second one'
BUG: tty addressed the cursor to column 81 of an 80-column terminal to write 'Second one'
```
With `proposed-fix.patch` (exit 1):
```
    row 1, column  22: '--More--'
    row 1, column  58: 'Second one'
    (a --More-- was shown before the next message)
OK: every top-line message started at or before column 80
```
