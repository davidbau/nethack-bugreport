/*
 * Unbounded ACSL/WP proof of the polymorph form-generation protocol.
 *
 * Unlike the CBMC pilot, choices are explicit arguments.  WP therefore proves
 * the assertions for every allowed choice without a loop or recursion bound.
 * This remains a protocol model; README.md and ASSESSMENT.md state the proof
 * obligations needed to refine it to the complete NetHack translation unit.
 */

/* The identity-guard model allows callback choices 0..IDENTITY_MAX_CHOICE.
 * The default, 2, is the no-ABA contract: no callback reinstalls the owner
 * form.  run-wp.sh also builds with -DIDENTITY_MAX_CHOICE=3, admitting the
 * same-form reinstallation, and requires WP to FAIL: a negative control
 * showing that identity guards alone cannot exclude ABA. */
#ifndef IDENTITY_MAX_CHOICE
#define IDENTITY_MAX_CHOICE 2
#endif

#include <limits.h>

#define FORM_HUMAN 0
#define FORM_TARGET 1
#define FORM_OTHER 2

/* Semantic form classes for the reachable nested callbacks.  A petrifying
 * non-stone golem becomes FORM_STONE_GOLEM; rehumanize becomes FORM_BASE.
 * These are deliberately separate from the three display forms above. */
#define FORM_BASE 0
#define FORM_NONSTONE_GOLEM 1
#define FORM_STONE_GOLEM 2
#define FORM_OTHER_KIND 3

struct world {
    int form;
    int form_epoch;
    int light_source;
    int cleanup_seen;
    int cleanup_epoch;
};

static struct world w;

/*@
  predicate valid_kind(integer kind) = FORM_BASE <= kind <= FORM_OTHER_KIND;
*/

/*@
  requires valid_kind(owner);
  requires 0 <= callback <= 2;
  assigns \nothing;
  ensures valid_kind(\result);
  ensures callback == 0 ==> \result == owner;
  ensures callback == 1 ==> \result == FORM_BASE;
  ensures callback == 2 && owner == FORM_NONSTONE_GOLEM
          ==> \result == FORM_STONE_GOLEM;
  ensures callback == 2 && owner != FORM_NONSTONE_GOLEM
          ==> \result == owner;
*/
static int
nested_kind(int owner, int callback)
{
    if (callback == 0)
        return owner;
    if (callback == 1)
        return FORM_BASE;
    if (owner == FORM_NONSTONE_GOLEM)
        return FORM_STONE_GOLEM;
    return owner;
}

/*@
  requires valid_kind(owner);
  requires owner != FORM_BASE;
  requires 0 <= callback <= 2;
  assigns \nothing;
  ensures callback == 0 || callback == 2 && owner != FORM_NONSTONE_GOLEM
       || (callback == 1 && owner != FORM_BASE)
       || (callback == 2 && owner == FORM_NONSTONE_GOLEM);
*/
static void
prove_nested_change_is_not_aba(int owner, int callback)
{
    int next = nested_kind(owner, callback);
    if (callback == 1)
        //@ assert next == FORM_BASE && next != owner;
        return;
    if (callback == 2 && owner == FORM_NONSTONE_GOLEM)
        //@ assert next == FORM_STONE_GOLEM && next != owner;
        return;
    //@ assert callback == 0 || (callback == 2 && owner != FORM_NONSTONE_GOLEM);
}

/*@
  requires valid_kind(owner);
  requires owner != FORM_BASE;
  requires 0 <= c0 <= 2;
  requires 0 <= c1 <= 2;
  assigns \nothing;
*/
static void
prove_two_nested_callbacks_no_aba(int owner, int c0, int c1)
{
    int first = nested_kind(owner, c0);
    int second = nested_kind(first, c1);
    prove_nested_change_is_not_aba(owner, c0);
    if (first != owner)
        //@ assert second != owner;
        return;
    /* The only same-form first callback is a no-op or a failed
     * petrification.  A second callback has the same endpoint rule. */
    if (c1 == 0 || (c1 == 2 && owner != FORM_NONSTONE_GOLEM))
        //@ assert second == owner;
        return;
    //@ assert c1 == 1 || (c1 == 2 && owner == FORM_NONSTONE_GOLEM);
    //@ assert second != owner;
}

