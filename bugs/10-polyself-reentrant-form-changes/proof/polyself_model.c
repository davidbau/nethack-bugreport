/*
 * Bounded model for NetHack PR #1681's polymorph reentrancy guards.
 *
 * This is verification-only C.  It intentionally models just the ownership
 * protocol around form installation, reentrant boundaries, cleanup, light
 * sources, and break_armor() block boundaries.  README.md records the mapping
 * to the real C and the limits of the abstraction.
 */

#include <stdbool.h>
#include <limits.h>

#define GUARD_NONE 0
#define GUARD_FORM_IDENTITY 1
#define GUARD_FORM_EPOCH 2

#ifndef GUARD_MODE
#define GUARD_MODE GUARD_FORM_IDENTITY
#endif

#ifndef OMIT_GUARD
#define OMIT_GUARD (-1)
#endif

#ifndef FORCE_BOUNDARY
#define FORCE_BOUNDARY (-1)
#endif

#ifndef ALLOW_SAME_FORM_REENTRY
#define ALLOW_SAME_FORM_REENTRY 1
#endif

#ifdef __CPROVER__
extern unsigned int nondet_uint(void);
#else
#include <assert.h>
static unsigned int nondet_uint(void) { return 0; }
#define __CPROVER_assert(condition, description) assert(condition)
#define __CPROVER_assume(condition) assert(condition)
#endif

enum form {
    FORM_HUMAN = 0,
    FORM_TARGET = 1,
    FORM_OTHER = 2
};

enum boundary {
    POLY_BREAK_ARMOR = 0,
    POLY_EXPELS = 1,
    POLY_DISMOUNT = 2,
    POLY_SPOTEFFECTS = 3,
    POLY_RETOUCH = 4,
    ARMOR_AFTER_GLOVES = 5,
    ARMOR_BEFORE_BOOTS = 6,
    ARMOR_BEFORE_EYEWEAR = 7
};

struct world {
    enum form form;
    unsigned int form_epoch;
    bool light_source;
    bool cleanup_seen;
    unsigned int cleanup_epoch;
};

static struct world w;

static bool
emits_light(enum form form)
{
    return form == FORM_TARGET;
}

static void
assert_light_consistent(void)
{
    __CPROVER_assert(w.light_source == emits_light(w.form),
                     "form and hero light source agree");
}

static void
reset_world(void)
{
    w.form = FORM_HUMAN;
    w.form_epoch = 0;
    w.light_source = false;
    w.cleanup_seen = false;
    w.cleanup_epoch = UINT_MAX;
    assert_light_consistent();
}

/* Model PR #1681's set_uasmon(); uasmon_light(old_light) pair. */
static void
install_form(enum form next)
{
    bool old_light = emits_light(w.form);
    bool new_light;

    w.form = next;
    ++w.form_epoch;
    new_light = emits_light(w.form);
    if (old_light != new_light)
        w.light_source = new_light;

    /* No reentrant call is allowed between installation and bookkeeping. */
    assert_light_consistent();
}

/* Model the pre-PR split: set_uasmon() now, polyself::made_change later. */
static void
install_form_without_light_bookkeeping(enum form next)
{
    w.form = next;
    ++w.form_epoch;
}

static void
cleanup_current_form(void)
{
    __CPROVER_assert(!w.cleanup_seen || w.cleanup_epoch != w.form_epoch,
                     "cleanup runs at most once for each form generation");
    w.cleanup_seen = true;
    w.cleanup_epoch = w.form_epoch;
}

static void
complete_nested_change(enum form next)
{
    install_form(next);
    cleanup_current_form();
}

/*
 * A sound default for the ownership pilot: a reentrant boundary may leave the
 * form alone, revert to human, install another monster, or reinstall the same
 * target.  The last choice is deliberately adversarial: identity guards need
 * an independently proved no-ABA contract to exclude it.
 */
static void
maybe_nested_change(enum boundary at)
{
    unsigned int choice;

    if ((int) at == FORCE_BOUNDARY) {
        choice = 1; /* deterministic A -> human counterexample */
    } else if (FORCE_BOUNDARY >= 0) {
        choice = 0;
    } else {
        choice = nondet_uint();
        __CPROVER_assume(choice <= 3);
    }

    if (!ALLOW_SAME_FORM_REENTRY)
        __CPROVER_assume(choice != 3);

    switch (choice) {
    case 0:
        break;
    case 1:
        complete_nested_change(FORM_HUMAN);
        break;
    case 2:
        complete_nested_change(FORM_OTHER);
        break;
    case 3:
        complete_nested_change(FORM_TARGET);
        break;
    }
}

