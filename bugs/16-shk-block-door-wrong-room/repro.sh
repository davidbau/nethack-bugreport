#!/bin/bash
# repro.sh -- Re-record bug 16 through a freshly built NetHack recorder and
# check that the shopkeeper does not block diagonal moves through his broken
# shop door.
#
# Both sessions are seed 5 in wizard mode, on Dlvl 2, whose armor shop
# (Siirt's) has its door in the west wall.  The hero teleports onto the door
# and wishes it into a broken door (a wizard-mode terrain wish), so that
# diagonal moves through it are allowed in principle.
#
#   session.json        the hero picks up a long sword (unpaid, 20 zm), stands
#                       diagonally inside the door next to Siirt at his post,
#                       and moves diagonally onto the door, then out.
#   session-entry.json  the hero, carrying a pick-axe, stands on the door and
#                       moves diagonally into the shop past Siirt.
#
# Stock 5.0.0: both moves succeed ("Please pay before leaving.", then "You
# stole 20 zorkmids worth of merchandise."; and the hero is inside the shop
# with the pick-axe).  With proposed-fix.patch: "Siirt blocks your way!" both
# times.
set -e
cd "$(dirname "$0")/../.."

DIR=bugs/16-shk-block-door-wrong-room
TMP_X=$(mktemp -t bugrep16x_XXXX.json)
TMP_E=$(mktemp -t bugrep16e_XXXX.json)
trap 'rm -f "$TMP_X" "$TMP_E"' EXIT

echo "=== Re-recording $DIR/session.json (leaving with an unpaid item) ==="
node scripts/record-session.mjs "$DIR/session.json" "$TMP_X"
echo "=== Re-recording $DIR/session-entry.json (entering with a pick-axe) ==="
node scripts/record-session.mjs "$DIR/session-entry.json" "$TMP_E"

echo
echo "=== Checking both diagonal moves ==="
RESULT=$(python3 - "$TMP_X" "$TMP_E" <<'PY'
import json, sys
def load(p):
    st = json.load(open(p))['segments'][0]['steps']
    return st, [(s.get('screen') or '').split('\n')[0] for s in st]
xs, xt = load(sys.argv[1])
es, et = load(sys.argv[2])
setup = (any('A broken door.' in t for t in xt)
         and any('long sword (unpaid' in t for t in xt)
         and any('A broken door.' in t for t in et)
         and any('leave your pick-axe outside' in t for t in et))
xblock = any('Siirt blocks your way!' in t for t in xt)
xstole = any('You stole' in t for t in xt)
eblock = any('Siirt blocks your way!' in t for t in et)
# the last diagonal key ('n', southeast) in the entry session
ni = max(i for i, s in enumerate(es) if s.get('key') == 'n')
einside = es[ni]['cursor'][:2] == [66, 17]
print('SETUP=%d EXIT_BLOCKED=%d STOLE=%d ENTRY_BLOCKED=%d ENTERED=%d'
      % (setup, xblock, xstole, eblock, einside))
PY
)
echo "$RESULT"

case "$RESULT" in
  "SETUP=1 EXIT_BLOCKED=0 STOLE=1 ENTRY_BLOCKED=0 ENTERED=1")
    echo
    echo "BUG CONFIRMED -- Siirt is at his post but lets the hero step"
    echo "diagonally out of the shop with an unpaid item, and diagonally into"
    echo "it with a pick-axe.  block_door() and block_entry() test"
    echo "svr.rooms[roomno] instead of svr.rooms[roomno - ROOMOFFSET]."
    exit 0 ;;
  "SETUP=1 EXIT_BLOCKED=1 STOLE=0 ENTRY_BLOCKED=1 ENTERED=0")
    echo
    echo "BUG NOT REPRODUCED -- Siirt blocks both moves."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the recordings did not follow the expected path."
    exit 2 ;;
esac
