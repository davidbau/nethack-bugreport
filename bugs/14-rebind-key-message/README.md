# Rebinding a key from the `O` menu never says so, and unbinding one reads a freed struct

The options menu has a "bind keys" entry (`O`, or `#optionsfull`, then
`bind keys`). It asks for a key and a command and is meant to confirm the
change:

```
Changed key 'J' from "runsouth" to "pray".
```

That message never appears when the key already had a binding. Bind `J`
(normally `runsouth`) to `pray` and the menu simply returns to "Do what?".
The binding does change: the next time you pick `J`, the menu says
`Key 'J' is currently bound to "pray".`

Unbinding a key (choosing "nothing: unbind the key") does print the message:

```
Changed key 'J' from "pray" to "nothing".
```

but by then the binding it names has been freed, and the text `"pray"` is
read through a pointer into that freed memory. On an ordinary glibc build the
freed bytes still hold the old value, so the message looks right. An
AddressSanitizer build reports a heap-use-after-free at that line.

The affected code is the tail of `handler_rebind_keys_add()` in `src/cmd.c`.
It is present at the `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117),
checked 2026-09-25, and was recorded against `NetHack/NetHack@16ff59115`,
NetHack 5.0.0 as released. The branch
[`bugreport/14-rebind-key-message`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/14-rebind-key-message)
holds one proposed commit, verified by rebuild.

Severity: low. A missing confirmation message, plus a read of freed memory
that is harmless on common allocators but is still undefined behaviour.

## Watch it happen

- [**Stock, the rebind**: `J` is bound to `pray` and the menu comes straight back with no message](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=37)
- [**Stock, the proof the rebind happened**: `Key 'J' is currently bound to "pray".`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=39)
- [**Stock, the unbind**: the message that does print, read from the freed binding](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=40)
- [**Patched, the rebind**: `Changed key 'J' from "runsouth" to "pray".`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session-fixed.json#step=37)
- [**Patched, the unbind**: the same message as stock, now from a saved pointer](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session-fixed.json#step=41)

The scenario, in normal play (wizard mode is on in the recording but is not
needed): `#optionsfull`, search for `bind keys`, choose "bind key to a
command", press `J`, search for `pray`; then do it again for `J` and choose
"nothing: unbind the key".

`session-fixed.json` has one more key than `session.json`: an Enter to dismiss
the `--More--` that the patched build now prints after the rebind. Otherwise
the two inputs are the same.

## Reproducing it

```
bash bugs/14-rebind-key-message/repro.sh
```

That re-records [`session.json`](session.json) through the stock recorder and
checks that `J` ends up bound to `pray` with no "Changed key" message for the
rebind. It exits 1 if the rebind message appears (the patch is probably
applied).

The freed read cannot be seen in the recording, since the freed bytes still
hold the old value. [`asan-report.txt`](asan-report.txt) is the report from an
AddressSanitizer build of the same recorder tree (`-fsanitize=address` added
to `CFLAGS` and `LFLAGS` in `sys/unix/hints/linux-minimal`) running the same
`session.json`. `cmd.c` line numbers in that tree are the same as upstream's.

```
ERROR: AddressSanitizer: heap-use-after-free ...
READ of size 8 ...
    #0 ... in handler_rebind_keys_add src/cmd.c:2394:37
... is located 16 bytes inside of 32-byte region ...
freed by thread T0 here:
    #0 ... in free
    #1 ... in cmdbind_remove src/cmd.c:2171:13
    #2 ... in bind_key src/cmd.c:2670:9
    #3 ... in handler_rebind_keys_add src/cmd.c:2393:13
```

Offset 16 in a `struct Cmd_bind` is the `cmd` field.

## What the code is doing

