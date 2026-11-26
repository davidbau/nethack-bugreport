#!/usr/bin/env bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp)
trap 'rm -f "$out"' EXIT
node "$here/../../scripts/record-session.mjs" "$here/session.json" "$out"
node --input-type=module - "$out" <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const { steps } = JSON.parse(readFileSync(process.argv[2])).segments[0];
assert.match(steps[37].screen, /newt corpse lands on the altar/);
assert.match(steps[39].screen, /Do what with the jackal corpse/);
assert.equal(steps[40].key, 'O');
assert.match(steps[40].screen, /Please report these messages to devteam/);
assert.match(steps[41].screen, /What do you want to sacrifice/);
console.log('Reproduced: offering the selected jackal reports an error and asks for the item again.');
JS
