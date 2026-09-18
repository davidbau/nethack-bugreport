/*
 * repro.c — Demonstrate that the dwarven digging bonus doubles the
 * accumulated effort rather than the per-turn increment, documented in
 *   nethack-bugreport/bugs/11-dwarf-dig-accumulator/README.md
 *
 * Self-contained: no NetHack headers, no linking, no game build.
 *   cc -o repro repro.c && ./repro
 *
 * This is a pure-math reproducer: it contains both formulas and compares
 * them, so it cannot and does not inspect your tree.  repro.sh does that
 * part, by looking for the upstream form in src/dig.c.
 *
 * Exits 0 if the claim holds -- the upstream formula's dwarf advantage
 * drifts with the hero's other bonuses instead of being the constant 2x
 * the code reads as -- and 1 if it does not.
 */

#include <stdio.h>
#include <stdlib.h>

/* dig.c's two completion thresholds. */
#define HOLE_EFFORT  250 /* "if (svc.context.digging.effort > 250)" */
#define WALL_EFFORT  100 /* "if (svc.context.digging.effort > 100)" */

#define TRIALS 200000

/* A deterministic stand-in for rn2(5); the distribution is what matters,
 * not NetHack's exact PRNG.  Seeded once in main() so runs are stable. */
static int
rn2(int x)
{
    return (int) (rand() % x);
}

/*
 * dig.c:365-368, verbatim in shape:
 *
 *     svc.context.digging.effort +=
 *         10 + rn2(5) + abon() + uwep->spe - greatest_erosion(uwep)
 *         + u.udaminc;
 *     if (Race_if(PM_DWARF))
 *         svc.context.digging.effort *= 2;
 *
 * 'bonuses' is abon() + spe - erosion + udaminc collapsed into one number,
 * which is all the formula does with them.
 */
static int
turns_upstream(int target, int bonuses, int dwarf)
{
    int effort = 0, turns = 0;

    while (effort <= target) {
        effort += 10 + rn2(5) + bonuses;
        if (dwarf)
            effort *= 2; /* <-- the accumulator, not the increment */
        turns++;
        if (turns > 10000)
            return turns; /* cannot happen; guards a bad 'bonuses' */
    }
    return turns;
}

/* The proposed form: double the increment that was just computed. */
static int
turns_proposed(int target, int bonuses, int dwarf)
{
    int effort = 0, turns = 0;

    while (effort <= target) {
        int inc = 10 + rn2(5) + bonuses;

        if (dwarf)
            inc *= 2;
        effort += inc;
        turns++;
        if (turns > 10000)
            return turns;
    }
    return turns;
}

static double
mean_turns(int (*fn)(int, int, int), int target, int bonuses, int dwarf)
{
    long total = 0;
    int i;

    for (i = 0; i < TRIALS; i++)
        total += fn(target, bonuses, dwarf);
    return (double) total / (double) TRIALS;
}

struct scenario {
    const char *what;
    int target;
    int bonuses;
    const char *who;
};

static const struct scenario scenarios[] = {
    { "dig down  (effort > 250)", HOLE_EFFORT, 0,
      "no bonuses, plain pick-axe" },
    { "dig down  (effort > 250)", HOLE_EFFORT, 5,
      "abon 2, +3 weapon" },
    { "dig sideways (effort > 100)", WALL_EFFORT, 0,
      "no bonuses, plain pick-axe" },
    { "dig sideways (effort > 100)", WALL_EFFORT, 5,
      "abon 2, +3 weapon" },
};
#define NSCENARIOS ((int) (sizeof scenarios / sizeof scenarios[0]))

static void
spread(double *ratios, int n, double *lo, double *hi)
{
    int i;

    *lo = *hi = ratios[0];
    for (i = 1; i < n; i++) {
        if (ratios[i] < *lo)
            *lo = ratios[i];
        if (ratios[i] > *hi)
            *hi = ratios[i];
    }
}

