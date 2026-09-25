#!/bin/bash
# repro.sh -- Re-record bug 14 through the stock NetHack recorder binary and
# check that rebinding an already-bound key from the 'O' menu prints nothing.
#
# The session binds J (runsouth) to pray, then opens the binding menu for J
# again, which shows 'Key 'J' is currently bound to "pray".', then unbinds J.
# On the stock build no "Changed key 'J' from "runsouth" to "pray"." message
# ever appears, because handler_rebind_keys_add() compares against the list
# entry that bind_key() has just overwritten.
#
# The unbind's message is read from a freed struct; that part is not visible
# in a recording (see asan-report.txt).
#
# Exit: 0 = bug confirmed, 1 = not reproduced (probably fixed),
#       2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/14-rebind-key-message/session.json
TMP_OUT=$(mktemp -t bugrep14_XXXX.json)
trap 'rm -f "$TMP_OUT"' EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the rebind message ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
steps = []
for seg in d.get('segments', [d]):
    steps += seg.get('steps', [])
screens = [s.get('screen') or '' for s in steps]
bound = any('Key \'J\' is currently bound to \"pray\".' in s for s in screens)
changed = any('Changed key \'J\' from \"runsouth\" to \"pray\".' in s for s in screens)
print('STEPS=%d BOUND=%d CHANGED=%d' % (len(steps), bound, changed))
")
echo "$RESULT"

case "$RESULT" in
  *"CHANGED=1"*)
    echo
    echo "BUG NOT REPRODUCED -- the rebind was reported."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1 ;;
  *"BOUND=1 CHANGED=0")
    echo
    echo "BUG CONFIRMED -- J was rebound from runsouth to pray and nothing"
    echo "was printed; the next visit to the menu shows the new binding."
    exit 0 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the recording never showed J bound to pray."
    echo "The keystream may not match this binary."
    exit 2 ;;
esac
