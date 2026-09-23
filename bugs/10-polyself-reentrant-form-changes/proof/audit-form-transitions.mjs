#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '../../..');
const upstreamRoot = join(repoRoot, 'nethack-c/upstream');

const expected = [
    ['include/extern.h', 'set_uasmon', 'extern void set_uasmon(void);',
        'public declaration'],
    ['src/allmain.c', 'set_uasmon', 'set_uasmon();',
        'refresh form-derived intrinsics after were-change activity'],
    ['src/invent.c', 'youmonst-data-write', 'gy.youmonst.data = mon->data;',
        'temporary display substitution, not a gameplay form transition'],
    ['src/invent.c', 'youmonst-data-write',
        'gy.youmonst.data = &mons[u.umonnum];',
        'restore after temporary display substitution'],
    ['src/polyself.c', 'set_uasmon', 'set_uasmon(void)',
        'definition of the form/intrinsic installer'],
    ['src/polyself.c', 'umonnum-write', 'u.umonnum = u.umonster;',
        'polyman installs the base form'],
    ['src/polyself.c', 'set_uasmon', 'set_uasmon();',
        'polyman commits the base form'],
    ['src/polyself.c', 'umonnum-write', 'u.umonnum = u.umonster;',
        'change_sex normal-form refresh'],
    ['src/polyself.c', 'umonnum-write',
        'u.umonnum = (u.umonnum == PM_SUCCUBUS) ? PM_INCUBUS : PM_SUCCUBUS;',
        'disabled succubus/incubus form switch site retained in source'],
    ['src/polyself.c', 'set_uasmon', 'set_uasmon();',
        'change_sex commits or refreshes form data'],
    ['src/polyself.c', 'umonnum-write', 'u.umonnum = mntmp;',
        'polymon installs its target form number'],
    ['src/polyself.c', 'set_uasmon', 'set_uasmon();',
        'polymon commits its target form'],
    ['src/restore.c', 'set_uasmon', 'set_uasmon();',
        'restore rebuilds derived hero-monster state'],
    ['src/u_init.c', 'umonnum-write',
        'u.umonnum = u.umonster = gu.urole.mnum;',
        'initial hero form'],
    ['src/u_init.c', 'set_uasmon', 'set_uasmon();',
        'initial derived hero-monster state'],
    ['src/were.c', 'set_uasmon', 'set_uasmon();',
        'lycanthropy intrinsic refresh without a form-number change'],
];

function stripComments(source) {
    let result = '';
    let state = 'code';
    for (let i = 0; i < source.length; ++i) {
        const ch = source[i];
        const next = source[i + 1];
        if (state === 'line-comment') {
            if (ch === '\n') {
                result += ch;
                state = 'code';
            } else {
                result += ' ';
            }
        } else if (state === 'block-comment') {
            if (ch === '*' && next === '/') {
                result += '  ';
                ++i;
                state = 'code';
            } else {
                result += ch === '\n' ? '\n' : ' ';
            }
        } else if (state === 'string' || state === 'char') {
            result += ch === '\n' ? '\n' : ' ';
            if (ch === '\\') {
                result += next === '\n' ? '\n' : ' ';
                ++i;
            } else if ((state === 'string' && ch === '"')
                       || (state === 'char' && ch === "'")) {
                state = 'code';
            }
        } else if (ch === '/' && next === '/') {
            result += '  ';
            ++i;
            state = 'line-comment';
        } else if (ch === '/' && next === '*') {
            result += '  ';
            ++i;
            state = 'block-comment';
        } else {
            result += ch;
            if (ch === '"') state = 'string';
            if (ch === "'") state = 'char';
        }
    }
    return result;
}

function normalize(line) {
    return line.trim().replace(/\s+/g, ' ')
        .replace(/\s*\/\/.*$/, '')
        .trim();
}

function classify(line) {
    const matches = [];
    if (/\bu\.umonnum\s*=(?!=)/.test(line))
        matches.push('umonnum-write');
    if (/\bgy\.youmonst\.data\s*=(?!=)/.test(line))
        matches.push('youmonst-data-write');
    if (/\bset_uasmon\s*\(/.test(line))
        matches.push('set_uasmon');
    return matches;
}

function cFiles(root) {
    const files = [];
    for (const entry of readdirSync(root, { withFileTypes: true })) {
        const path = join(root, entry.name);
        if (entry.isDirectory()) files.push(...cFiles(path));
        else if (/\.[ch]$/.test(entry.name)) files.push(path);
    }
    return files;
}

function inventory(root) {
    const rows = [];
    for (const file of [...cFiles(join(root, 'include')),
                        ...cFiles(join(root, 'src'))]) {
        const path = relative(root, file);
        const lines = stripComments(readFileSync(file, 'utf8')).split('\n');
        for (let index = 0; index < lines.length; ++index) {
            const code = normalize(lines[index]);
            for (const kind of classify(code))
                rows.push({ path, line: index + 1, kind, code });
        }
    }
    return rows.sort((a, b) =>
        a.path.localeCompare(b.path) || a.line - b.line
        || a.kind.localeCompare(b.kind));
}

function expectedKey(row) {
    return `${row[0]}\0${row[1]}\0${row[2]}`;
}

function actualKey(row) {
    return `${row.path}\0${row.kind}\0${row.code}`;
}

function counts(rows, key) {
    const result = new Map();
    for (const row of rows) {
        const value = key(row);
        result.set(value, (result.get(value) ?? 0) + 1);
    }
    return result;
}

function selfTest() {
    const fixture = stripComments(`
        /* u.umonnum = bogus; set_uasmon(); */
        if (u.umonnum == target) { /* equality is not a write */ }
        const char *s = "set_uasmon() and u.umonnum = are text";
        u.umonnum = target;
        set_uasmon();
    `);
    const found = fixture.split('\n').flatMap(line => classify(normalize(line)));
    assert.deepEqual(found, ['umonnum-write', 'set_uasmon']);

    const unexpected = classify('gy.youmonst.data = replacement;');
    assert.deepEqual(unexpected, ['youmonst-data-write']);
}

selfTest();

const actual = inventory(upstreamRoot);
const expectedCounts = counts(expected, expectedKey);
const actualCounts = counts(actual, actualKey);
const unexpected = actual.filter((row, index, rows) => {
    const key = actualKey(row);
    const occurrence = rows.slice(0, index + 1)
        .filter(candidate => actualKey(candidate) === key).length;
    return occurrence > (expectedCounts.get(key) ?? 0);
});
const missing = expected.filter((row, index, rows) => {
    const key = expectedKey(row);
    const occurrence = rows.slice(0, index + 1)
        .filter(candidate => expectedKey(candidate) === key).length;
    return occurrence > (actualCounts.get(key) ?? 0);
});

if (unexpected.length || missing.length) {
    if (unexpected.length) {
        console.error('Unexpected form-transition sites:');
        for (const row of unexpected)
            console.error(`  ${row.path}:${row.line} ${row.kind}: ${row.code}`);
    }
    if (missing.length) {
        console.error('Missing reviewed form-transition sites:');
        for (const row of missing)
            console.error(`  ${row[0]} ${row[1]}: ${row[2]} (${row[3]})`);
    }
    process.exitCode = 1;
} else {
    console.log(`form-transition audit: ${actual.length} reviewed sites, no drift`);
}
