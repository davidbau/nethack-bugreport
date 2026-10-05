**Title:** Rebinding a key from the `O` menu never says so, and unbinding one reads a freed struct

**Version:** `NetHack-5.0` tip
[`88ebe7c41`](https://github.com/NetHack/NetHack/tree/88ebe7c416fcd76f2ddee3102633d46d1e633117)
(checked 2026-09-25); recorded against `NetHack/NetHack@16ff59115` (5.0.0 as
released). Fix branch:
[`bugreport/14-rebind-key-message`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/14-rebind-key-message).

### Symptom

`#optionsfull`, `bind keys`, "bind key to a command", `J` (normally
`runsouth`), `pray`: the menu
[returns with no message](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=37),
though the binding changed
([`Key 'J' is currently bound to "pray".`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=39)).
The intended message is `Changed key 'J' from "runsouth" to "pray".`

Unbinding `J` ("nothing: unbind the key")
[prints](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session.json#step=40)
`Changed key 'J' from "pray" to "nothing".`, but reads `"pray"` from the freed
binding. AddressSanitizer ([`asan-report.txt`](asan-report.txt)):

```
ERROR: AddressSanitizer: heap-use-after-free ...
    #0 ... in handler_rebind_keys_add src/cmd.c:2394:37
... is located 16 bytes inside of 32-byte region ...   (the cmd field of struct Cmd_bind)
freed by thread T0 here:
    #1 ... in cmdbind_remove src/cmd.c:2171:13
    #2 ... in bind_key src/cmd.c:2670:9
    #3 ... in handler_rebind_keys_add src/cmd.c:2393:13
```

### Cause

[`src/cmd.c:2391-2403`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2391-L2403):

```c
        prevcmd = cmdbind_get(key);

        if (bind_key(key, cmdstr, TRUE)) {
            if (prevcmd && prevcmd->cmd != ec) {
                pline("Changed key '%s' from \"%s\" to \"%s\".",
                      key2txt(key, buf2), prevcmd->cmd->ef_txt, cmdstr);
```

`cmdbind_get()` returns the key's list entry, not a copy. On a rebind,
`cmdbind_add()` overwrites it in place (`bind->cmd = extcmd;`,
[`cmd.c:2136-2138`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2136-L2138)),
so `prevcmd->cmd != ec` is always false. On an unbind, `bind_key()` calls
`cmdbind_remove()`
([`cmd.c:2668-2671`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2668-L2671)),
which frees the entry
([`cmd.c:2171`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/cmd.c#L2171));
`ec` is NULL, so the test passes and `prevcmd->cmd->ef_txt` is read from freed
memory. Only binding a previously unbound key works ("Bound key ...").

### Fix

Save the old command, not the binding, before `bind_key()`:

```diff
-        prevcmd = cmdbind_get(key);
+        prevbind = cmdbind_get(key);
+        wasbound = (prevbind != 0);
+        if (wasbound)
+            prevcmd = prevbind->cmd;
 
         if (bind_key(key, cmdstr, TRUE)) {
-            if (prevcmd && prevcmd->cmd != ec) {
+            if (wasbound && prevcmd != ec) {
                 pline("Changed key '%s' from \"%s\" to \"%s\".",
-                      key2txt(key, buf2), prevcmd->cmd->ef_txt, cmdstr);
-            } else if (!prevcmd) {
+                      key2txt(key, buf2), prevcmd->ef_txt, cmdstr);
+            } else if (!wasbound) {
```

`prevcmd` becomes `const struct ext_func_tab *`. Rebinding a key to its
current command stays silent. Full diff:
[`proposed-fix.patch`](proposed-fix.patch);
[commit a2c2cb68c](https://github.com/davidbau/NetHack/commit/a2c2cb68cea8cb401758c7ab9bb74c4b783a6fda).
At the tip the patch needs a context adjustment: `c3ce34143` ("Strcat to an
empty character buffer") changed the adjacent `char cmdstr[BUFSZ];`
declaration.

### Repro

`bash bugs/14-rebind-key-message/repro.sh` re-records
[`session.json`](session.json) and checks that `J` ends up bound to `pray` with
no "Changed key" message for the rebind; it exits 1 if that message appears.
Patched:
[`Changed key 'J' from "runsouth" to "pray".`](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session-fixed.json#step=37)
and the
[same unbind message](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/14-rebind-key-message/session-fixed.json#step=41),
now from the saved pointer (`session-fixed.json` has one extra Enter for the
new `--More--`). The ASan report comes from the recorder built with
`-fsanitize=address` in `CFLAGS` and `LFLAGS` (`sys/unix/hints/linux-minimal`)
on the same inputs; the patched build runs clean.