```c
        prevcmd = cmdbind_get(key);

        if (bind_key(key, cmdstr, TRUE)) {
            if (prevcmd && prevcmd->cmd != ec) {
                pline("Changed key '%s' from \"%s\" to \"%s\".",
                      key2txt(key, buf2), prevcmd->cmd->ef_txt, cmdstr);
            } else if (!prevcmd) {
                pline("Bound key '%s' to \"%s\".",
                      key2txt(key, buf2), cmdstr);
            }
        } else {
            pline("Key binding failed?!");
        }
```

Source: [`src/cmd.c:2391-2403`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2391-L2403).

`cmdbind_get()` returns a pointer to the key's entry in the `gc.Cmd.cmdbinds`
list, not a copy. `bind_key()` then changes that entry in one of two ways:

- **Rebinding to a command.** `bind_key()` calls `cmdbind_add()`, which, when
  the key already has an entry, overwrites it in place:

  ```c
      /* binding exists, set it to this command */
      if (bind) {
          bind->cmd = extcmd;
  ```

  ([`src/cmd.c:2136-2138`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2136-L2138)).
  After that, `prevcmd->cmd` is the new command `ec`, the test
  `prevcmd->cmd != ec` is always false, and neither message prints.

- **Unbinding** (`cmdstr` is `"nothing"`). `bind_key()` calls
  `cmdbind_remove()`
  ([`src/cmd.c:2668-2671`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2668-L2671)),
  which unlinks the entry and `free()`s it
  ([`src/cmd.c:2171`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2171)).
  `ec` is `NULL` here, so the test passes, and `prevcmd->cmd->ef_txt` is read
  from the freed entry.

The only case that behaves as intended is binding a key that had no entry at
all, which prints "Bound key ...".

The message is clearly meant to report the old command: the code compares the
old command with the new one and prints the old command's name. It just keeps
a pointer to the binding rather than to the command.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): remember whether the key was bound
and which command it was bound to *before* calling `bind_key()`, and test
those afterwards.

```c
        /* remember the command, not the binding; bind_key() either
           overwrites the binding in place or frees it */
        prevbind = cmdbind_get(key);
        wasbound = (prevbind != 0);
        if (wasbound)
            prevcmd = prevbind->cmd;

        if (bind_key(key, cmdstr, TRUE)) {
            if (wasbound && prevcmd != ec) {
                pline("Changed key '%s' from \"%s\" to \"%s\".",
                      key2txt(key, buf2), prevcmd->ef_txt, cmdstr);
            } else if (!wasbound) {
```

Fixed code and diff:
[commit a2c2cb68c](https://github.com/davidbau/NetHack/commit/a2c2cb68cea8cb401758c7ab9bb74c4b783a6fda).

`wasbound` is a separate flag so the freed pointer is never used afterwards,
not even to test it against null. Rebinding a key to the command it already
has stays silent, as before.

At the tip the patch needs a trivial context adjustment: commit `c3ce34143`
("Strcat to an empty character buffer") moved the `char cmdstr[BUFSZ];`
declaration that sits next to `prevcmd`, and initialised it. That commit fixed
a different bug in the same function and does not touch the lines this patch
changes.

## Verification

Rebuilt and re-recorded. Same seed, same datetime; the patched input has one
extra Enter for the new `--More--`:

| | stock | patched |
|---|---|---|
| steps recorded | 43 | 44 |
| RNG entries | 2,763 | 2,763 |
| message after binding `J` to `pray` | **none** | `Changed key 'J' from "runsouth" to "pray".` |
| `J` bound to `pray` afterwards | yes | yes |
| message after unbinding `J` | `Changed key 'J' from "pray" to "nothing".` | the same |
| AddressSanitizer, same inputs | **heap-use-after-free** on the unbind | clean, all 44 steps |

Reverting the source and rebuilding reproduced the stock recording exactly
(every step, screen and RNG entry byte-for-byte), which is the control that the
patched run differed because of the patch rather than because of the rebuild.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, recordings and patch from Claude
Opus 5.5. It surfaced during a tour of every entry in the `O` menu: the port
matched C's behaviour exactly, and the review of that behaviour asked why a
rebind printed nothing when an unbind did.
