#!/bin/bash
# repro.sh — Re-record bug 12 through a freshly-built NetHack recorder binary
# and assert that Fort Ludios's #overview annotation is missing.
#
# The shipped session is seed 19, on which flip_level_rnd() mirrors Knox
# horizontally. The scenario magic-maps the fort, wizard-teleports into the
# throne room, runs ^E (findit) to turn the entrance from SDOOR into DOOR,
# re-maps, and reads #overview. On the stock build the overview lists
# "A throne." and stops; the "Fort Ludios." line is never earned.
#
# session-unflipped.json (seed 7027) is the control: same scenario on a seed
# that does not flip, where both lines print. session-fixed.json is seed 19
# re-recorded against a binary with proposed-fix.patch applied.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/12-fort-ludios-annotation-flip/session.json
TMP_OUT=$(mktemp -t bugrep12_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the #overview annotation ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
throne = any('A throne.' in (s.get('screen') or '') for s in steps)
ludios = any('Fort Ludios.' in (s.get('screen') or '') for s in steps)
print('THRONE=%d LUDIOS=%d' % (throne, ludios))
")
echo "$RESULT"

case "$RESULT" in
  "THRONE=1 LUDIOS=0")
    echo
    echo "BUG CONFIRMED — the throne is annotated but 'Fort Ludios.' is not."
    echo "The level is x-flipped, so the throne sits at entrance + 4 and"
    echo "recalc_mapseen()'s x - 4 test looks at empty floor."
    exit 0 ;;
  "THRONE=1 LUDIOS=1")
    echo
    echo "BUG NOT REPRODUCED — both lines present."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE — the scenario did not reach the throne room."
    echo "Expected THRONE=1; the recording may not match this binary."
    exit 2 ;;
esac