/*@
  predicate valid_form(integer form) =
      FORM_HUMAN <= form <= FORM_OTHER;

  predicate light_consistent{L} =
      w.light_source == (w.form == FORM_TARGET);
*/

/*@
  requires valid_form(form);
  assigns \nothing;
  ensures \result == (form == FORM_TARGET);
*/
static int
emits_light(int form)
{
    return form == FORM_TARGET;
}

/*@
  assigns w;
  ensures w.form == FORM_HUMAN;
  ensures w.form_epoch == 0;
  ensures w.light_source == 0;
  ensures w.cleanup_seen == 0;
  ensures w.cleanup_epoch == -1;
  ensures light_consistent;
*/
static void
reset_world(void)
{
    w.form = FORM_HUMAN;
    w.form_epoch = 0;
    w.light_source = 0;
    w.cleanup_seen = 0;
    w.cleanup_epoch = -1;
}

/*@
  requires valid_form(next);
  requires valid_form(w.form);
  requires 0 <= w.form_epoch < INT_MAX;
  requires light_consistent;
  assigns w.form, w.form_epoch, w.light_source;
  ensures w.form == next;
  ensures w.form_epoch == \old(w.form_epoch) + 1;
  ensures light_consistent;
*/
static void
install_form(int next)
{
    int old_light = emits_light(w.form);
    int new_light;

    w.form = next;
    ++w.form_epoch;
    new_light = emits_light(w.form);
    if (old_light != new_light)
        w.light_source = new_light;

    //@ assert light_consistent;
}

/*@
  requires w.cleanup_seen == 0 || w.cleanup_epoch != w.form_epoch;
  assigns w.cleanup_seen, w.cleanup_epoch;
  ensures w.cleanup_seen == 1;
  ensures w.cleanup_epoch == w.form_epoch;
*/
static void
cleanup_current_form(void)
{
    w.cleanup_seen = 1;
    w.cleanup_epoch = w.form_epoch;
}

/*@
  requires 0 <= choice <= 3;
  requires valid_form(w.form);
  requires 0 <= w.form_epoch < 99;
  requires light_consistent;
  requires w.cleanup_seen == 0 || w.cleanup_epoch <= w.form_epoch;
  assigns w;
  ensures light_consistent;
  ensures valid_form(w.form);
  ensures choice == 0 ==> w.form_epoch == \old(w.form_epoch);
  ensures choice != 0 ==> w.form_epoch == \old(w.form_epoch) + 1;
  ensures choice == 0 ==> w.form == \old(w.form);
  ensures choice == 0 ==> w.cleanup_seen == \old(w.cleanup_seen);
  ensures choice == 0 ==> w.cleanup_epoch == \old(w.cleanup_epoch);
  ensures choice == 1 ==> w.form == FORM_HUMAN;
  ensures choice == 2 ==> w.form == FORM_OTHER;
  ensures choice == 3 ==> w.form == FORM_TARGET;
  ensures choice != 0 ==> w.cleanup_epoch == w.form_epoch;
  ensures 0 <= w.form_epoch < 100;
  ensures w.cleanup_seen == 0 || w.cleanup_epoch <= w.form_epoch;
*/
static void
nested_change(int choice)
{
    if (choice == 0)
        return;
    if (choice == 1)
        install_form(FORM_HUMAN);
    else if (choice == 2)
        install_form(FORM_OTHER);
    else
        install_form(FORM_TARGET);
    cleanup_current_form();
}

/*@
  requires 0 <= choice <= 3;
  requires valid_form(w.form);
  requires 0 <= w.form_epoch < 99;
  requires owner_epoch == w.form_epoch;
  requires light_consistent;
  requires w.cleanup_seen == 0;
  assigns w;
  ensures light_consistent;
  ensures valid_form(w.form);
  ensures 0 <= w.form_epoch < 100;
  ensures w.cleanup_seen == 0 || w.cleanup_epoch <= w.form_epoch;
  ensures \result == 0 ==> w.form_epoch == owner_epoch;
  ensures \result == 0 ==> w.form_epoch == \old(w.form_epoch);
  ensures \result == 0 ==> w.cleanup_seen == 0;
*/
static int
epoch_boundary(int choice, int owner_epoch)
{
    nested_change(choice);
    if (w.form_epoch != owner_epoch)
        return 1;
    //@ assert choice == 0;
    //@ assert w.cleanup_seen == 0;
    //@ assert w.form_epoch == owner_epoch;
    return 0;
}

