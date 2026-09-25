#!/bin/bash
# repro.sh -- Re-record bug 21 through the NetHack recorder binary and check
# that a hero hiding as a mimic loses the disguise across save and restore.
#
# Segment 1 (seed 1): #polyself into a giant mimic, #monster (hide),
# #monster again ("already mimicking"), save.  Segment 2: restore, #monster.
# On the stock build the restored hero is not hiding, so the last #monster
# says "You are now mimicking"; with the patch it says "already mimicking".
#
# Exit 0: bug confirmed.  1: not reproduced (patch applied?).  2: inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/21-mimic-disguise-save/session.json
TMP_OUT=$(mktemp -t bugrep21_XXXX.json)
trap 'rm -f "$TMP_OUT"' EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the disguise before and after the restore ==="
RESULT=$(python3 - "$TMP_OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
segs = d.get('segments') or []
def said(seg, text):
    return any(text in (st.get('screen') or '') for st in seg.get('steps', []))
if len(segs) != 2:
    print('BEFORE=0 AFTER=none')
else:
    before = said(segs[0], 'You are already mimicking a strange object')
    welcome = said(segs[1], 'welcome back')
    if not welcome:
        after = 'none'
    elif said(segs[1], 'You are already mimicking a strange object'):
        after = 'kept'
    elif said(segs[1], 'You are now mimicking a strange object'):
        after = 'lost'
    else:
        after = 'none'
    print('BEFORE=%d AFTER=%s' % (before, after))
PY
)
echo "$RESULT"

case "$RESULT" in
  "BEFORE=1 AFTER=lost")
    echo
    echo "BUG CONFIRMED -- the hero was hiding when saved, but had to hide"
    echo "again after the restore: youmonst.m_ap_type was not saved."
    exit 0 ;;
  "BEFORE=1 AFTER=kept")
    echo
    echo "BUG NOT REPRODUCED -- the disguise survived the restore."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the scenario did not play out as recorded."
    exit 2 ;;
esac
