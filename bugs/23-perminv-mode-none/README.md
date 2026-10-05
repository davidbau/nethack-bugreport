**Title:** `OPTIONS=perminv_mode:none` turns persistent inventory on

**Version:** NetHack 5.0.0 as released (`NetHack/NetHack@16ff59115`, where it
was recorded). `optfn_perminv_mode()` is unchanged at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25.

### Symptom

The Guidebook says `none` means "behave as if *perm_invent* is false"
([`doc/Guidebook.mn:4558-4559`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/doc/Guidebook.mn#L4558-L4559)).
In a `.nethackrc`, `perminv_mode:none` sets `perm_invent` on instead.

- tty built with `TTY_PERM_INVENT` (offered in `include/config.h`, always on
  in the Windows console port via `include/windconf.h`), on a 24x80 terminal:

  ```
  tty perm_invent could not be enabled.
  tty perm_invent needs a terminal that is at least 52x79, yours is 24x80.
  ```

- curses, or tty with `TTY_PERM_INVENT` on a large terminal: by reading the
  code, the window opens and lists everything except gold, as
  `perminv_mode:all` does (mode 0 has neither the gold nor the in-use bit).
  Not recorded; the recorder terminal is 24x80.
- default Unix tty build: no visible effect.

Recordings (same nethackrc and keys: three `ESC`s, then `|`):

- [Stock, `TTY_PERM_INVENT` build](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session.json#step=0):
  the start-up message. `|` then says "not presently enabled" because the tty
  size check turned the flag back off.
- [Patched, same build](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session-fixed.json#step=0):
  starts normally.
- [Stock, default tty build](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session-default-build.json#step=4):
  no effect; `|` reports tty has no persistent inventory.

### Cause

[`src/options.c:3075-3094`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L3075-L3094):

```c
                if (!strncmpi(op, pi0, ln) || !strncmpi(op, pi1, ln)
                    || op[0] == i + '0') { /* also accept '0'..'8' */
                    ...
                    iflags.perminv_mode = (uchar) i;
                    iflags.perm_invent = TRUE;
```

Row 0 of the table is `{ "none", "off", ... }`
([`options.c:226`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L226)),
so `none`, `off` and `0` reach the unconditional `perm_invent = TRUE`. The `O`
menu's `handler_perminv_mode()` clears `perm_invent` for `InvOptNone`
([`options.c:6064-6067`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L6064-L6067)),
and `!perminv_mode` or an unrecognised value both set it FALSE
([`options.c:3095-3105`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L3095-L3105)),
so a misspelt value does what `none` should. At start-up
`tty_create_nhwindow()` fails its size check, prints the two lines and clears
the flag
([`win/tty/wintty.c:2953-2967`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L2953-L2967)).

### Fix

```diff
                     iflags.perminv_mode = (uchar) i;
-                    iflags.perm_invent = TRUE;
+                    /* "none" means perm_invent is off */
+                    iflags.perm_invent = (i != InvOptNone);
```

The same rule `handler_perminv_mode()` applies. [`proposed-fix.patch`](proposed-fix.patch)
applies unchanged at the tip; branch
[`bugreport/23-perminv-mode-none`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/23-perminv-mode-none),
[commit 7f0e07a64](https://github.com/davidbau/NetHack/commit/7f0e07a645a9464ff0a480862b100dadbcad0fd7).

### Repro

```
bash bugs/23-perminv-mode-none/repro.sh
```

The script builds a copy of the recorder in `/tmp/nethack-bugreport-23` with
the `TTY_PERM_INVENT` line in `config.h` uncommented, re-records
[`session.json`](session.json), and checks for the start-up message. It exits
1 if the message is absent (normally because the patch is applied).

Stock and patched recordings (same seed, datetime, keys, nethackrc) both have
5 steps and 2,995 RNG entries; only the start-up message differs. Reverting
the source and rebuilding reproduces the stock recording byte-for-byte.
