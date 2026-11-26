#!/usr/bin/env bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for name in session session-menu; do
    node "$here/../../scripts/record-session.mjs" "$here/$name.json" "$work/$name.json"
done
node --input-type=module - "$work" "${1:-original}" <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const [dir, mode] = process.argv.slice(2);
assert.ok(['original', 'fixed'].includes(mode));
for (const [name, inventory] of [['session', 152], ['session-menu', 151]]) {
    const { steps } = JSON.parse(readFileSync(dir + '/' + name + '.json')).segments[0];
    assert.match(steps[148].screen, /Buy this unpaid item/);
    const pack = steps[inventory].screen;
    if (mode === 'fixed') {
        assert.match(steps[149].screen, /bought .*glass for 5 gold pieces/);
        assert.match(pack, /5002 gold pieces/);
        assert.match(pack, /scroll of gold detection \(unpaid, 100 zorkmids\)/);
        assert.doesNotMatch(steps[inventory + 1].screen, /glass \(unpaid/);
    } else if (name === 'session') {
        assert.match(steps[149].screen, /bought .*scroll of gold detection for 100/);
        assert.match(steps[150].screen, /bought .*glass for 5/);
        assert.match(pack, /4902 gold pieces/);
    } else {
        assert.match(steps[149].screen, /Pay for which items/);
        assert.match(pack, /5007 gold pieces/);
        assert.match(steps[inventory + 1].screen, /glass \(unpaid, 5 zorkmids\)/);
    }
}
console.log('Verified both billing styles (' + mode + ').');
JS
