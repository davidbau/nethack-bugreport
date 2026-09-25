#!/usr/bin/env node

import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const upstream = join(root, 'nethack-c/upstream');
// PR #1681 is these two patches applied in order: the first three commits
// (identity guards, light ownership) and then the generation counter commit
// 97b843554, which replaces every identity guard.
const patches = [
    join(root, 'bugs/10-polyself-reentrant-form-changes/proposed-fix.patch'),
    join(root, 'bugs/10-polyself-reentrant-form-changes/proof/generation-guard.patch'),
];
const GEN_GUARD = 'if (uasmon_generation != my_generation)';

function count(text, needle) {
    return text.split(needle).length - 1;
}

function requireText(text, needle, description) {
    assert.ok(text.includes(needle), `missing ${description}: ${needle}`);
}

function functionBody(source, name) {
    const signature = new RegExp(`\\n${name}\\([^;]*?\\)\\n\\{`, 's');
    const match = signature.exec(source);
    assert.ok(match, `cannot locate function ${name}`);
    const start = source.indexOf('{', match.index + 1);
    let depth = 0;
    for (let i = start; i < source.length; ++i) {
        if (source[i] === '{') ++depth;
        if (source[i] === '}' && --depth === 0)
            return source.slice(start, i + 1);
    }
    assert.fail(`unterminated function ${name}`);
}

function auditPatched(polyself, timeout) {
    const polymon = functionBody(polyself, 'polymon');
    const breakArmor = functionBody(polyself, 'break_armor');
    const polyman = functionBody(polyself, 'polyman');

    const setUasmon = functionBody(polyself, 'set_uasmon');

    assert.equal(count(polymon, GEN_GUARD), 5,
        'polymon must have exactly five generation guards');
    assert.equal(count(breakArmor, GEN_GUARD), 3,
        'break_armor must have exactly three generation guards');
    assert.equal(count(polymon, 'if (u.umonnum != mntmp)'), 0,
        'no identity guard may remain in polymon');
    assert.equal(count(breakArmor, 'if (gy.youmonst.data != uptr)'), 0,
        'no identity guard may remain in break_armor');
    // The counter is bumped by set_uasmon() itself, so every installation,
    // including a same-form one, is a new generation.
    assert.equal(count(setUasmon, 'note_uasmon_install();'), 1,
        'set_uasmon must bump the form generation');
    requireText(functionBody(polyself, 'note_uasmon_install'),
        'if (++uasmon_generation == 0UL)',
        'generation wraparound check');
    requireText(polymon,
        'set_uasmon();\n    uasmon_light(old_light);\n    my_generation = uasmon_generation;',
        'polymon owning the generation it just installed');
    requireText(breakArmor, 'unsigned long my_generation = uasmon_generation;',
        'break_armor owning the generation current at entry');
    assert.equal(count(polyself, 'uasmon_light(old_light);'), 2,
        'both semantic form installers must complete light bookkeeping');
    requireText(polyman, 'set_uasmon();\n    uasmon_light(old_light);',
        'adjacent polyman light bookkeeping');
    requireText(polymon, 'set_uasmon();\n    uasmon_light(old_light);',
        'adjacent polymon light bookkeeping');
    assert.equal(count(functionBody(polyself, 'polyself'), 'made_change:'), 0,
        'deferred polyself light bookkeeping must be removed');
    assert.equal(count(functionBody(polyself, 'rehumanize'),
                       'del_light_source(LS_MONSTER'), 0,
        'rehumanize must not pre-delete the new owner light source');
    assert.equal(count(functionBody(timeout, 'slimed_to_death'),
                       'del_light_source(LS_MONSTER'), 0,
        'sliming must not pre-delete the hero light source');
}

function auditAbaRoute() {
    const artifact = readFileSync(join(upstream, 'src/artifact.c'), 'utf8');
    const trap = readFileSync(join(upstream, 'src/trap.c'), 'utf8');
    const hack = readFileSync(join(upstream, 'src/hack.c'), 'utf8');
    const polyself = readFileSync(join(upstream, 'src/polyself.c'), 'utf8');

    requireText(artifact, '(void) float_down(I_SPECIAL | TIMEOUT, W_ARTI);',
        'invoked levitation ending in float_down');
    requireText(trap, 'dotrap(trap, NO_TRAP_FLAGS);',
        'float_down trap activation');
    requireText(hack, 'dotrap(trap, trapflag);',
        'spoteffects trap activation');
    requireText(trap, 'polyself(POLY_NOFLAGS);',
        'polymorph trap form change');
    requireText(polyself, 'Strcpy(buf, (u.umonnum != mntmp) ? "" : "new ");',
        'same-form polymon path');
    requireText(polyself, 'u.umonnum = mntmp;\n    set_uasmon();',
        'same-form reinstall is not elided');
}

function main() {
    const commit = execFileSync('git', ['rev-parse', 'HEAD'], {
        cwd: upstream, encoding: 'utf8'
    }).trim();
    assert.equal(commit, '16ff59115315917b93185d026aeefea06db9b0f4',
        'proof source pin changed');

    const scratch = mkdtempSync(join(tmpdir(), 'polyself-proof-'));
    try {
        mkdirSync(join(scratch, 'src'));
        cpSync(join(upstream, 'src/polyself.c'), join(scratch, 'src/polyself.c'));
        cpSync(join(upstream, 'src/timeout.c'), join(scratch, 'src/timeout.c'));
        for (const patch of patches)
            execFileSync('git', ['apply', '--recount', patch], { cwd: scratch });

        const polyself = readFileSync(join(scratch, 'src/polyself.c'), 'utf8');
        const timeout = readFileSync(join(scratch, 'src/timeout.c'), 'utf8');
        auditPatched(polyself, timeout);

        assert.throws(
            () => auditPatched(
                polyself.replace(GEN_GUARD, 'if (0 /* removed guard */)'),
                timeout),
            /five generation guards/,
            'negative fixture must detect a missing polymon guard');
        assert.throws(
            () => auditPatched(
                polyself.replace('    note_uasmon_install();\n    /* we can reset',
                                 '    /* we can reset'),
                timeout),
            /set_uasmon must bump/,
            'negative fixture must detect a set_uasmon() that does not bump');
        assert.throws(
            () => auditPatched(
                polyself.replace('uasmon_light(old_light);',
                                 '/* removed light update */'),
                timeout),
            /both semantic form installers/,
            'negative fixture must detect incomplete light bookkeeping');
    } finally {
        rmSync(scratch, { recursive: true, force: true });
    }

    auditAbaRoute();
    console.log('patch audit: source pin, PR patches apply, 8 generation guards, '
        + 'set_uasmon() bumps, light ownership, and ABA route verified');
}

main();
