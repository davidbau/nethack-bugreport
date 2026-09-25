/*
 * polyself_acsl.c -- the generation invariant of PR #1681, proved with
 * Frama-C/WP.  run-wp.sh checks every function below against its contract.
 *
 * THE INVARIANT
 *
 * Every running polymon() or break_armor() remembers the generation that was
 * current when it started (its "saved generation" g).  The patch keeps:
 *
 *   (1) The counter only goes up: every form installation adds exactly one.
 *   (2) So g equals the counter exactly when no form has been installed since
 *       g was saved.  We say the call OWNS the current form.  Once anything is
 *       installed, g is below the counter for good: the call is STALE.
 *   (3) A call applies an effect of its form only while it owns it.  After
 *       every callback that could install a form there is a checkpoint,
 *           if (uasmon_generation != my_generation) return 1;
 *       so a stale call can only return.
 *
 * Bug 08 is a stale break_armor() stripping gear by the old form's rules.
 * Bug 06 is a stale polymon() repeating the cleanup its successor already ran.
 * Bug 07 breaks a second, smaller invariant: a light source exists exactly
 * when the installed form emits light.
 *
 * THE MODEL
 *
 * The world is the installed form, the generation counter, the hero's light
 * source, and which generation was last cleaned up.  A callback that may
 * re-enter (break_armor(), expels(), spoteffects(), retouch_equipment(), ...)
 * is modelled as "installs any number of forms, of any kind, in any order,
 * each finished by its own installer, cleanup included".  That covers
 * everything the real callbacks can do to the form, A->B->A chains included.
 *
 * Reading order: the predicates, install_form() (property 1 and the light
 * invariant), cleanup_form(), callback(), checkpoint() (properties 2 and 3),
 * the two operations polymon_model() and break_armor_model(), and last the
 * identity-guard contrast used by run-wp.sh's negative control.
 */

#include <limits.h>

#define FORM_HUMAN 0
#define FORM_TARGET 1 /* the form polymon() installs; it emits light */
#define FORM_OTHER 2

/* A generous bound so that the counter provably cannot overflow in the
 * model; the patch itself panics rather than let the real counter wrap. */
#define MAX_GEN 100000
#define MAX_INSTALLS 1000

struct world {
    int form;        /* u.umonnum / gy.youmonst.data                     */
    int gen;         /* uasmon_generation                                */
    int light;       /* an LS_MONSTER light source exists for the hero   */
    int cleaned_gen; /* the generation whose cleanup last ran; -1 = none */
};

static struct world w;

/*@
  predicate valid_form(integer f) = FORM_HUMAN <= f <= FORM_OTHER;

  // (2): the call whose saved generation is g owns the installed form...
  predicate owns(integer g) = g == w.gen;
  // ...or has been overtaken by a later installation.
  predicate stale(integer g) = g < w.gen;

  // Bug 07's invariant: a light source exists exactly when the form glows.
  predicate light_ok = w.light == (w.form == FORM_TARGET);

  // Everything that is true between any two steps of the model.
  predicate world_ok =
      valid_form(w.form) && light_ok
      && 0 <= w.gen <= MAX_GEN && -1 <= w.cleaned_gen <= w.gen;

  // The installed form has not had its cleanup yet.
  predicate not_cleaned_yet = w.cleaned_gen < w.gen;
*/

/*@
  assigns w;
  ensures world_ok;
  ensures w.gen == 0 && w.form == FORM_HUMAN && w.cleaned_gen == -1;
*/
static void
reset_world(void)
{
    w.form = FORM_HUMAN;
    w.gen = 0;
    w.light = 0;
    w.cleaned_gen = -1;
}

/* One form installation, as the patch does it:
 *     u.umonnum = mntmp; set_uasmon(); uasmon_light(old_light);
 * set_uasmon() bumps the counter, and the light is updated in the same step,
 * with no re-entrant call in between. */
/*@
  requires world_ok && w.gen < MAX_GEN;
  requires valid_form(next);
  assigns w.form, w.gen, w.light;
  ensures world_ok;
  ensures w.form == next;
  ensures w.gen == \old(w.gen) + 1;   // (1) every installation adds one
  ensures not_cleaned_yet;            // a new generation starts uncleaned
*/
static void
install_form(int next)
{
    int old_light = (w.form == FORM_TARGET);

    w.form = next;
    ++w.gen;
    if (old_light != (w.form == FORM_TARGET))
        w.light = (w.form == FORM_TARGET);
}

