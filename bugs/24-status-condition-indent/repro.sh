#!/bin/bash
# repro.sh -- Re-record bug 24 through the NetHack recorder binary and check
# the third status line.
#
# Both sessions use statuslines:3 with weaponstatus and armorstatus, on a
# Valkyrie (spear wielded, shield worn) who puts on a blindfold so that the
# "Blind" condition shows, wishes for 100 gold, and drops it.
#
#   session.json           the gold change makes "Spear Shield" vanish, and
#                          dropping the gold leaves "Blindnd" behind
#   session-showvers.json  the same with showvers: "Blind" never appears
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed), 2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."

DIR=bugs/24-status-condition-indent
OUT1=$(mktemp -t bugrep24a_XXXX.json)
OUT2=$(mktemp -t bugrep24b_XXXX.json)
trap "rm -f $OUT1 $OUT2" EXIT

echo "=== Re-recording $DIR/session.json ==="
node scripts/record-session.mjs "$DIR/session.json" "$OUT1"
echo "=== Re-recording $DIR/session-showvers.json ==="
node scripts/record-session.mjs "$DIR/session-showvers.json" "$OUT2"

echo
echo "=== Checking the third status line ==="
set +e
python3 - "$OUT1" "$OUT2" <<'PY'
import json, re, sys

def rows(path):
    steps = json.load(open(path))['segments'][0]['steps']
    out = []
    for s in steps:
        scr = re.sub(r'\x1b\[(\d+)C', lambda m: ' ' * int(m.group(1)),
                     s.get('screen') or '')
        scr = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]|[\x0e\x0f]',
                     '', scr)
        lines = scr.split('\n') + [''] * 24
        out.append(lines[23].rstrip())
    return out

plain, vers = rows(sys.argv[1]), rows(sys.argv[2])
if len(plain) != 34 or len(vers) != 37:
    print('unexpected step counts %d/%d' % (len(plain), len(vers)))
    sys.exit(2)
final = plain[-1]
print('session.json          last step:  %r' % final)
print('session-showvers.json after Pe:   %r' % vers[13])
stale = 'Blindnd' in final
vanished = 'Blind' in final and 'Spear' not in final
never = not any('Blind' in r for r in vers)
print('stale "Blindnd": %s; weapon/armor gone: %s; Blind hidden by showvers: %s'
      % (stale, vanished, never))
if stale and vanished and never:
    sys.exit(0)
if (not stale and not vanished and not never
        and 'Spear Shield' in final and 'Blind' in final):
    sys.exit(1)
sys.exit(2)
PY
RC=$?
set -e

case $RC in
  0)
    echo
    echo "BUG CONFIRMED -- the right-indented condition on the third status"
    echo "line collides with the weapon and armor fields placed after it."
    exit 0 ;;
  1)
    echo
    echo "BUG NOT REPRODUCED -- the third status line is drawn correctly."
    echo "proposed-fix.patch (or an equivalent) is probably applied."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the recording does not match either expected outcome."
    exit 2 ;;
esac
