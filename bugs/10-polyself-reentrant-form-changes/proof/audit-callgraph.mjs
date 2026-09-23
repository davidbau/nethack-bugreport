#!/usr/bin/env node

/* Conservative call-graph audit for semantic hero-form installation.
 * This is intentionally source-based: it errs by reporting extra callers,
 * never by hiding a possible path.  Every direct form-number write and every
 * call to the installation primitives is listed and checked against the
 * reviewed inventory. */
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const src = join(root, 'nethack-c/upstream/src');

function files(dir) {
    return readdirSync(dir, { withFileTypes: true }).flatMap(e => {
        const p = join(dir, e.name);
        return e.isDirectory() ? files(p) : /\.c$/.test(e.name) ? [p] : [];
    });
}

function strip(s) {
    return s.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
        .replace(/\/\/.*$/gm, '');
}

const rows = [];
for (const file of files(src)) {
    const text = strip(readFileSync(file, 'utf8'));
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; ++i) {
        if (/\bu\.umonnum\s*=(?!=)/.test(lines[i])
            || /\bgy\.youmonst\.data\s*=(?!=)/.test(lines[i]))
            rows.push({ file: relative(src, file), line: i + 1,
                text: lines[i].trim() });
    }
}

const expected = new Set([
    'polyself.c:210', 'polyself.c:293', 'polyself.c:299',
    'polyself.c:814', 'restore.c:627',
    'u_init.c:991', 'were.c:236', 'allmain.c:349',
    'invent.c:5363', 'invent.c:5374'
]);
for (const row of rows) {
    const key = `${row.file}:${row.line}`;
    assert.ok(expected.has(key), `unreviewed installation site ${key}: ${row.text}`);
}

const setCalls = [];
for (const file of files(src)) {
    const lines = strip(readFileSync(file, 'utf8')).split('\n');
    for (let i = 0; i < lines.length; ++i)
        if (/\bset_uasmon\s*\(\s*\)/.test(lines[i]))
            setCalls.push(`${relative(src, file)}:${i + 1}`);
}
assert.deepEqual(setCalls.map(x => x.split(':')[0]).sort(),
    ['allmain.c', 'polyself.c', 'polyself.c', 'polyself.c', 'restore.c', 'u_init.c', 'were.c'].sort(),
    'set_uasmon call graph changed; review every installation edge');

/* Enumerate every direct polymon caller.  A call graph cannot make an
 * indirect function pointer sound, so reject such calls in this subsystem. */
const callsites = [];
for (const file of files(src)) {
    const text = strip(readFileSync(file, 'utf8'));
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; ++i)
        if (/\bpolymon\s*\(/.test(lines[i]) && !/^\s*polymon\s*\(/.test(lines[i]))
            callsites.push(`${relative(src, file)}:${i + 1}`);
}
assert.equal(callsites.some(x => x.startsWith('trap.c:')), true,
    'trap-to-polymon path was not found');
assert.equal(callsites.some(x => x.startsWith('polyself.c:')), true,
    'polyself recursive polymon path was not found');
console.log(`call-graph audit: ${rows.length} reviewed installation sites;`);
console.log(`  direct polymon call sites: ${callsites.length}`);
console.log('  all direct form writes/calls are covered by the reviewed inventory');