/* The end-of-change cleanup, encumber_msg() and retouch_equipment().
 * Bug 06 is this running twice for one generation. */
/*@
  requires not_cleaned_yet;           // at most once per generation
  assigns w.cleaned_gen;
  ensures w.cleaned_gen == w.gen;
*/
static void
cleanup_form(void)
{
    w.cleaned_gen = w.gen;
}

/* A callback that may re-enter.  It installs n forms, kinds[0..n-1]; each is
 * installed by a nested polymon() or rehumanize() that finishes its own
 * setup, cleanup included, before the callback returns. */
/*@
  requires world_ok;
  requires 0 <= n <= MAX_INSTALLS && w.gen <= MAX_GEN - MAX_INSTALLS;
  requires \valid_read(kinds + (0 .. n - 1));
  requires \forall integer j; 0 <= j < n ==> valid_form(kinds[j]);
  assigns w;
  ensures world_ok;
  ensures w.gen == \old(w.gen) + n;
  ensures n > 0 ==> w.form == kinds[n - 1];
  ensures n == 0 ==> w.form == \old(w.form)
                     && w.cleaned_gen == \old(w.cleaned_gen);
*/
static void
callback(int n, const int *kinds)
{
    int i;

    /*@
      loop invariant 0 <= i <= n;
      loop invariant world_ok;
      loop invariant w.gen == \at(w.gen, Pre) + i;
      loop invariant i > 0 ==> w.form == kinds[i - 1];
      loop invariant i == 0 ==> w.form == \at(w.form, Pre)
                                && w.cleaned_gen == \at(w.cleaned_gen, Pre);
      loop assigns i, w;
      loop variant n - i;
    */
    for (i = 0; i < n; ++i) {
        install_form(kinds[i]);
        cleanup_form();
    }
}

/* THE CHECKPOINT the patch places after every callback that may re-enter:
 *     callback();
 *     if (uasmon_generation != my_generation)
 *         return 1;
 * The contract is properties (2) and (3). */
/*@
  requires world_ok;
  requires owns(g);
  requires 0 <= n <= MAX_INSTALLS && w.gen <= MAX_GEN - MAX_INSTALLS;
  requires \valid_read(kinds + (0 .. n - 1));
  requires \forall integer j; 0 <= j < n ==> valid_form(kinds[j]);
  assigns w;
  ensures world_ok;
  ensures \result == 0 <==> n == 0;   // continue exactly when nothing was installed
  ensures \result == 0 ==> owns(g)    // a call that continues still owns its form,
          && w.form == \old(w.form) && w.cleaned_gen == \old(w.cleaned_gen);
  ensures \result != 0 ==> stale(g);  // and one that stops has been overtaken
*/
int
checkpoint(int n, const int *kinds, int g)
{
    callback(n, kinds);
    if (w.gen != g)
        return 1;
    return 0;
}

/* Something the operation does on behalf of its own form: find_ac(),
 * unhiding, stripping armor by uptr's rules, selftouch().  Its precondition
 * IS property (3); WP checks it at every call. */
/*@
  requires owns(g);
  assigns \nothing;
*/
static void
owned_effect(int g)
{
    (void) g;
}

/* polymon(), boundary by boundary (the model's POLY_* list).  Each callback
 * may install any number of forms: k0..k4 list them. */
