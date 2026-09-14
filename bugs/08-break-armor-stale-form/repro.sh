#!/bin/bash
# repro.sh — Re-record bug 08 through a freshly-built NetHack recorder binary
# and assert that break_armor() strips a REVERTED (human) hero's shield and
# water walking boots, killing them in lava.
#
# Prerequisites:
#   - nethack-c/recorder/ populated and built (run `bash setup.sh` once)
#   - node >= 22, python3
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/08-break-armor-stale-form/session.json
TMP_OUT=$(mktemp -t bugrep08_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking what happens after 'You return to human form!' ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
tops = [(s.get('screen') or '').split('\n')[0] for s in steps]
rev = next((i for i, t in enumerate(tops) if 'You return to human form' in t), None)
after = tops[rev:] if rev is not None else []
def seen(m): return int(any(m in t for t in after))
print(f'REVERT_AT={rev}')
print(f'SHIELD={seen(\"You can no longer hold your shield\")}')
print(f'BOOTS={seen(\"Your boots slide off your feet\")}')
print(f'DEATH={seen(\"burn to a crisp\")}')
")
echo "$RESULT"

SH=$(echo "$RESULT" | grep '^SHIELD=' | cut -d= -f2)
BO=$(echo "$RESULT" | grep '^BOOTS=' | cut -d= -f2)
DE=$(echo "$RESULT" | grep '^DEATH=' | cut -d= -f2)

if [ "$SH" = "1" ] && [ "$BO" = "1" ] && [ "$DE" = "1" ]; then
    echo
    echo "BUG CONFIRMED — after rehumanize(), break_armor() stripped the human's"
    echo "shield and water walking boots (by the newt's nohands/verysmall), and"
    echo "the bootless hero burned to death in the lava."
    exit 0
elif [ "$SH" = "0" ] && [ "$BO" = "0" ]; then
    echo
    echo "BUG NOT REPRODUCED — gear retained after the revert."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1
else
    echo
    echo "BUG NOT REPRODUCED cleanly — partial match; the session may have desynced."
    exit 1
fi
