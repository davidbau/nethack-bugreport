# `OPTIONS=perminv_mode:none` turns persistent inventory on

The Guidebook describes `perminv_mode:none` as "behave as if *perm_invent*
is false". Putting it in a `.nethackrc` does the opposite: the option parser
switches `perm_invent` **on**, with a mode that is supposed to mean "no
persistent inventory".

What the player sees depends on the interface:

- **tty built with `TTY_PERM_INVENT`** (the option `include/config.h` offers
  for this, and always on in the Windows console port through
  `include/windconf.h`), on an ordinary 24x80 terminal: the game starts by
  saying it could not open a window the player asked not to have.

  ```
  tty perm_invent could not be enabled.
  tty perm_invent needs a terminal that is at least 52x79, yours is 24x80.
  ```

  This is recorded below.
- **Interfaces that can show the window** (curses, or tty with
  `TTY_PERM_INVENT` on a large enough terminal): by reading the code, the
  persistent inventory window opens. Mode 0 has neither the "show gold" nor
  the "in use only" bit set, so it lists everything except gold, the same as
  `perminv_mode:all`. This case was not recorded, because the recorder
  terminal is 24x80.
- **The default Unix tty build** (no `TTY_PERM_INVENT`): nothing visible. The
  port has no persistent inventory, and `|` says so whatever the flag holds.
  [`session-default-build.json`](session-default-build.json) shows this.

The affected code is `optfn_perminv_mode()` in `src/options.c`. It is present
at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25 (the function is unchanged there), and was recorded against
`NetHack/NetHack@16ff59115`, NetHack 5.0.0 as released. The branch
[`bugreport/23-perminv-mode-none`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/23-perminv-mode-none)
holds one proposed commit, verified by rebuild.

Severity: low. An option value does the opposite of what the Guidebook says.
The workaround is to leave the option out, since `none` is already the
default.

## Watch it happen

- [**Stock, `TTY_PERM_INVENT` build**: the start-up message about the window that could not be enabled](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session.json#step=0)
- [**Patched, same build option**: the game starts normally](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session-fixed.json#step=0)
- [**Stock, default tty build**: no visible effect; `|` reports that tty has no persistent inventory](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/23-perminv-mode-none/session-default-build.json#step=4)

All three use the same nethackrc, which contains `OPTIONS=perminv_mode:none`,
and the same keys: three `ESC`s to get past the opening screens, then `|`.
In the stock `TTY_PERM_INVENT` recording, `|` then says persistent inventory
"is not presently enabled". That is only because the tty port turned the flag
back off after its size check failed.

## Reproducing it

```
bash bugs/23-perminv-mode-none/repro.sh
```

The stock recorder is built without `TTY_PERM_INVENT`, so it cannot show the
bug. The script builds a private copy of the recorder in
`/tmp/nethack-bugreport-23` with that one `config.h` line uncommented,
re-records [`session.json`](session.json) with it, and checks for the
start-up message. It exits 1 if the message is absent, which normally means
the patch is already applied.

## What the code is doing

```c
            for (i = 0; i < SIZE(perminv_modes); ++i) {
                if (!(pi0 = perminv_modes[i][0]))
                    continue;
                pi1 = perminv_modes[i][1];
                if (!strncmpi(op, pi0, ln) || !strncmpi(op, pi1, ln)
                    || op[0] == i + '0') { /* also accept '0'..'8' */
                    ...
                    iflags.perminv_mode = (uchar) i;
                    iflags.perm_invent = TRUE;
                    break;
                }
            }
```

Source: [`src/options.c:3075-3094`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L3075-L3094).

Row 0 of the table it walks is

```c
  /*0*/ { "none",      "off",        "no permanent inventory window" },
```

([`src/options.c:226`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L226)),
so `none`, `off` and `0` all match row 0 and reach the unconditional
`perm_invent = TRUE`.

Everything else in the game treats "none" as "off":

- The Guidebook: "`none` behave as if *perm_invent* is false"
  ([`doc/Guidebook.mn:4558-4559`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/doc/Guidebook.mn#L4558-L4559)).
- The same option set from the `O` menu, in `handler_perminv_mode()`:

  ```c
        if (new_pi != InvOptNone && !old_perm_invent)
            iflags.perm_invent = can_set_perm_invent();
        else if (new_pi == InvOptNone && old_perm_invent)
            iflags.perm_invent = FALSE;
  ```

  ([`src/options.c:6064-6067`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L6064-L6067)).
- The two other ways of clearing the mode in this function, `!perminv_mode`
  and an unrecognised value, both set `perm_invent = FALSE`
  ([`src/options.c:3095-3105`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/options.c#L3095-L3105)).
  So a misspelt value does what `none` was meant to do, and `none` itself
  does not.

The flag is then acted on at start-up. On the recorded build,
`tty_create_nhwindow()` tries to create the `NHW_PERMINVENT` window, fails its
size check, prints the two lines and clears the flag again
([`win/tty/wintty.c:2953-2967`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/win/tty/wintty.c#L2953-L2967)).

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): set `perm_invent` from the mode
that was chosen.

```c
                    iflags.perminv_mode = (uchar) i;
                    /* "none" means perm_invent is off */
                    iflags.perm_invent = (i != InvOptNone);
                    break;
```

Fixed code and diff:
[commit 7f0e07a64](https://github.com/davidbau/NetHack/commit/7f0e07a645a9464ff0a480862b100dadbcad0fd7).

This is the same rule `handler_perminv_mode()` already applies. The patch
applies unchanged at the tip.

## Verification

Rebuilt with `TTY_PERM_INVENT` and re-recorded. Same seed, same datetime,
same keystream, same nethackrc:

| | stock | patched |
|---|---|---|
| steps recorded | 5 | 5 |
| RNG entries | 2,995 | 2,995 |
| "tty perm_invent could not be enabled." at start-up | **printed** | absent |
| `|` | "not presently enabled" (the size check had turned it off) | "not presently enabled" |

The RNG stream and the step count are identical, so the patch changes the
option's effect and nothing else. Reverting the source and rebuilding
reproduced the stock recording exactly, byte-for-byte, which is the control
that the patched run differed because of the patch rather than because of the
rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced while porting the option parser, which the port copied
faithfully; setting an option to `none` and getting the window turned on
looked wrong once the Guidebook text was set beside it.
