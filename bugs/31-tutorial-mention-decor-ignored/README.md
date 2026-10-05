**Title:** The tutorial's `OPTIONS=mention_decor` is ignored, so the tutorial never describes dungeon features

**Version:** `NetHack-5.0` tip `a9f93bb00`. Introduced by 8fcc15a86 ("mention_decor and tutorial K4372").

**Symptom**

`dat/tut-1.lua:65-67` turns on three options for new players:

```lua
nh.parse_config("OPTIONS=mention_walls");
nh.parse_config("OPTIONS=mention_decor");
nh.parse_config("OPTIONS=lit_corridor");
```

With no config file, start a game, answer `y` to "Do you want a tutorial?", and open `#optionsfull`:

```
 l - mention_decor           [false]
 m - mention_map             [false]
 n - mention_walls           [true]
```

`mention_walls` is on and `mention_decor` is off, so in the tutorial walking onto a broken door (after kicking open the locked one) or another feature says nothing. No error is reported.

**Cause**

`initoptions_finish()` marks the option disregarded before the startup `rcfile()` (`src/options.c:7348`):

```c
    disregard_this_option(opt_mention_decor);  /* defer this */
```

Nothing clears that mark until `rcfile_only_this_option(opt_mention_decor)` ends with `heed_all_options()`. When the tutorial is accepted, that call is `src/allmain.c:599` in `moveloop()`, which runs after `maybe_do_tutorial()` has already created tut-1 through `deferred_goto()`. While tut-1.lua runs, `parseoptions()` skips the option because `allopt[opt_mention_decor].disregarded` is set (`src/options.c:620-621`), and returns FALSE without a message (`src/options.c:671-673`).

**Fix**

```diff
     if (ask_do_tutorial()) {
+        /* tut-1.lua turns on mention_decor; let that take effect */
+        heed_this_option(opt_mention_decor);
         assign_level(&u.ucamefrom, &u.uz);
```

Once the player has chosen the tutorial, the stairs message from K4372 can no longer appear on the first level, so the deferral can end there. That lets the script's setting through. The `moveloop()` re-read still applies the player's own config value afterwards.

The re-read of the config file also has a side effect. `rcfile_only_this_option()` runs all of `rcfile()`, and the `CHOOSE=` handling in `parse_conf_buf()` (`src/cfgfiles.c:1793-1808`) runs even when statements are disregarded. So each re-read calls `rn2()` again and can pick a different section. A player who declines the tutorial gets two re-reads (`allmain.c:586` and `599`). This patch does not change that.

**Repro**

`bash repro.sh` clones the `NetHack-5.0` branch, or `bash repro.sh <tree>` copies an existing tree. It builds with `hints/linux.501`, drives a new game in a pty into the tutorial, and reads the two options from `#optionsfull`. At `a9f93bb00`:

```
  mention_walls = true   (tut-1.lua: OPTIONS=mention_walls)
  mention_decor = false   (tut-1.lua: OPTIONS=mention_decor)
=== BUG: the tutorial's mention_decor setting was ignored
```

The script exits 0. With `proposed-fix.patch` applied, it prints `mention_decor = true` and `=== OK: the tutorial's mention_decor setting is in effect`, and exits 1.
