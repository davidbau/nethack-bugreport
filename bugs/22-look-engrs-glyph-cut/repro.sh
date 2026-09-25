#!/bin/bash
# repro.sh -- Re-record bug 22 through the recorder binary and check the
# symbol the engravings list shows for an object lying on a long engraving.
#
# The session is seed 2 in wizard mode.  The hero burns a 191-character
# engraving, drops a dagger on it, steps off, and asks for the list of
# nearby engravings with "/e".  The line for the engraving ends with
# ", obscured by <symbol>", where <symbol> should be the dagger's ')'.
#
# Stock build:   "obscured by S"  (the glyph code was cut in half)
# Patched build: "obscured by )"  (session-fixed.json)
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed), 2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/22-look-engrs-glyph-cut/session.json
TMP_OUT=$(mktemp -t bugrep22_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the engravings list ==="
RESULT=$(python3 -c "
import json, re
d = json.load(open('$TMP_OUT'))
steps = d['segments'][0].get('steps', [])
scr = [re.sub(r'\x1b\[[0-9;]*[A-Za-z]', ' ', s.get('screen') or '') for s in steps]
last = [s for s in scr if 'seen or remembered engravings' in s]
if not last:
    print('SYMBOL=none')
else:
    m = re.search(r'obscured\s+by\s+(\S*)', last[-1])
    print('SYMBOL=%s' % (m.group(1) if m else 'none'))
")
echo "$RESULT"

case "$RESULT" in
  "SYMBOL=)")
    echo
    echo "BUG NOT REPRODUCED -- the dagger is shown as ')'."
    echo "proposed-fix.patch (or an equivalent) is probably applied."
    exit 1 ;;
  "SYMBOL=none")
    echo
    echo "INCONCLUSIVE -- the engravings list did not show an 'obscured by'"
    echo "line; the recording may not match this binary."
    exit 2 ;;
  *)
    echo
    echo "BUG CONFIRMED -- the object on the engraving is shown as the wrong"
    echo "symbol, because look_engrs()'s overflow guard cut the encglyph()"
    echo "code short."
    exit 0 ;;
esac
