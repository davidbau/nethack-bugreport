# Bug #03 — Tutorial dungeon silently inherits `AM_CHAOTIC` via bit-collision

**Status:** unreported upstream as of 2026-06-19 (searched
[NetHack/NetHack issues](https://github.com/NetHack/NetHack/issues)
and [PRs](https://github.com/NetHack/NetHack/pulls) for
`Tutorial alignment`, `UNCONNECTED chaotic`, `init_level align`,
`D_ALIGN_MASK`, `dungeon flags collision`, `align_shift Tutorial` —
no matching issue or PR).

**NetHack version:** 5.0.0 (also present in the 3.7 line; the
`init_level()` function in `src/dungeon.c` and the constants in
`include/dgn_file.h` have not changed for many years).

**Not patch-induced:** the bug is in pure bit math involving
header-defined macros (`UNCONNECTED`, `D_ALIGN_CHAOTIC`,
`D_ALIGN_MASK`) and the data layout of `struct tmpdungeon`. The
`repro.c` shipped with this bundle is self-contained — it hard-codes
the relevant macros verbatim from
`nethack-c/upstream/include/{align,dgn_file}.h` and exercises the
same expression `init_level()` uses, with no linking, no recorder
binary, and no patches.

**Severity:** MEDIUM. Not a crash or data-corrupt; the Tutorial is
still playable. The visible effect is a uniform upward bias in
random monster spawn weights on tut-1 and tut-2 — see "Downstream
effect" below for the exact numbers.

## What you see in-game

No message tells the player the level is treated as chaotic-aligned.
A single Tutorial run is too short to surface the bias plainly; the
effect is statistical, and a player has no reference for what the
"correct" monster distribution should look like.

It IS observable with any of these tools:

- **Instrumentation**: dump `rndmonst()`'s computed weights on entry
  to tut-1 and compare against an `AM_NONE` baseline. The
  per-monster shift table appears in "Downstream effect" below.
- **Empirical comparison**: record many Tutorial runs, count
  monster species frequencies, compare against `dat/dungeon.lua`'s
  declared (unaligned) intent. Chaotic-aligned monsters are
  over-represented by roughly the spawn-weight shift.
- **Source inspection**: this bug's `repro.c` (no NetHack build
  needed).

The bug was originally surfaced this way: the JavaScript port of
NetHack 3.7
([davidbau/teleport](https://github.com/davidbau/teleport))
initially produced cumulative monster weights of `3, 4, 5, …, 21`
on tut-1, while the C recorder produced `5, 8, 11, …, 39` — exactly
`+2` per monster, totalling a `+18` mismatch at the end. Tracing
the discrepancy through `align_shift()` and then back through
dungeon init pinpointed the bit collision.

## Downstream effect (the only one)

`flags.align` has exactly **two** consumers in all of NetHack:

| Consumer | C ref | Fires for Tutorial? |
|---|---|---|
| `align_shift()` — biases monster spawn weights | `makemon.c:1621` | **Yes**, on every `rndmonst()` call |
| `induced_align()` — random-altar / `AM_SPLEV_RANDOM` alignment | `dungeon.c:2004` | **No** — Tutorial Lua scripts have no random-altar generation or `AM_SPLEV_RANDOM` placements; both callers (`mkroom.c:616` random rooms; `sp_lev.c:1917` Lua `random` alignment) are dormant on Tutorial levels |

So the only visible effect is `align_shift`'s spawn-weight bias.
With `ALIGNWEIGHT = 4` (`global.h:411`) and `AM_CHAOTIC`'s formula
`alshift = -(ptr->maligntyp - 20) / (2 * ALIGNWEIGHT)`, the per-monster
weight bonus relative to the `AM_NONE` baseline is:

| Monster `maligntyp` | Example | `AM_NONE` bonus | `AM_CHAOTIC` (buggy) bonus |
|---|---|---|---|
| −10 (strongly chaotic) | ogre | 0 | **+3** |
| −5  (chaotic)          | orc  | 0 | **+3** |
|  0  (neutral)          | lichen | 0 | **+2** |
| +5  (lawful)           | dwarf | 0 | **+1** |
| +10 (strongly lawful)  | paladin | 0 | **+1** |
| +15+ (very lawful)     | — | 0 | 0 |

`rndmonst()` selects from the per-difficulty pool weighted by
`G_FREQ + align_shift(ptr)`. Base `G_FREQ` for difficulty-1
monsters is typically 2-3, so a `+2`-`+3` shift roughly doubles
the relative selection probability of chaotic and neutral
monsters at the player's expense of lawful ones.

The cumulative weight totals quoted above
(`3,4,5,…,21` AM_NONE vs `5,8,11,…,39` AM_CHAOTIC)
make this concrete: the buggy table is nearly 2× the size,
shifting the rolled threshold into chaotic territory more often.

No other gameplay effect changes — peace/hostility uses the
PLAYER's alignment (`u.ualign.type`, `makemon.c:2270`), not the
level's; altar generation on Tutorial doesn't fire; sp_lev random
alignment doesn't fire.

## Repro

```bash
cd nethack-bugreport
bash bugs/03-tutorial-alignment-collision/repro.sh
```

No setup required. The reproducer is a standalone C program (no
NetHack headers, no recorder binary). It prints the bit math
side-by-side and exits 0 when the collision is confirmed.

Sample output:

```
Tutorial dungeon definition:
    dat/dungeon.lua flags = { mazelike, unconnected }
    --> raw bitmask                                  = 0x14
    Lua-parsed `alignment` (absent --> default)      = D_ALIGN_NONE (0x00)
    stored in tmpdungeon[Tutorial].align             = 0x00

init_level()'s fallback uses .flags, not .align:
    (tutorial_flags & D_ALIGN_MASK)       = 0x10
    >> 4                                   = 0x01   (AM_CHAOTIC)

Bit collision:
    UNCONNECTED (0x10) and D_ALIGN_CHAOTIC (0x10) occupy the same
    bit position in the dgn_file flags byte.  init_level extracts
    bits 4-6 as the alignment fallback, so any dungeon with the
    UNCONNECTED flag set is silently treated as chaotic-aligned.

Proposed fix (read the parsed .align instead):
    tmpdungeon[dgn].align >> 4             = 0x00   (AM_NONE)

BUG REPRODUCED: init_level fallback yields AM_CHAOTIC, but the
Lua-parsed alignment is AM_NONE.
```

## Root cause

Three pieces of code combine to produce the collision:

**1. Bit definitions** (`include/dgn_file.h`):
```c
#define MAZELIKE        0x04
#define UNCONNECTED     0x10                /* <-- bit 4 */
...
#define D_ALIGN_CHAOTIC (AM_CHAOTIC << 4)   /* <-- = 0x10, bit 4 */
#define D_ALIGN_NEUTRAL (AM_NEUTRAL << 4)
#define D_ALIGN_LAWFUL  (AM_LAWFUL  << 4)
#define D_ALIGN_MASK    0x70                /* bits 4..6 */
```

`UNCONNECTED` and `D_ALIGN_CHAOTIC` are independent enums that
happen to pick the same bit position in the same byte.

**2. Data definition** (`dat/dungeon.lua`):
```lua
{
    name = "The Tutorial",
    base = 2,
    flags = { "mazelike", "unconnected" },
    levels = { { name = "tut-1", base = 1 }, { name = "tut-2", base = 2 } },
},
```

The Tutorial sets `flags` but not `alignment`. `get_dgn_flags()`
(`dungeon.c:744`) OR-merges the flag names into a bitmask:
`MAZELIKE | UNCONNECTED = 0x14`. `get_dgn_align()` (`dungeon.c:781`)
returns the default — `D_ALIGN_NONE` (0) — because no `alignment` key
is set.

`init_dungeon_set_dungeon()` then stores BOTH fields in
`struct tmpdungeon` (`dungeon.c:1056-1057`):
```c
pd->tmpdungeon[dngidx].flags = dgn_flags;   /* 0x14 for Tutorial */
pd->tmpdungeon[dngidx].align = dgn_align;   /* D_ALIGN_NONE for Tutorial */
```

So `tmpdungeon[Tutorial].align` correctly holds the parsed alignment.

**3. The reader** (`dungeon.c:583-591` `init_level()`):
```c
new_level->flags.align = ((tlevel->flags & D_ALIGN_MASK) >> 4);
if (!new_level->flags.align)
    new_level->flags.align =
        ((pd->tmpdungeon[dgn].flags & D_ALIGN_MASK) >> 4);   /* <-- BUG */
```

The fallback (when the per-level `tlevel->flags` doesn't carry
alignment bits) re-extracts the alignment from
`tmpdungeon[dgn].flags`, ignoring the separately-parsed `.align`
field. For the Tutorial:
- `tmpdungeon[Tutorial].flags = 0x14`
- `(0x14 & 0x70) >> 4 = 0x10 >> 4 = 1 = AM_CHAOTIC`

So every Tutorial level gets `flags.align = AM_CHAOTIC` instead of
`AM_NONE`. The downstream consumer is `align_shift()`
(`makemon.c:1611`), which returns `+2` for most difficulty-1 monsters
under `AM_CHAOTIC`, biasing the Tutorial's monster spawn weights.

## Why this is most likely a bug, not a design choice

- **The Tutorial's job is to teach with predictable, gentle monsters.
  Making it chaotic-difficulty is the opposite intent.** No
  data-file comment justifies the chaotic alignment, and no other
  stock dungeon relies on this fallback path coming from `.flags`.
- **`struct tmpdungeon` has BOTH a `.flags` field AND a separately-
  parsed `.align` field.** The Lua loader properly stores the parsed
  alignment in `.align` at line 1057. The clear intent of having two
  separate fields is to avoid the bit collision — but `init_level`
  reads from the wrong one.
- **The Tutorial is the only stock dungeon that triggers this.** It
  is the only data-file dungeon with `UNCONNECTED` set but no
  `alignment` key (Sokoban has `unconnected` but `alignment =
  "lawful"`; the others don't have `unconnected` at all). The fact
  that the bug only fires for the Tutorial is consistent with a
  rarely-traversed code path, not an intentional design.

## Proposed patch

See `proposed-fix.patch`. **Replace `tmpdungeon[dgn].flags &
D_ALIGN_MASK` with `tmpdungeon[dgn].align`** at the fallback site so
the parsed alignment is honoured instead of being re-derived from
the bit-colliding `.flags` byte.

The corrected expression `tmpdungeon[dgn].align >> 4`:
- `D_ALIGN_NONE    (0x00) >> 4 = 0x00 = AM_NONE`
- `D_ALIGN_CHAOTIC (0x10) >> 4 = 0x01 = AM_CHAOTIC`
- `D_ALIGN_NEUTRAL (0x20) >> 4 = 0x02 = AM_NEUTRAL`
- `D_ALIGN_LAWFUL  (0x40) >> 4 = 0x04 = AM_LAWFUL`

so the conversion to `flags.align`'s raw `AM_*` layout is exact for
all four values.

The first half of the assignment (`flags.align = ((tlevel->flags &
D_ALIGN_MASK) >> 4)`) is left untouched. That path serves
per-level alignment overrides written into a level's own flags
table — a use-case where the level definition author has knowingly
opted into the bit-packed encoding — and is the right place to
preserve backward compatibility with existing level files.

A wider fix that moves `D_ALIGN_*` out of bits 4-6 entirely is
also possible but would break the on-disk save format.

**Verified locally:** the standalone `repro.c` shows the math
collision; the proposed fix is reflected in the `if-the-fix-were-
applied` block of repro.c (the `>> 4` computation that uses
`tmpdungeon.align`).  The JavaScript port at
[davidbau/teleport](https://github.com/davidbau/teleport) reproduces
the bug verbatim today (Tutorial monster weights match the
`AM_CHAOTIC` C output bit-for-bit); see LORE entry "22. The
UNCONNECTED / D_ALIGN_CHAOTIC bitfield collision" for the trace
that surfaced the bug originally.

## Test artifacts

- `repro.c` — standalone C program; no NetHack headers, no linking,
  no recorder. Hard-codes the relevant macros from `align.h` and
  `dgn_file.h` and exercises both the `init_level` fallback
  expression and the proposed-fix expression.
- `repro.sh` — wrapper: compiles `repro.c` with `${CC:-cc}` and
  reports exit status.
- `proposed-fix.patch` — the one-line diff against vanilla
  `src/dungeon.c`.

No `session.json` for this bug: the symptom (monster-weight bias)
is not screen-visible without per-spawn instrumentation, and the
collision is fully demonstrable through pure bit math. A future
addition could record a wizmode session that uses `#wizgenesis`
to spawn N monsters on tut-1 and asserts the species distribution
follows the AM_CHAOTIC bias — but the static repro is the
authoritative reproducer; an empirical session would be
supplementary evidence.
