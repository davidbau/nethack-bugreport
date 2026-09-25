#!/bin/bash
# repro.sh -- Re-record bug 13 through a freshly built NetHack recorder and
# check that a shop's squares belong to the wrong room after the level is
# revisited.
#
# The session is seed 895 in wizard mode.  It level-teleports down one level
# at a time to Dlvl 17, which has two themed rooms with subrooms: a
# "Nesting rooms" room in the middle of the map, made first, and a "Twin
# businesses" armor shop and weapon shop at the far left, made second.  The
# hero teleports into the armor shop (greeted, the plate mail is for sale),
# into the middle subroom (nothing), goes to Dlvl 18 and comes back, and
# repeats both visits.
#
# Stock 5.0.0: on the second visit the armor shop is no longer a shop (no
# greeting, the plate mail is not for sale and is picked up free), and the
# ordinary subroom reports "This shop seems to be untended."
# With proposed-fix.patch: "Welcome again", the plate mail is still for sale,
# and the ordinary room says nothing.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/13-subroom-roomno-stale-on-restore/session.json
TMP_OUT=$(mktemp -t bugrep13_XXXX.json)
trap 'rm -f "$TMP_OUT"' EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the two visits to Dlvl 17 ==="
RESULT=$(python3 - "$TMP_OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
steps = d['segments'][0]['steps']
tops = [(s.get('screen') or '').split('\n')[0] for s in steps]
def first(pred, start=0):
    for i in range(start, len(tops)):
        if pred(tops[i]):
            return i
    return -1
greet = first(lambda t: "Welcome to Ayancik's used armor dealership" in t)
sale = first(lambda t: 'bronze plate mail (for sale' in t)
# the second visit starts after the return to Dlvl 17 (the ^V 17 after ^V 18)
back = -1
for i, s in enumerate(steps):
    if s.get('key') == '7' and i > 0 and steps[i-1].get('key') == '1' and i > sale > 0:
        back = i
again = first(lambda t: "Welcome again to Ayancik's" in t, max(back, 0))
free = first(lambda t: t.strip() == 'e - a bronze plate mail.', max(back, 0))
untended = first(lambda t: 'This shop seems to be untended.' in t, max(back, 0))
print('FIRST=%d REVISIT=%d AGAIN=%d FREE=%d UNTENDED=%d'
      % (greet >= 0 and sale >= 0, back >= 0, again >= 0, free >= 0, untended >= 0))
PY
)
echo "$RESULT"

case "$RESULT" in
  "FIRST=1 REVISIT=1 AGAIN=0 FREE=1 UNTENDED=1")
    echo
    echo "BUG CONFIRMED -- after the level was saved and restored, the armor"
    echo "shop's squares resolve to an ordinary room (the plate mail is picked"
    echo "up free) and the ordinary subroom's squares resolve to a shop with no"
    echo "shopkeeper (\"This shop seems to be untended.\")."
    exit 0 ;;
  "FIRST=1 REVISIT=1 AGAIN=1 FREE=0 UNTENDED=0")
    echo
    echo "BUG NOT REPRODUCED -- the shop is still a shop after the revisit."
    echo "proposed-fix.patch is probably already applied to your tree."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the recording did not follow the expected path."
    exit 2 ;;
esac
