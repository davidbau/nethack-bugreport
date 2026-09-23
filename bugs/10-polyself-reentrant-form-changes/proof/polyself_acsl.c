/*
 * Unbounded ACSL/WP proof of the polymorph form-generation protocol.
 *
 * Unlike the CBMC pilot, choices are explicit arguments.  WP therefore proves
 * the assertions for every allowed choice without a loop or recursion bound.
 * This remains a protocol model; README.md and ASSESSMENT.md state the proof
 * obligations needed to refine it to the complete NetHack translation unit.
 */

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
  requires 0 <= w.form_epoch < 100;
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
  requires 0 <= choice <= 2;
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
  requires 0 <= c0 <= 2;
  requires 0 <= c1 <= 2;
  requires 0 <= c2 <= 2;
  requires 0 <= c3 <= 2;
  requires 0 <= c4 <= 2;
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
  requires 0 <= c0 <= 2;
  requires 0 <= c1 <= 2;
  requires 0 <= c2 <= 2;
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
