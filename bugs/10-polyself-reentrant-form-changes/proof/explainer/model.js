/* JavaScript transcription of proof/polyself_model.c (the CBMC model).
 * Each run takes an explicit list of callback choices in place of CBMC's
 * nondet_uint(), and records every step so the page can show the trace. */
(function (root) {
  const FORM = { HUMAN: 0, TARGET: 1, OTHER: 2 };
  const FORM_GLYPH = ['@', 'y', ':'];
  const FORM_NAME = ['human', 'yellow light', 'newt'];
  const GUARD = { NONE: 0, IDENTITY: 1, EPOCH: 2 };
  const CHOICE_LABEL = ['nothing happens', 'revert to human', 'become another form', 'reinstall the same form'];
  const BOUNDARY = [
    { id: 0, name: 'POLY_BREAK_ARMOR', code: 'break_armor(); drop_weapon(1);' },
    { id: 1, name: 'POLY_EXPELS', code: 'expels(...)' },
    { id: 2, name: 'POLY_DISMOUNT', code: 'instapetrify(...) / dismount_steed(...)' },
    { id: 3, name: 'POLY_SPOTEFFECTS', code: 'spoteffects(TRUE)' },
    { id: 4, name: 'POLY_RETOUCH', code: 'retouch_equipment(2)' },
    { id: 5, name: 'ARMOR_AFTER_GLOVES', code: 'drop_weapon(0); Gloves_off(); dropp(...)' },
    { id: 6, name: 'ARMOR_BEFORE_BOOTS', code: 'shield / helmet blocks' },
    { id: 7, name: 'ARMOR_BEFORE_EYEWEAR', code: 'boots block' },
  ];

  const emits = f => f === FORM.TARGET;

  class Stop extends Error {}

  function makeRun(opts) {
    const o = Object.assign({ mode: GUARD.EPOCH, omit: -1, force: -1, allowSame: true, choices: [] }, opts);
    const w = { form: 0, epoch: 0, light: false, cleanupSeen: false, cleanupEpoch: null };
    const log = [];
    let k = 0; // index into o.choices
    let failed = null;
    let pruned = false; // path excluded by __CPROVER_assume
    const snap = () => ({ form: w.form, epoch: w.epoch, light: w.light, cleanupSeen: w.cleanupSeen, cleanupEpoch: w.cleanupEpoch });
    const ev = (kind, text, extra) => log.push(Object.assign({ kind, text, w: snap() }, extra || {}));

    let curAt;
    function check(cond, msg) {
      if (!cond) { failed = msg; ev('fail', 'assertion violated: ' + msg, { at: curAt }); throw new Stop(); }
      ev('ok', 'assert ' + msg);
    }
    const lightOK = () => check(w.light === emits(w.form), 'form and hero light source agree');

    function reset() {
      Object.assign(w, { form: 0, epoch: 0, light: false, cleanupSeen: false, cleanupEpoch: null });
    }
    function install(next, quiet) {
      const old = emits(w.form);
      w.form = next; ++w.epoch;
      const nl = emits(w.form);
      if (old !== nl) w.light = nl;
      ev('install', `install_form(${FORM_GLYPH[next]} ${FORM_NAME[next]}): generation is now ${w.epoch}`, { depth: quiet ? 1 : 0 });
      lightOK();
    }
    function installNoLight(next) {
      w.form = next; ++w.epoch;
      ev('install', `set_uasmon() to ${FORM_GLYPH[next]} with the light update deferred (old code)`);
    }
    function cleanup(depth) {
      check(!w.cleanupSeen || w.cleanupEpoch !== w.epoch, 'cleanup runs at most once for each form generation');
      w.cleanupSeen = true; w.cleanupEpoch = w.epoch;
      ev('cleanup', `cleanup for generation ${w.epoch} (encumber_msg, retouch_equipment)`, { depth });
    }
    function maybeNested(at) {
      let c;
      if (at === o.force) c = 1;
      else if (o.force >= 0) c = 0;
      else { c = o.choices[k++]; if (c === undefined) c = 0; }
      if (!o.allowSame && c === 3) { pruned = true; ev('prune', 'excluded by assumption: no same-form reentry'); throw new Stop(); }
      ev('callback', `${BOUNDARY[at].code}: callback ${CHOICE_LABEL[c]}`, { choice: c, at });
      if (c === 1) { install(FORM.HUMAN, true); cleanup(1); }
      else if (c === 2) { install(FORM.OTHER, true); cleanup(1); }
      else if (c === 3) { install(FORM.TARGET, true); cleanup(1); }
      return c;
    }
    function guardStops(at, ownerForm, ownerEpoch) {
      if (at === o.omit) { ev('guard', `guard at ${BOUNDARY[at].name} omitted: always continue`, { at }); return false; }
      let stop = false, why;
      if (o.mode === GUARD.IDENTITY) { stop = w.form !== ownerForm; why = `form ${FORM_GLYPH[w.form]} ${stop ? '≠' : '='} owner ${FORM_GLYPH[ownerForm]}`; }
      else if (o.mode === GUARD.EPOCH) { stop = w.epoch !== ownerEpoch; why = `generation ${w.epoch} ${stop ? '≠' : '='} saved ${ownerEpoch}`; }
      else { why = 'no guard'; }
      ev(stop ? 'stop' : 'guard', stop ? `guard: ${why}, so return early` : `guard: ${why}, so continue`, { at });
      return stop;
    }
    function applyOwned(ownerEpoch, at) {
      curAt = at;
      check(w.epoch === ownerEpoch, 'old transformation never applies a stale-form effect');
      lightOK();
      ev('effect', `apply the ${FORM_GLYPH[FORM.TARGET]} form's own effects after ${BOUNDARY[at].name}`, { at });
    }
    function cross(at, ownerForm, ownerEpoch) {
      maybeNested(at);
      if (guardStops(at, ownerForm, ownerEpoch)) return false;
      applyOwned(ownerEpoch, at);
      return true;
    }

    const programs = {
      polymon() {
        const ownerForm = FORM.TARGET;
        reset(); ev('start', 'polymon(y): begin');
        install(ownerForm);
        const ownerEpoch = w.epoch;
        ev('note', `save my_generation = ${ownerEpoch}`);
        for (const b of [0, 1, 2, 3]) if (!cross(b, ownerForm, ownerEpoch)) return;
        maybeNested(4);
        if (guardStops(4, ownerForm, ownerEpoch)) return;
        applyOwned(ownerEpoch, 4);
        cleanup(0);
        ev('note', 'selftouch() follows; later tests read the fresh form');
        maybeNested(4);
        lightOK();
      },
      break_armor() {
        const ownerForm = FORM.TARGET;
        reset(); ev('start', 'break_armor(): begin');
        install(ownerForm);
        const ownerEpoch = w.epoch;
        ev('note', `save my_generation = ${ownerEpoch}`);
        for (const b of [5, 6, 7]) if (!cross(b, ownerForm, ownerEpoch)) return;
      },
      polytrap() {
        const ownerForm = FORM.TARGET;
        reset(); ev('start', 'polymon(y), then the polymorph-trap route');
        install(ownerForm);
        const ownerEpoch = w.epoch;
        ev('callback', 'drop artifact → float_down → dotrap(POLY_TRAP) → polyself → polymon(y) again', { choice: 3, at: 5 });
        install(ownerForm, true); cleanup(1);
        if (guardStops(5, ownerForm, ownerEpoch)) return;
        applyOwned(ownerEpoch, 5);
      },
      light() {
        reset(); ev('start', 'immediate light bookkeeping');
        install(FORM.TARGET);
        maybeNested(0);
        lightOK();
      },
      delayedLight() {
        reset(); ev('start', 'old delayed light bookkeeping');
        installNoLight(FORM.TARGET);
        ev('callback', 'nested rehumanize() runs before polyself() reaches made_change:');
        check(!emits(w.form) || w.light, 'rehumanize must not delete a light source that does not exist');
      },
    };

    return {
      exec(name) {
        try { programs[name](); if (!failed) ev('done', 'return'); }
        catch (e) { if (!(e instanceof Stop)) throw e; }
        return { log, failed, pruned, used: k };
      },
    };
  }

  function run(name, opts) { return makeRun(opts).exec(name); }

  // Number of nondeterministic points each harness can reach.
  const DEPTH = { polymon: 6, break_armor: 3, light: 1, polytrap: 0, delayedLight: 0 };

  /* Exhaustive search, standing in for CBMC's SAT search: explore the
   * choice tree, extending a prefix whenever the run asked for one more
   * nondeterministic choice than the prefix supplied. */
  function exploreAll(name, opts) {
    const leaves = [];
    function go(prefix) {
      let asked = false;
      const probe = new Proxy(prefix, {
        get(t, p) { if (p === String(prefix.length)) asked = true; return t[p]; },
      });
      const r = run(name, Object.assign({}, opts, { choices: probe }));
      if (asked) for (let c = 0; c < 4; ++c) go(prefix.concat(c));
      else leaves.push({ choices: prefix.slice(), result: r });
    }
    go([]);
    return leaves;
  }

  function verdict(name, opts) {
    const leaves = exploreAll(name, opts);
    const bad = leaves.find(l => l.result.failed);
    return { pass: !bad, counterexample: bad || null, paths: leaves.filter(l => !l.result.pruned).length };
  }

  const api = { FORM, FORM_GLYPH, FORM_NAME, GUARD, CHOICE_LABEL, BOUNDARY, run, exploreAll, verdict, DEPTH };
  if (typeof module !== 'undefined') module.exports = api; else root.PolyModel = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