/*@
  requires 0 <= n0 <= MAX_INSTALLS && \valid_read(k0 + (0 .. n0 - 1));
  requires 0 <= n1 <= MAX_INSTALLS && \valid_read(k1 + (0 .. n1 - 1));
  requires 0 <= n2 <= MAX_INSTALLS && \valid_read(k2 + (0 .. n2 - 1));
  requires 0 <= n3 <= MAX_INSTALLS && \valid_read(k3 + (0 .. n3 - 1));
  requires 0 <= n4 <= MAX_INSTALLS && \valid_read(k4 + (0 .. n4 - 1));
  requires \forall integer j; 0 <= j < n0 ==> valid_form(k0[j]);
  requires \forall integer j; 0 <= j < n1 ==> valid_form(k1[j]);
  requires \forall integer j; 0 <= j < n2 ==> valid_form(k2[j]);
  requires \forall integer j; 0 <= j < n3 ==> valid_form(k3[j]);
  requires \forall integer j; 0 <= j < n4 ==> valid_form(k4[j]);
  assigns w;
  ensures world_ok;
*/
void
polymon_model(int n0, const int *k0, int n1, const int *k1,
              int n2, const int *k2, int n3, const int *k3,
              int n4, const int *k4)
{
    int g;

    reset_world();
    install_form(FORM_TARGET);         /* u.umonnum = mntmp; set_uasmon(); ... */
    g = w.gen;                         /* my_generation = uasmon_generation;   */

    if (checkpoint(n0, k0, g)) return; /* break_armor(); drop_weapon(1);       */
    owned_effect(g);                   /* find_ac(), unhide                    */
    if (checkpoint(n1, k1, g)) return; /* expels()                             */
    owned_effect(g);
    if (checkpoint(n2, k2, g)) return; /* instapetrify() / dismount_steed()    */
    owned_effect(g);
    if (checkpoint(n3, k3, g)) return; /* spoteffects(TRUE)                    */
    cleanup_form();                    /* encumber_msg(); retouch_equipment(2) */
    if (checkpoint(n4, k4, g)) return; /* retouch_equipment() can revert you   */
    owned_effect(g);                   /* selftouch() and the rest             */
}

/* break_armor(), sub-block by sub-block (the model's ARMOR_* list). */
/*@
  requires 0 <= n0 <= MAX_INSTALLS && \valid_read(k0 + (0 .. n0 - 1));
  requires 0 <= n1 <= MAX_INSTALLS && \valid_read(k1 + (0 .. n1 - 1));
  requires 0 <= n2 <= MAX_INSTALLS && \valid_read(k2 + (0 .. n2 - 1));
  requires \forall integer j; 0 <= j < n0 ==> valid_form(k0[j]);
  requires \forall integer j; 0 <= j < n1 ==> valid_form(k1[j]);
  requires \forall integer j; 0 <= j < n2 ==> valid_form(k2[j]);
  assigns w;
  ensures world_ok;
*/
void
break_armor_model(int n0, const int *k0, int n1, const int *k1,
                  int n2, const int *k2)
{
    int g;

    reset_world();
    install_form(FORM_TARGET);         /* the form polymon() just installed    */
    g = w.gen;                         /* my_generation = uasmon_generation;   */

    owned_effect(g);                   /* body armor, cloak, shirt by uptr     */
    if (checkpoint(n0, k0, g)) return; /* drop_weapon(0); Gloves_off(); ...    */
    owned_effect(g);                   /* shield, helmet                       */
    if (checkpoint(n1, k1, g)) return; /* before the boots block               */
    owned_effect(g);                   /* boots: Boots_off() may re-enter      */
    if (checkpoint(n2, k2, g)) return; /* before the eyewear block             */
    owned_effect(g);                   /* eyewear                              */
}

/* THE CONTRAST: the first draft of the PR compared the form instead,
 *     if (u.umonnum != mntmp) return 1;
 * That keeps property (3) only under an extra promise that no callback ever
 * reinstalls the owner's form.  run-wp.sh builds once more with
 * -DIDENTITY_ALLOW_REINSTALL, dropping that promise, and requires WP to fail
 * on exactly one goal: the assertion below.  Form numbers cannot tell
 * "nothing happened" from "y -> @ -> y"; the counter can. */
#ifdef IDENTITY_ALLOW_REINSTALL
#define NEVER_REINSTALLS(n, kinds, f) \true
#else
#define NEVER_REINSTALLS(n, kinds, f) \
    (\forall integer j; 0 <= j < (n) ==> (kinds)[j] != (f))
#endif

/*@
  requires world_ok;
  requires owns(g) && w.form == owner_form;
  requires 0 <= n <= MAX_INSTALLS && w.gen <= MAX_GEN - MAX_INSTALLS;
  requires \valid_read(kinds + (0 .. n - 1));
  requires \forall integer j; 0 <= j < n ==> valid_form(kinds[j]);
  requires NEVER_REINSTALLS(n, kinds, owner_form);
  assigns w;
  ensures world_ok;
*/
int
identity_checkpoint(int n, const int *kinds, int owner_form, int g)
{
    callback(n, kinds);
    if (w.form != owner_form)
        return 1;
    //@ assert owns(g);   // continuing is safe only if nothing was installed
    return 0;
}
