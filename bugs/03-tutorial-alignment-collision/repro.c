/*
 * repro.c — Demonstrate the Tutorial dungeon flags-byte/alignment bit
 * collision documented in
 *   nethack-bugreport/bugs/03-tutorial-alignment-collision/README.md
 *
 * Self-contained: no NetHack headers, no linking. Just compile and run:
 *   cc -o repro repro.c && ./repro
 *
 * Exits 0 if the collision is present (the parsed alignment disagrees
 * with what init_level's bit-extraction produces); 1 if it is absent.
 * Also prints how the 3-bit dungeons[].flags.align field truncates the
 * D_ALIGN_* values stored in it.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Copied verbatim from nethack-c/include/align.h. */
#define AM_NONE         0x00
#define AM_CHAOTIC      0x01
#define AM_NEUTRAL      0x02
#define AM_LAWFUL       0x04

/* Copied verbatim from nethack-c/include/dgn_file.h. */
#define MAZELIKE        0x04
#define ROGUELIKE       0x08
#define UNCONNECTED     0x10
#define D_ALIGN_NONE    0
#define D_ALIGN_CHAOTIC (AM_CHAOTIC << 4)   /* = 0x10 — COLLIDES with UNCONNECTED */
#define D_ALIGN_NEUTRAL (AM_NEUTRAL << 4)
#define D_ALIGN_LAWFUL  (AM_LAWFUL  << 4)
#define D_ALIGN_MASK    0x70

/* The Tutorial dungeon's flags as written in dat/dungeon.lua:
 *   flags = { "mazelike", "unconnected" }
 * are processed by get_dgn_flags(), which OR-merges:
 *   MAZELIKE  = 0x04
 *   UNCONNECTED = 0x10
 *   --------------- = 0x14
 */
#define TUTORIAL_DGN_FLAGS  (MAZELIKE | UNCONNECTED)

/* The Tutorial dungeon has NO `alignment = ...` key, so get_dgn_align()
 * returns the default "unaligned" -> D_ALIGN_NONE.  This is stored
 * properly in tmpdungeon[dgn].align (dungeon.c:1057):
 *   pd->tmpdungeon[dngidx].align = dgn_align;
 */
#define TUTORIAL_PARSED_ALIGN  D_ALIGN_NONE

static const char *
align_name(int am)
{
    switch (am) {
        case AM_NONE:    return "AM_NONE";
        case AM_CHAOTIC: return "AM_CHAOTIC";
        case AM_NEUTRAL: return "AM_NEUTRAL";
        case AM_LAWFUL:  return "AM_LAWFUL";
        default:         return "<unknown>";
    }
}

int
main(void)
{
    int tutorial_flags        = TUTORIAL_DGN_FLAGS;
    int tutorial_parsed_align = TUTORIAL_PARSED_ALIGN;

    /* init_level()'s fallback expression at dungeon.c:590-591:
     *
     *   if (!new_level->flags.align)
     *       new_level->flags.align =
     *           ((pd->tmpdungeon[dgn].flags & D_ALIGN_MASK) >> 4);
     */
    int init_level_fallback = (tutorial_flags & D_ALIGN_MASK) >> 4;

    /* The alignment the Lua loader stored at dungeon.c:1057, shifted
     * to the AM_* layout flags.align uses.
     */
    int parsed_align = tutorial_parsed_align >> 4;

    printf("Tutorial dungeon definition:\n");
    printf("    dat/dungeon.lua flags = { mazelike, unconnected }\n");
    printf("    --> raw bitmask                                  = 0x%02x\n", tutorial_flags);
    printf("    Lua-parsed `alignment` (absent --> default)      = D_ALIGN_NONE (0x%02x)\n",
           tutorial_parsed_align);
    printf("    stored in tmpdungeon[Tutorial].align             = 0x%02x\n",
           tutorial_parsed_align);
    printf("\n");

    printf("init_level()'s fallback uses .flags, not .align:\n");
    printf("    (tutorial_flags & D_ALIGN_MASK)       = 0x%02x\n",
           tutorial_flags & D_ALIGN_MASK);
    printf("    >> 4                                   = 0x%02x   (%s)\n",
           init_level_fallback, align_name(init_level_fallback));
    printf("\n");

    printf("Bit collision:\n");
    printf("    UNCONNECTED (0x10) and D_ALIGN_CHAOTIC (0x10) occupy the same\n");
    printf("    bit position in the dgn_file flags byte.  init_level extracts\n");
    printf("    bits 4-6 as the alignment fallback, so any dungeon with the\n");
    printf("    UNCONNECTED flag set is silently treated as chaotic-aligned.\n");
    printf("\n");

    printf("The parsed alignment (what the Lua table says):\n");
    printf("    tmpdungeon[dgn].align >> 4             = 0x%02x   (%s)\n",
           parsed_align, align_name(parsed_align));
    printf("\n");

    /* svd.dungeons[].flags.align is Bitfield(align, 3) (include/dungeon.h)
     * and dungeon.c:1103 stores the unshifted D_ALIGN_* value in it. */
    {
        static const int dal[] = { D_ALIGN_CHAOTIC, D_ALIGN_NEUTRAL,
                                   D_ALIGN_LAWFUL };
        struct { unsigned align : 3; } df;
        int i;

        printf("Dungeon-wide alignment, stored in a 3-bit bitfield:\n");
        for (i = 0; i < 3; i++) {
            df.align = (unsigned) dal[i] & 7U; /* what the bitfield keeps */
            printf("    D_ALIGN 0x%02x -> svd.dungeons[].flags.align = %u   (%s)\n",
                   dal[i], df.align, align_name((int) df.align));
        }
        printf("\n");
    }

    if (init_level_fallback != parsed_align) {
        printf("BUG REPRODUCED: init_level fallback yields %s, but the\n",
               align_name(init_level_fallback));
        printf("Lua-parsed alignment is %s.\n", align_name(parsed_align));
        printf("\n");
        printf("Downstream effect: align_shift() (makemon.c:1611) reads\n");
        printf("flags.align and biases monster generation toward chaotic\n");
        printf("monsters on Tutorial levels.  See the README.\n");
        return 0;
    }

    printf("BUG NOT REPRODUCED: init_level fallback agrees with the\n");
    printf("parsed alignment.  The constants copied above no longer\n");
    printf("collide.\n");
    return 1;
}
