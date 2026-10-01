# A key binding for Delete, as `#saveoptions` writes it, is rejected when read back

NetHack can write the player's current options to a config file with
`#saveoptions`, including any changed key bindings, as `BIND=` lines. A binding
for the Delete key is written as

```
BIND=<del>:pray
```

and the next time the game starts, that line is rejected:

```
 * Line 3: Unknown key binding key '<del>'.
1 error in /home/.../.nethackrc.
Hit return to continue:
```

The binding is lost, and the player gets a config-file error for a line the
game wrote itself. A hand-written `BIND=<del>:...` line, using the spelling the
game shows for that key in its own messages and menus, fails the same way.

## Reproducing it

```
bash bugs/26-del-key-binding-roundtrip/repro.sh
```

That starts the recorder binary with a config file containing
`BIND=<del>:pray` and checks the opening screen for the error above. It exits 0
if the error appears (the bug) and 1 if it does not (as with the patch
applied).

## What the code is doing

`key2txt()` (`src/cmd.c`) spells four keys by name and the rest with
`visctrl()`:

```c
    if (c == ' ')
        Sprintf(txt, "<space>");
    else if (c == '\033')
        Sprintf(txt, "<esc>"); /* "<escape>" won't fit */
    else if (c == '\n')
        Sprintf(txt, "<enter>"); /* "<return>" won't fit */
    else if (c == '\177')
        Sprintf(txt, "<del>"); /* "<delete>" won't fit */
    else
        Strcpy(txt, visctrl((char) c));
```

`get_changed_key_binds()`, which `#saveoptions` uses, writes each changed
binding as `BIND=<key2txt(key)>:<command>`. `txt2key()` (`src/options.c`),
which reads `BIND` lines, recognizes the first three names but not the fourth:

```c
    if (!strcmp(txt, "<enter>"))
        return '\n';
    if (!strcmp(txt, "<space>"))
        return ' ';
    if (!strcmp(txt, "<esc>"))
        return '\033';
```

`<del>` then falls through to the control, meta and three-digit-decimal cases,
none of which match, and `txt2key()` returns `'\0'`: "Unknown key binding key".

`txt2key()` already reads Delete written as `^?` (the spelling `visctrl()` uses)
or as `127`. Only the name `key2txt()` actually writes is missing.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): accept `<del>` in `txt2key()`.

```c
    if (!strcmp(txt, "<del>")) /* key2txt() writes it for #saveoptions */
        return '\177';
```

That keeps the four names symmetric between the writer and the reader, and it
makes the name the game shows for the key usable in a config file. The other
choice is to drop the `<del>` case from `key2txt()` so that it writes `^?`,
which `txt2key()` already reads; that would also change how the key is shown
in messages and menus.

## Verification

Built from the `NetHack-5.0` tip with and without the patch, started with a
config file containing `BIND=<del>:pray`:

| | stock | patched |
|---|---|---|
| opening screen | `Unknown key binding key '<del>'.` | no error |

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis and patch from Claude Opus 5.5.
It surfaced while porting `key2txt()` and `txt2key()` side by side, where the
writer's list of names has one entry the reader's does not.
