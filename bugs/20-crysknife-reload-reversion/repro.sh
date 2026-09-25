#!/bin/bash
# repro.sh -- Re-record bug 20 through the NetHack recorder binary and check
# that fixed crysknives lying on the floor are rolled again for reversion
# when their level is read back in.
#
# The session (seed 28) drops five fixed crysknives on the up staircase of
# level 2, goes up and down the stairs twelve times, saves on level 1, and in a
# second segment restores and goes down once more.  Every obj_no_longer_held()
# draw beyond the five taken on the drop comes from getlev() -> find_lev_obj()
# -> place_object().
#
# Exit 0: bug confirmed.  1: not reproduced (patch applied?).  2: inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/20-crysknife-reload-reversion/session.json
TMP_OUT=$(mktemp -t bugrep20_XXXX.json)
trap 'rm -f "$TMP_OUT"' EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Counting obj_no_longer_held() draws ==="
RESULT=$(python3 - "$TMP_OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
drop = reload = 0
dropped = 0
last_pile = ''
for seg in d['segments']:
    for st in seg['steps']:
        n = sum(1 for r in (st.get('rng') or []) if 'obj_no_longer_held' in r)
        scr = st.get('screen') or ''
        if 'You drop a fixed' in scr and st.get('key') in list('efghij'):
            drop += n
            dropped += 1
        else:
            reload += n
        if 'Things that are here' in scr:
            last_pile = scr
teeth = last_pile.count('worm tooth')
print('DROPPED=%d DROP_DRAWS=%d RELOAD_DRAWS=%d FINAL_TEETH=%d' % (dropped, drop, reload, teeth))
PY
)
echo "$RESULT"
eval "$(echo "$RESULT" | tr ' ' '\n')"

if [ "$DROPPED" -ne 5 ] || [ "$DROP_DRAWS" -ne 5 ]; then
    echo
    echo "INCONCLUSIVE -- the five crysknives were not dropped as expected."
    exit 2
fi
if [ "$RELOAD_DRAWS" -gt 0 ]; then
    echo
    echo "BUG CONFIRMED -- $RELOAD_DRAWS extra reversion rolls were taken while"
    echo "levels were being read back in; $FINAL_TEETH of the 5 knives ended as worm teeth."
    exit 0
fi
echo
echo "BUG NOT REPRODUCED -- only the five drop-time rolls were taken."
echo "proposed-fix.patch is probably already applied to your tree."
exit 1
