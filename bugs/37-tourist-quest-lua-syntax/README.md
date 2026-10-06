**Title:** The Tourist quest home and locate levels fail to load and become random mazes; six named monsters on the home level are random monsters

**Version:** `NetHack-5.0` tip `8898570da`. The Tourist quest rewrite merged
in `993c80183` (branch `tourist-quest`, 2026-10-01) brought in all three
defects: `c0783332b` (the statues), `4bd33a2e2` (`end=`) and `ef1bc62a2`
(the monster tables).

**Symptom**

Reaching the Tourist quest home level (from the portal) or locate level
prints

```
luaL_loadbuffer: Error loading (Tou-strt.lua): [string "(Tou-strt.lua)"]:131: '}' expected near 'x'
Couldn't load "Tou-strt.lua" - making a maze.
```

(`Tou-loca.lua` fails at line 166 with `unexpected symbol near '='`), with
"Program in disorder!", and the level is a random maze. The home level then
has no Twoflower, so the hero cannot get the quest, and going down from it
says "A mysterious force prevents you from descending." (do.c:1585).

**Cause**

`dat/Tou-loca.lua:166` closes an `if` with `end=`, and
`dat/Tou-strt.lua:131-134` have no comma between `montype="wumpus"` and
`x=`. Both are Lua syntax errors, so `luaL_loadbuffer()` fails
(src/nhlua.c:2268-2272) and `makemaz()` falls back to a maze
(src/mkmaze.c:1188-1194).

With those fixed, `Tou-strt.lua:117-118` and `126-129` still write
`des.monster({"watchman", 35, 08, name="Sergeant Colon", male=1})` and the
like. In its table form `lspo_monster()` takes the species only from `id`
(`get_table_montype()`, src/sp_lev.c:3168-3180) and the place only from
`x`/`y` or `coord` (sp_lev.c:3342), and ignores the positional entries, so
Sergeant Colon, Corporal Nobbs, Bravd, the Weasel, Angua and Detritus are
each a random monster at a random spot carrying that name.

**Fix**

```diff
-end=
+end
-des.object({id="statue", montype="wumpus" x=34,y=8, historic=1, contents=0})
+des.object({id="statue", montype="wumpus", x=34,y=8, historic=1, contents=0})
-des.monster({"watchman", 35, 08, name="Sergeant Colon", male=1})
+des.monster({id="watchman", x=35, y=08, name="Sergeant Colon", male=1})
-des.monster({"barbarian", peaceful=1, name="Bravd", male=1, keep_default_invent=false})
+des.monster({id="barbarian", peaceful=1, name="Bravd", male=1, keep_default_invent=false})
```

and the same for the other three statues and four monsters
(`proposed-fix.patch`). `id=`, `x=` and `y=` are the keys the table form
reads.

**Repro**

`bash repro.sh [nethack-src]` compiles `luac` from the tree's
`nhlua/lua/src`, runs `luac -p` over `dat/*.lua`, and lists
`des.monster({"...` tables. With `GAME=1` it also builds the game and runs
`#wizloaddes Tou-strt` and `#wizloaddes Tou-loca` in a wizard-mode game.

On the tip it prints the two `luac` errors, the six tables, the two
`luaL_loadbuffer` errors from the game and `BUG CONFIRMED -- 2 dat/*.lua
file(s) are not valid Lua; 6 des.monster table(s) name the species without
id=` (exit 0). With `proposed-fix.patch`: `131 files, 0 fail to compile`,
`0 found`, both levels load, `not seen` (exit 1).
