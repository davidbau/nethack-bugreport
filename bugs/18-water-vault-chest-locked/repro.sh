#!/bin/bash
# repro.sh -- Re-record bug 18 through the recorder binary and check that the
# water-vault chest holding a glass escape item is locked.
#
# The session is seed 13 in wizard mode with THEMERM='Water-surrounded vault'
# (NetHack's own themed-room debug hook), so the themed-room generator builds
# that vault.  On this seed the escape item is a crystal wand, which is glass,
# so themerms.lua asks for the chest to be unlocked.  The hero magic-maps the
# level, teleports onto that chest and uses #loot, then ':' to look.
#
# Stock build:   "Hmmm, the chest turns out to be locked."
# Patched build: the #loot menu opens and the chest holds a crystal wand
#                (session-fixed.json).
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed), 2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/18-water-vault-chest-locked/session.json
TMP_OUT=$(mktemp -t bugrep18_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION (THEMERM='Water-surrounded vault') ==="
THEMERM='Water-surrounded vault' node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the escape chest ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
steps = d['segments'][0].get('steps', [])
scr = [s.get('screen') or '' for s in steps]
locked = any('chest turns out to be locked' in s for s in scr)
opened = any('Do what with the chest?' in s for s in scr)
print('STEPS=%d LOCKED=%d OPENED=%d' % (len(steps), locked, opened))
")
echo "$RESULT"

case "$RESULT" in
  *"LOCKED=1 OPENED=0")
    echo
    echo "BUG CONFIRMED -- the chest themerms.lua forces unlocked is locked."
    echo "des.object() reads 'locked', and the script passes 'olocked'."
    exit 0 ;;
  *"LOCKED=0 OPENED=1")
    echo
    echo "BUG NOT REPRODUCED -- the chest opens."
    echo "proposed-fix.patch (or an equivalent) is probably applied."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the scenario did not reach the chest."
    echo "The recording may not match this binary, or THEMERM was ignored"
    echo "(it only takes effect in wizard mode)."
    exit 2 ;;
esac
