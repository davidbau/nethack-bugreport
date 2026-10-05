**Title:** Duplicate option in a comma-separated OPTIONS list is reported "via alias: (null)"

**Version:** `NetHack-5.0` tip `a9f93bb00`. The `using_alias` flag and the
"(via alias: %s)" text came in with `058fbc1cd` ("more duplicate detect",
2020-03-01).

### Symptom

With this `~/.nethackrc`:

```
OPTIONS=name:nonesuch
OPTIONS=name:Xorn,align:neutral
```

the config-error report at startup is

```
 * Line 2: compound option specified multiple times: name (via alias: (null)).
```

`name` has no alias and was not given by one. `align` is the alias of
`alignment`. glibc prints `(null)` for the NULL `%s` argument; on other C
libraries passing NULL to `%s` is undefined behavior. If the duplicated
option does have an alias but was named by its full name, the message names
that alias instead.

### Cause

`parseoptions()` (`src/options.c:489`) handles a comma-separated list by
splitting off the first element and recursing on the rest, so elements are
processed right to left. It clears `using_alias` at entry (line 503), before
the recursion at line 519. The alias loop sets it (line 611) when the
right-hand element `align:neutral` matches through an alias. When the
recursion returns, the flag is still TRUE while the left-hand element
`name:Xorn` is processed, and `complain_about_duplicate()` then formats

```c
    if (using_alias)
        Sprintf(buf, " (via alias: %s)", allopt[optidx].alias);
```

(line 6815) with `allopt[opt_name].alias == NULL`.

### Fix

```diff
     duplicate = FALSE;
-    using_alias = FALSE;
     go.opt_initial = tinitial;
...
         if (!parseoptions(op, go.opt_initial, go.opt_from_file))
             retval = FALSE;
     }
+    /* reset after the recursion; a later element may have used an alias */
+    using_alias = FALSE;
```

Clearing the flag after the recursion, rather than at entry, makes it
describe only the element this call is about to match; `duplicate` needs no
change because it is reassigned for every matched element. The patch
(`proposed-fix.patch`) also adds a `doc/fixes5-0-1.txt` entry.

### Repro

```
bash repro.sh                 # shallow-clones NetHack-5.0 and builds it
bash repro.sh ~/src/NetHack   # or builds an existing tree
```

It builds with `hints/linux.501`, starts a game on a pty with the rc file
above, and prints the duplicate-option line. On `a9f93bb00`:

```
=== config error: * Line 2: compound option specified multiple times: name (via alias: (null)).
=== BUG SEEN: 'name' reported as given via an alias
```

(exit 0). With `proposed-fix.patch` applied:

```
=== config error: * Line 2: compound option specified multiple times: name.
=== bug not seen
```

(exit 1).
