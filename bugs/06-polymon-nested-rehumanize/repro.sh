#!/bin/bash
# repro.sh — Re-record bug 06 through a freshly-built NetHack recorder binary
# and assert that TWO artifact blasts fire from a single polymorph.
#
# Prerequisites:
#   - nethack-c/recorder/ populated and built (run `bash setup.sh` once)
#   - node >= 22, python3
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/06-polymon-nested-rehumanize/session.json
TMP_OUT=$(mktemp -t bugrep06_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Counting touch_artifact() blasts after the polymorph ==="
COUNT=$(python3 -c "
import json, re
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
poly = [i for i, s in enumerate(steps)
        for e in (s.get('rng') or [])
        if re.search(r'>pline @ polymon\(polyself\.c:\d+\)', e)]
start = max(poly) if poly else 0
n = sum(1 for i, s in enumerate(steps) if i >= start
        for e in (s.get('rng') or [])
        if re.match(r'd\(\d+,10\)=\d+ @ touch_artifact', e))
print(n)
")
echo "blasts after polymorph: $COUNT"

if [ "$COUNT" -ge 2 ]; then
    echo
    echo "BUG CONFIRMED — $COUNT artifact blasts from one polymorph."
    echo "rehumanize() ran retouch_equipment(2) at polyself.c:1415, then"
    echo "polymon() ran it again at polyself.c:1021."
    exit 0
elif [ "$COUNT" = "1" ]; then
    echo
    echo "BUG NOT REPRODUCED — exactly one blast."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1
else
    echo
    echo "BUG NOT REPRODUCED — no blasts found; the session may have desynced."
    echo "Check that nethack-c/upstream is at the recorded commit."
    exit 1
fi
