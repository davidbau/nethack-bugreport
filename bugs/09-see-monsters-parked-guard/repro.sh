#!/bin/bash
# repro.sh — Re-record bug 09 through a freshly-built NetHack recorder binary
# and assert that newsym()'s impossible() fires for the parked vault guard.
#
# Uses session-directed.json, a 97-key wizard-mode scenario built from the
# mechanics: teleport into a vault, get escorted out, and stay standing in the
# temporary corridor while the guard is parked.  Five firings, at steps 73, 78,
# 83, 88 and 93.
#
# NOTE 1: your tree must already contain upstream c42d35eac ("avoid newsym(0,0)
# for vault guard").  Without it the older postmov() path (bug 01) fires first
# and this repro cannot distinguish the two call sites.
#
# NOTE 2: upstream d13eceb28 (2026-06-14) fixes this, so on any tree at or
# after that commit the bug is absent and this script exits 1.  It stays here
# for trees between c42d35eac and d13eceb28, and as the check the patch in this
# bundle was verified against (5 assertions unpatched, 0 patched).
#
# NOTE 3: do not point this at session.json.  That recording still replays
# frame for frame, but a fresh C recording of its keystream diverges at RNG
# draw 2486 against the current harness and the replacement game never parks a
# guard.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/09-see-monsters-parked-guard/session-directed.json
TMP_OUT=$(mktemp -t bugrep09_XXXX.json)
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
hits = [i for i, s in enumerate(steps)
        if 'newsym: attempting screen update' in (s.get('screen') or '')]
print('HITS=' + (','.join(map(str, hits)) or '-'))
")
echo "$RESULT"
H=$(echo "$RESULT" | cut -d= -f2)

if [ "$H" != "-" ]; then
    echo
    echo "BUG CONFIRMED — newsym(0,0) impossible() at step(s) $H."
    echo "see_monsters() drew the vault guard parked off-map at <0,0>."
    exit 0
else
    echo
    echo "BUG NOT REPRODUCED — no impossible()."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1
fi
