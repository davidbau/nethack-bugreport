/*
 * repro.c -- bug 17: alter_cost() passes the current shopkeeper back to
 * next_shkp(), which starts its scan AT its argument.
 *
 * This program contains next_shkp() and the loop from alter_cost() as they
 * are in src/shk.c at NetHack 5.0.0 (16ff59115), with the monster and bill
 * structures cut down to the fields those two functions read.  It runs the
 * loop on a level with two shopkeepers who both have unpaid items on their
 * bills, and asks about an object on the SECOND one's bill.
 *
 * The upstream loop never gets past the first shopkeeper; here it is capped
 * at 1000 iterations so the program can report that instead of hanging.
 * The proposed loop (advance with shkp->nmon, as every other walk over
 * shopkeepers in shk.c does) finds the second shopkeeper on its second step.
 *
 * Exit status: 0 = upstream loop does not terminate (bug present in this
 * model), 1 = it terminates.
 */
#include <stdio.h>

typedef int boolean;
#define TRUE 1
#define FALSE 0

struct bill_x { unsigned bo_id; long price; };
struct eshk { int billct; struct bill_x bill[4]; };
struct monst {
    struct monst *nmon;
    const char *name;
    boolean dead, isshk;
    struct eshk eshk;
};
#define DEADMONSTER(m) ((m)->dead)
#define ESHK(m) (&(m)->eshk)
struct obj { unsigned o_id; };

/* src/shk.c, next_shkp(), minus the ANGRY()/rile_shk() side effect */
static struct monst *
next_shkp(struct monst *shkp, boolean withbill)
{
    for (; shkp; shkp = shkp->nmon) {
        if (DEADMONSTER(shkp))
            continue;
        if (shkp->isshk && (ESHK(shkp)->billct || !withbill))
            break;
    }
    return shkp;
}

/* src/shk.c, onbill(), reduced to the id match */
static struct bill_x *
onbill(struct obj *obj, struct monst *shkp)
{
    int ct;

    for (ct = 0; ct < ESHK(shkp)->billct; ct++)
        if (ESHK(shkp)->bill[ct].bo_id == obj->o_id)
            return &ESHK(shkp)->bill[ct];
    return (struct bill_x *) 0;
}

#define CAP 1000

/* the loop from alter_cost(); returns the shopkeeper found (or null) and
   the number of iterations, stopping at CAP */
static struct monst *
walk(struct monst *fmon, struct obj *obj, boolean proposed, int *iters)
{
    struct monst *shkp;

    *iters = 0;
    for (shkp = next_shkp(fmon, TRUE); shkp;
         shkp = proposed ? next_shkp(shkp->nmon, TRUE)
                         : next_shkp(shkp, TRUE)) {  /* upstream */
        if (++*iters > CAP)
            return shkp;
        if (onbill(obj, shkp))
            return shkp;
    }
    return (struct monst *) 0;
}

int
main(void)
{
    /* fmon -> newt -> Jonzac (bill: short sword #101)
                    -> jackal -> Ayancik (bill: chain mail #202) */
    struct monst ayancik = { 0, "Ayancik", FALSE, TRUE,
                             { 1, { { 202, 100 } } } };
    struct monst jackal = { &ayancik, "jackal", FALSE, FALSE, { 0 } };
    struct monst jonzac = { &jackal, "Jonzac", FALSE, TRUE,
                            { 1, { { 101, 13 } } } };
    struct monst newt = { &jonzac, "newt", FALSE, FALSE, { 0 } };
    struct obj chain_mail = { 202 }, short_sword = { 101 };
    struct monst *found;
    int n, loops = 0;

    printf("Two shopkeepers with bills; fmon order: newt, Jonzac, jackal,"
           " Ayancik.\n\n");

    found = walk(&newt, &short_sword, FALSE, &n);
    printf("upstream, object on Jonzac's bill (first):  %-8s after %d step%s\n",
           found ? found->name : "(none)", n, n == 1 ? "" : "s");

    found = walk(&newt, &chain_mail, FALSE, &n);
    printf("upstream, object on Ayancik's bill (second): ");
    if (n > CAP) {
        printf("still on %s after %d steps -- infinite loop\n",
               found->name, CAP);
        loops = 1;
    } else {
        printf("%-8s after %d steps\n", found ? found->name : "(none)", n);
    }

    found = walk(&newt, &chain_mail, TRUE, &n);
    printf("proposed, object on Ayancik's bill (second): %-8s after %d steps\n",
           found ? found->name : "(none)", n);

    printf("\n%s\n", loops
           ? "BUG: next_shkp(shkp, TRUE) returns shkp itself, so the upstream"
             " loop\nnever advances past a shopkeeper whose bill lacks obj."
           : "No infinite loop in this model.");
    return loops ? 0 : 1;
}