static bool
guard_stops(enum boundary at, enum form owner_form,
            unsigned int owner_epoch)
{
    if ((int) at == OMIT_GUARD)
        return false;
#if GUARD_MODE == GUARD_FORM_IDENTITY
    (void) owner_epoch;
    return w.form != owner_form;
#elif GUARD_MODE == GUARD_FORM_EPOCH
    (void) owner_form;
    return w.form_epoch != owner_epoch;
#else
    (void) owner_form;
    (void) owner_epoch;
    return false;
#endif
}

static void
apply_owned_effect(unsigned int owner_epoch)
{
    __CPROVER_assert(w.form_epoch == owner_epoch,
                     "old transformation never applies a stale-form effect");
    assert_light_consistent();
}

static bool
cross_boundary(enum boundary at, enum form owner_form,
               unsigned int owner_epoch)
{
    maybe_nested_change(at);
    if (guard_stops(at, owner_form, owner_epoch))
        return false;
    apply_owned_effect(owner_epoch);
    return true;
}

/* Mirrors the five guard locations added to polymon() by PR #1681. */
void
verify_polymon_guards(void)
{
    enum form owner_form = FORM_TARGET;
    unsigned int owner_epoch;

    reset_world();
    install_form(owner_form);
    owner_epoch = w.form_epoch;

    if (!cross_boundary(POLY_BREAK_ARMOR, owner_form, owner_epoch))
        return;
    if (!cross_boundary(POLY_EXPELS, owner_form, owner_epoch))
        return;
    if (!cross_boundary(POLY_DISMOUNT, owner_form, owner_epoch))
        return;
    if (!cross_boundary(POLY_SPOTEFFECTS, owner_form, owner_epoch))
        return;

    /* retouch_equipment() can rehumanize or recursively polymorph. */
    maybe_nested_change(POLY_RETOUCH);
    if (guard_stops(POLY_RETOUCH, owner_form, owner_epoch))
        return;
    apply_owned_effect(owner_epoch);
    cleanup_current_form();

    /* selftouch() follows, but later capability tests read the fresh form. */
    maybe_nested_change(POLY_RETOUCH);
    assert_light_consistent();
}

/* Mirrors the three sub-block guard locations added to break_armor(). */
void
verify_break_armor_guards(void)
{
    enum form owner_form = FORM_TARGET;
    unsigned int owner_epoch;

    reset_world();
    install_form(owner_form);
    owner_epoch = w.form_epoch;

    if (!cross_boundary(ARMOR_AFTER_GLOVES, owner_form, owner_epoch))
        return;
    if (!cross_boundary(ARMOR_BEFORE_BOOTS, owner_form, owner_epoch))
        return;
    if (!cross_boundary(ARMOR_BEFORE_EYEWEAR, owner_form, owner_epoch))
        return;
}

/*
 * Concrete abstraction of the source-audited route:
 * drop invoked levitation -> float_down -> dotrap(POLY_TRAP) -> polyself.
 * Polymorph control can select FORM_TARGET again.  Identity is unchanged,
 * but the nested polymon owns a new generation and has run its cleanup.
 */
void
verify_same_form_polytrap_route(void)
{
    enum form owner_form = FORM_TARGET;
    unsigned int owner_epoch;

    reset_world();
    install_form(owner_form);
    owner_epoch = w.form_epoch;

    complete_nested_change(FORM_TARGET);
    if (guard_stops(ARMOR_AFTER_GLOVES, owner_form, owner_epoch))
        return;
    apply_owned_effect(owner_epoch);
}

/* Positive model for PR #1681's immediate light-source ownership. */
void
verify_light_bookkeeping(void)
{
    reset_world();
    install_form(FORM_TARGET);
    maybe_nested_change(POLY_BREAK_ARMOR);
    assert_light_consistent();
}

/* Negative control reproducing the old delete-before-create window. */
void
reject_delayed_light_bookkeeping(void)
{
    reset_world();
    install_form_without_light_bookkeeping(FORM_TARGET);

    /* A nested rehumanize observes a glowing form before made_change. */
    __CPROVER_assert(!emits_light(w.form) || w.light_source,
                     "legacy rehumanize must not delete a missing source");
}