/*@
  requires 0 <= choice <= IDENTITY_MAX_CHOICE;
  requires valid_form(w.form);
  requires 0 <= w.form_epoch < 99;
  requires owner_form == FORM_TARGET;
  requires w.form == owner_form;
  requires light_consistent;
  requires w.cleanup_seen == 0;
  assigns w;
  ensures light_consistent;
  ensures valid_form(w.form);
  ensures 0 <= w.form_epoch < 100;
  ensures w.cleanup_seen == 0 || w.cleanup_epoch <= w.form_epoch;
  ensures \result == 0 ==> w.form == owner_form;
  ensures \result == 0 ==> w.form_epoch == \old(w.form_epoch);
  ensures \result == 0 ==> w.cleanup_seen == 0;
*/
static int
identity_boundary_no_aba(int choice, int owner_form)
{
    int owner_epoch = w.form_epoch;

    nested_change(choice);
    if (w.form != owner_form)
        return 1;
    /* choice 3 (same-target reinstall) is excluded by the contract. */
    //@ assert choice == 0;
    //@ assert w.cleanup_seen == 0;
    //@ assert w.form_epoch == owner_epoch;
    return 0;
}

/* Generation guards remain sound even when the nested callback performs an
 * arbitrary ABA transition.  Choice 3 deliberately reinstalls the owner
 * form, which is the case identity-only guards cannot distinguish. */
/*@
  requires 0 <= choice <= 3;
  requires valid_form(w.form);
  requires 0 <= w.form_epoch < 99;
  requires owner_epoch == w.form_epoch;
  requires light_consistent;
  assigns w;
  ensures light_consistent;
  ensures valid_form(w.form);
  ensures \result == 0 ==> w.form_epoch == owner_epoch;
  ensures \result == 1 ==> w.form_epoch != owner_epoch;
*/
static int
generation_boundary_arbitrary_aba(int choice, int owner_epoch)
{
    if (choice == 1)
        install_form(FORM_HUMAN);
    else if (choice == 2)
        install_form(FORM_OTHER);
    else if (choice == 3)
        install_form(FORM_TARGET);
    if (w.form_epoch != owner_epoch)
        return 1;
    //@ assert choice == 0;
    return 0;
}

/* A callback may install any number of forms before it returns: rehumanize,
 * then a polymorph trap, then another.  kinds[0..n-1] lists them (each one
 * of FORM_HUMAN, FORM_TARGET, FORM_OTHER, so A->B->A chains of any length are
 * included).  The loop invariant carries the one fact the guard needs: after
 * i installations the generation is exactly i past where it started. */
/*@
  requires 0 <= n;
  requires \valid_read(kinds + (0 .. n - 1));
  requires \forall integer j; 0 <= j < n ==> valid_form(kinds[j]);
  requires valid_form(w.form);
  requires 0 <= w.form_epoch;
  requires w.form_epoch <= INT_MAX - n;
  requires light_consistent;
  assigns w.form, w.form_epoch, w.light_source;
  ensures w.form_epoch == \old(w.form_epoch) + n;
  ensures valid_form(w.form);
  ensures light_consistent;
*/
static void
nested_installs(int n, const int *kinds)
{
    int i;

    /*@
      loop invariant 0 <= i <= n;
      loop invariant w.form_epoch == \at(w.form_epoch, Pre) + i;
      loop invariant valid_form(w.form);
      loop invariant light_consistent;
      loop assigns i, w.form, w.form_epoch, w.light_source;
      loop variant n - i;
    */
    for (i = 0; i < n; ++i)
        install_form(kinds[i]);
}

/* The boundary argument without the one-installation-per-callback limit:
 * the guard lets the owner continue exactly when the callback installed
 * nothing. */
