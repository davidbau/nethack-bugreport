#!/bin/bash
# repro.sh — Re-record bug 01 through a freshly-built NetHack recorder
# binary and assert the impossible() warning fires.
#
# Prerequisites:
#   - nethack-c/recorder/ submodule populated and built
#     (run `bash setup.sh` from the repo root once before this)
#   - node >= 22

set -e

cd "$(dirname "$0")/../.."

SESSION=bugs/01-vault-guard-parkguard-newsym/session.json
TMP_OUT=$(mktemp -t bugrep01_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Searching output for the impossible() cascade ==="
HITS=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
hit_lines = []
for i, s in enumerate(steps):
    scr = s.get('screen', '') or ''
    for needle in ('newsym: attempting screen update', 'Program in disorder', 'devteam@nethack.org'):
        if needle in scr:
            hit_lines.append((i, needle))
for i, n in hit_lines:
    print(f'step {i}: {n}')
print(f'TOTAL HITS: {len(hit_lines)}')
")
echo "$HITS"

# Expect at least the three impossible-cascade lines to fire
COUNT=$(echo "$HITS" | tail -1 | awk '{print $3}')
if [ "$COUNT" -ge 3 ]; then
    echo
    echo "BUG CONFIRMED — impossible() cascade reproduced ($COUNT hits)."
    exit 0
else
    echo
    echo "BUG NOT REPRODUCED — only $COUNT hits (expected >= 3)."
    echo "If 0 hits: the bug may have been patched, or your recorder"
    echo "binary may not be vanilla 5.0. Check nethack-c/upstream HEAD."
    exit 1
fi
