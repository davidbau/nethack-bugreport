**Title:** A key binding for Delete, as `#saveoptions` writes it, is rejected when read back

**Version:** `NetHack-5.0` tip.

### Symptom

`#saveoptions` writes a changed binding for the Delete key as
`BIND=<del>:pray`. On the next start that line is rejected and the binding is
lost:

```
 * Line 3: Unknown key binding key '<del>'.
1 error in /home/.../.nethackrc.
Hit return to continue:
```

A hand-written `BIND=<del>:...`, using the name the game shows for the key in
its messages and menus, fails the same way.

### Cause

`key2txt()` (`src/cmd.c`) names four keys and spells the rest with
`visctrl()`:

```c
    else if (c == '\177')
        Sprintf(txt, "<del>"); /* "<delete>" won't fit */
```

`get_changed_key_binds()`, used by `#saveoptions`, writes
`BIND=<key2txt(key)>:<command>`. `txt2key()` (`src/options.c`) recognizes
`<enter>`, `<space>` and `<esc>` but not `<del>`, which falls through the
control, meta and decimal cases and returns `'\0'`: "Unknown key binding key".
`txt2key()` already reads Delete as `^?` or `127`.

### Fix

Accept `<del>` in `txt2key()` ([`proposed-fix.patch`](proposed-fix.patch)):

```diff
     if (!strcmp(txt, "<esc>"))
         return '\033';
+    if (!strcmp(txt, "<del>")) /* key2txt() writes it for #saveoptions */
+        return '\177';
```

This makes the writer's and reader's names match and lets the displayed name
be used in a config file. Alternative: drop the `<del>` case from `key2txt()`
so it writes `^?`, which also changes how the key is shown in messages and
menus.

### Repro

```
bash bugs/26-del-key-binding-roundtrip/repro.sh
```

Starts the recorder binary with a config file containing `BIND=<del>:pray`
and checks the opening screen for the error. Exits 0 if it appears (bug), 1
if not. Built from the `NetHack-5.0` tip: stock shows
`Unknown key binding key '<del>'.`; patched shows no error.