/*@
  requires 0 <= n;
  requires \valid_read(kinds + (0 .. n - 1));
  requires \forall integer j; 0 <= j < n ==> valid_form(kinds[j]);
  requires valid_form(w.form);
  requires 0 <= w.form_epoch;
  requires w.form_epoch <= INT_MAX - n;
  requires owner_epoch == w.form_epoch;
  requires light_consistent;
  assigns w.form, w.form_epoch, w.light_source;
  ensures light_consistent;
  ensures valid_form(w.form);
  ensures \result == 0 <==> n == 0;
  ensures \result == 0 ==> w.form_epoch == owner_epoch;
*/
int
generation_boundary_any_installs(int n, const int *kinds, int owner_epoch)
{
    nested_installs(n, kinds);
    if (w.form_epoch != owner_epoch)
        return 1;
    //@ assert n == 0;
    return 0;
}

/*@
  requires 0 <= c0 <= 3;
  requires 0 <= c1 <= 3;
  requires 0 <= c2 <= 3;
  requires 0 <= c3 <= 3;
  requires 0 <= c4 <= 3;
  assigns w;
  ensures light_consistent;
*/
void
verify_polymon_epoch(int c0, int c1, int c2, int c3, int c4)
{
    int owner_epoch;

    reset_world();
    install_form(FORM_TARGET);
    owner_epoch = w.form_epoch;

    if (epoch_boundary(c0, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c1, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c2, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c3, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c4, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    cleanup_current_form();
}

/*@
  requires 0 <= c0 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c1 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c2 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c3 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c4 <= IDENTITY_MAX_CHOICE;
  assigns w;
  ensures light_consistent;
*/
void
verify_polymon_identity_no_aba(int c0, int c1, int c2, int c3, int c4)
{
    reset_world();
    install_form(FORM_TARGET);

    if (identity_boundary_no_aba(c0, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c1, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c2, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c3, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c4, FORM_TARGET)) return;
    cleanup_current_form();
}

/*@
  requires 0 <= c0 <= 3;
  requires 0 <= c1 <= 3;
  requires 0 <= c2 <= 3;
  requires 0 <= c3 <= 3;
  requires 0 <= c4 <= 3;
  assigns w;
  ensures light_consistent;
*/
void
verify_polymon_generation_arbitrary_aba(int c0, int c1, int c2, int c3, int c4)
{
    int owner_epoch;

    reset_world();
    install_form(FORM_TARGET);
    owner_epoch = w.form_epoch;

    if (generation_boundary_arbitrary_aba(c0, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c1, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c2, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c3, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c4, owner_epoch)) return;
}

/*@
  requires 0 <= c0 <= 3;
  requires 0 <= c1 <= 3;
  requires 0 <= c2 <= 3;
  assigns w;
  ensures light_consistent;
*/
void
verify_break_armor_epoch(int c0, int c1, int c2)
{
    int owner_epoch;

    reset_world();
    install_form(FORM_TARGET);
    owner_epoch = w.form_epoch;

    if (epoch_boundary(c0, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c1, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
    if (epoch_boundary(c2, owner_epoch)) return;
    //@ assert w.form_epoch == owner_epoch;
}

/*@
  requires 0 <= c0 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c1 <= IDENTITY_MAX_CHOICE;
  requires 0 <= c2 <= IDENTITY_MAX_CHOICE;
  assigns w;
  ensures light_consistent;
*/
void
verify_break_armor_identity_no_aba(int c0, int c1, int c2)
{
    reset_world();
    install_form(FORM_TARGET);

    if (identity_boundary_no_aba(c0, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c1, FORM_TARGET)) return;
    if (identity_boundary_no_aba(c2, FORM_TARGET)) return;
}

/*@
  requires 0 <= c0 <= 3;
  requires 0 <= c1 <= 3;
  requires 0 <= c2 <= 3;
  assigns w;
  ensures light_consistent;
*/
void
verify_break_armor_generation_arbitrary_aba(int c0, int c1, int c2)
{
    int owner_epoch;

    reset_world();
    install_form(FORM_TARGET);
    owner_epoch = w.form_epoch;

    if (generation_boundary_arbitrary_aba(c0, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c1, owner_epoch)) return;
    if (generation_boundary_arbitrary_aba(c2, owner_epoch)) return;
}

/*@
  requires 0 <= choice <= 3;
  assigns w;
  ensures light_consistent;
*/
void
verify_light_protocol(int choice)
{
    reset_world();
    install_form(FORM_TARGET);
    nested_change(choice);
    //@ assert light_consistent;
}