int
main(void)
{
    int i;
    double up_ratio[NSCENARIOS], pr_ratio[NSCENARIOS];
    double up_lo, up_hi, pr_lo, pr_hi;

    srand(20260918u); /* stable output across runs */

    printf("Turns to finish a dig, mean of %d trials each.\n\n", TRIALS);

    printf("UPSTREAM  (effort *= 2 -- the running total)\n");
    printf("  %-28s  %-26s  %8s  %8s  %6s\n",
           "dig", "hero", "non-dwarf", "dwarf", "ratio");
    for (i = 0; i < NSCENARIOS; i++) {
        double plain = mean_turns(turns_upstream, scenarios[i].target,
                                  scenarios[i].bonuses, 0);
        double dwarf = mean_turns(turns_upstream, scenarios[i].target,
                                  scenarios[i].bonuses, 1);
        double ratio = plain / dwarf;

        printf("  %-28s  %-26s  %8.1f  %8.1f  %5.1fx\n",
               scenarios[i].what, scenarios[i].who, plain, dwarf, ratio);
        up_ratio[i] = ratio;
    }

    printf("\nPROPOSED  (inc *= 2 -- the per-turn increment)\n");
    printf("  %-28s  %-26s  %8s  %8s  %6s\n",
           "dig", "hero", "non-dwarf", "dwarf", "ratio");
    for (i = 0; i < NSCENARIOS; i++) {
        double plain = mean_turns(turns_proposed, scenarios[i].target,
                                  scenarios[i].bonuses, 0);
        double dwarf = mean_turns(turns_proposed, scenarios[i].target,
                                  scenarios[i].bonuses, 1);

        printf("  %-28s  %-26s  %8.1f  %8.1f  %5.1fx\n",
               scenarios[i].what, scenarios[i].who, plain, dwarf,
               plain / dwarf);
        pr_ratio[i] = plain / dwarf;
    }

    /* The per-tick totals, which show why the ratio drifts: once the
     * running total is being doubled every tick, the increment that the
     * hero's strength and weapon feed into stops mattering. */
    printf("\nEffort after each tick, with a typical increment of 12:\n");
    {
        int effort_plain = 0, effort_dwarf = 0, t;

        printf("  %-10s", "non-dwarf");
        for (t = 0; t < 5; t++) {
            effort_plain += 12;
            printf(" %6d", effort_plain);
        }
        printf("\n  %-10s", "dwarf");
        for (t = 0; t < 5; t++) {
            effort_dwarf = (effort_dwarf + 12) * 2;
            printf(" %6d", effort_dwarf);
        }
        printf("\n");
    }

    spread(up_ratio, NSCENARIOS, &up_lo, &up_hi);
    spread(pr_ratio, NSCENARIOS, &pr_lo, &pr_hi);
    printf("\nAdvantage across the four scenarios:\n");
    printf("  upstream  %.1fx to %.1fx   (spread %.1f)\n",
           up_lo, up_hi, up_hi - up_lo);
    printf("  proposed  %.1fx to %.1fx   (spread %.1f)\n",
           pr_lo, pr_hi, pr_hi - pr_lo);

    /* The proposed form lands near 1.9x rather than exactly 2.0x because
     * turns are whole numbers, so "is it 2.0" is the wrong test.  What
     * distinguishes the two forms is whether the advantage is the SAME in
     * every scenario. */
    if (up_hi - up_lo > 0.5) {
        printf("\nCLAIM CONFIRMED: the upstream advantage drifts by %.1fx "
               "across these four\nscenarios, while the proposed form holds "
               "steady within %.1fx.  Doubling the\nrunning total makes the "
               "advantage depend on how many turns the dig takes,\nso a weak "
               "dwarf with a plain pick-axe gains more than a strong one "
               "with\nan enchanted mattock.\n", up_hi - up_lo, pr_hi - pr_lo);
        return 0;
    }
    printf("\nCLAIM NOT CONFIRMED: the upstream advantage is constant here.\n");
    return 1;
}
