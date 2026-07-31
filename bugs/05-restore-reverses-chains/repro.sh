#!/bin/bash
# repro.sh — Re-record bug 05 through a freshly-built NetHack recorder
# binary and assert the stairway-list flip fires.
#
# The recording wounds a master lich on the Sokoban entrance level
# (two up staircases). Wounded covetous monsters teleport to "the
# first up staircase in the list" and camp there. The session then
# leaves the level and comes straight back, which reverses the
# stairway list — so on a vanilla build the lich switches to the
# OTHER staircase ("The master lich vanishes and reappears closer to
# you." on the far side of the trip). On a build with
# proposed-fix.patch applied, the list keeps its order and the lich
# stays put ("...reappears farther away.").
#
# Prerequisites:
#   - nethack-c/recorder built (run `bash setup.sh` from the repo
#     root once before this)
#   - node >= 22

set -e

cd "$(dirname "$0")/../.."

SESSION=bugs/05-restore-reverses-chains/session.json
TMP_OUT=$(mktemp -t bugrep05_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the two camp readouts ==="
python3 - "$TMP_OUT" <<'EOF'
import json, sys

steps = json.load(open(sys.argv[1]))['segments'][0]['steps']

def screen(i):
    return steps[i].get('screen') or '' if i < len(steps) else ''

# Step 87: after the lightning hit, the wounded lich retreats to the
# first-in-list staircase (the Sokoban branch stair, west side).
pre = 'vanishes and reappears farther away' in screen(87)

# Step 99: first turn after the leave-and-return. Buggy: the reversed
# list makes it switch to the main stair beside the hero ("closer to
# you"). Fixed: it stays at the branch stair ("farther away").
post_flip = 'vanishes and reappears closer to you' in screen(99)
post_stay = 'vanishes and reappears farther away' in screen(99)

print(f'step 87 retreat-to-stairs camp: {"OK" if pre else "MISSING"}')
if not pre:
    print('cannot evaluate: the setup did not replay as recorded')
    sys.exit(2)

if post_flip:
    print('step 99: lich SWITCHED staircases after one leave-and-return')
    print()
    print('BUG CONFIRMED — the stairway list reversed on revisit.')
    sys.exit(0)
elif post_stay:
    print('step 99: lich stayed at the same staircase')
    print()
    print('BUG NOT PRESENT — list order survived the revisit')
    print('(is this a build with proposed-fix.patch applied?)')
    sys.exit(1)
else:
    print('step 99: unexpected screen; replay drifted from the recording')
    sys.exit(2)
EOF
