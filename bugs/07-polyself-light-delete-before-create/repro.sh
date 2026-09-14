#!/bin/bash
# repro.sh — Re-record bug 07 through a freshly-built NetHack recorder binary
# and assert that del_light_source() reports "not found".
#
# Prerequisites:
#   - nethack-c/recorder/ populated and built (run `bash setup.sh` once)
#   - node >= 22, python3
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/07-polyself-light-delete-before-create/session.json
TMP_OUT=$(mktemp -t bugrep07_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Looking for the impossible() on screen ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
notfound = [i for i, s in enumerate(steps)
            if 'del_light_source: not found' in (s.get('screen') or '')]
disorder = [i for i, s in enumerate(steps)
            if 'Program in disorder' in (s.get('screen') or '')]
print(f'NOTFOUND={\",\".join(map(str, notfound)) or \"-\"}')
print(f'DISORDER={\",\".join(map(str, disorder)) or \"-\"}')
")
echo "$RESULT"

NF=$(echo "$RESULT" | grep NOTFOUND | cut -d= -f2)

if [ "$NF" != "-" ]; then
    echo
    echo "BUG CONFIRMED — del_light_source: not found at step(s) $NF."
    echo "rehumanize() (polyself.c:1393) deleted a hero light source that"
    echo "polyself.c:728 had not created yet."
    exit 0
else
    echo
    echo "BUG NOT REPRODUCED — no 'not found' diagnostic."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1
fi
