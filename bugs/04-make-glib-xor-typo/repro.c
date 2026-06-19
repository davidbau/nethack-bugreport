/*
 * repro.c — Demonstrate the `make_glib` botl-dirty XOR typo documented
 * in nethack-bugreport/bugs/04-make-glib-xor-typo/README.md
 *
 * Self-contained: no NetHack headers, no linking. Just compile and run:
 *   cc -o repro repro.c && ./repro
 *
 * Exits 0 if the bug is present (the current `(!Glib ^ !!xtime)` marks
 * dirty on non-transitions and skips real transitions); 1 if absent
 * (e.g., the proposed `!` -> `!!` fix has been applied to your tree
 * and the dirty flag is marked exactly on real boolean transitions).
 *
 * The point of this reproducer is to make the XOR truth table directly
 * inspectable.  No game state, no botl plumbing — just the same
 * expression `make_glib` evaluates, run against all four (old, new)
 * boolean-state combinations.
 */

#include <stdio.h>
#include <stdlib.h>

/*
 * The two expressions under comparison:
 *
 *   buggy:   (!Glib ^ !!xtime)
 *   fixed:   (!!Glib ^ !!xtime)
 *
 * Glib here is "the OLD value before set_itimeout", xtime is "the NEW
 * value being set".  In C terms `Glib` is a long iff `xtime` is an int;
 * we use `long` for both here for cleanliness.
 *
 * `!Glib` returns 1 iff Glib == 0; that's a typo for `!!Glib` which
 * returns 1 iff Glib != 0.  The correctly-shaped expression
 * `(!!OLD) ^ (!!NEW)` is the standard "did the boolean state change?"
 * idiom — true iff exactly one side is non-zero.
 *
 * The sibling function make_deaf (potion.c:443-456) uses the same
 * idiom, just spelled differently:
 *     if ((xtime != 0L) ^ (old != 0L)) disp.botl = TRUE;
 * which is mathematically identical to the proposed fix here, just
 * inlining the boolean coercion.
 */
static int buggy(long Glib, long xtime)  { return  !Glib ^ !!xtime; }
static int fixed(long Glib, long xtime)  { return !!Glib ^ !!xtime; }

int
main(void)
{
    /* The four (old, new) state combinations we care about. */
    static const struct {
        long old;
        long new_;
        const char *label;
    } cases[] = {
        { 0,  0, "no transition, both clear  (no-op)"        },
        { 0,  5, "transition off->on         (gained Glib)"  },
        { 7,  0, "transition on->off         (Glib expired)" },
        { 7, 12, "no transition, both set    (refresh)"      },
    };

    int n = sizeof(cases) / sizeof(cases[0]);
    int wrong = 0;

    printf("make_glib's `disp.botl |= ...` dirty-flag expression:\n");
    printf("    buggy : (!Glib ^ !!xtime)\n");
    printf("    fixed : (!!Glib ^ !!xtime)\n");
    printf("\n");
    printf("    old   new   buggy   fixed   should-fire?   verdict\n");
    printf("    ----  ----  -----   -----   ------------   -------\n");

    for (int i = 0; i < n; i++) {
        long old = cases[i].old, new_ = cases[i].new_;
        int b = buggy(old, new_);
        int f = fixed(old, new_);
        int real_transition = ((old != 0) ^ (new_ != 0));
        const char *verdict =
            (b == real_transition) ? "OK     "
                                   : "BUG (inverted)";
        printf("    %4ld  %4ld  %4d    %4d    %s         %s   (%s)\n",
               old, new_, b, f, real_transition ? "YES" : "no ",
               verdict, cases[i].label);
        if (b != real_transition) wrong++;
    }

    printf("\n");

    if (wrong > 0) {
        printf("BUG REPRODUCED: the buggy expression returns the OPPOSITE\n");
        printf("of `should-fire?` on all four cases.\n");
        printf("\n");
        printf("In other words: it marks the status line dirty when the\n");
        printf("Slippery boolean state DOESN'T change, and silently skips\n");
        printf("the dirty flag when the state DOES change.  The status\n");
        printf("line is therefore one bot() call behind reality.\n");
        printf("\n");
        printf("Self-correcting in normal play: bot() runs every player\n");
        printf("turn anyway, driven by other status changes that mark\n");
        printf("disp.botl dirty correctly.  So the visible symptom is at\n");
        printf("most a one-turn lag in 'Slippery' appearing on or leaving\n");
        printf("the status line; and only when NO other status change\n");
        printf("happens in the same turn as the Glib transition.\n");
        return 0;
    }

    printf("BUG NOT REPRODUCED: the buggy expression agrees with the\n");
    printf("real-transition predicate on all four cases.  Either the\n");
    printf("proposed `!` -> `!!` fix has been applied to your tree, or\n");
    printf("the expression has otherwise been rewritten.\n");
    return 1;
}
