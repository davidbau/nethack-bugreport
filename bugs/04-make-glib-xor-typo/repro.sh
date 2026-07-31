#!/bin/bash
# repro.sh — Re-record bug 04 through a freshly-built NetHack recorder
# binary and assert the stale-status signature fires.
#
# The recording greases the hero's hands with OPTIONS=cond_slip
# enabled. On a vanilla build the Slip status indicator does NOT
# appear when the fingers become slippery (steps 22-30), appears only
# after a forced ^R redraw (step 31), and is wrongly erased again one
# turn later. On a build with proposed-fix.patch applied, Slip
# displays from the moment of greasing through expiry (steps 22-63).
#
# Prerequisites:
#   - nethack-c/recorder built (run `bash setup.sh` from the repo
#     root once before this)
#   - node >= 22

set -e

cd "$(dirname "$0")/../.."

SESSION=bugs/04-make-glib-xor-typo/session.json
TMP_OUT=$(mktemp -t bugrep04_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the Slip-indicator signature ==="
python3 - "$TMP_OUT" <<'EOF'
import json, re, sys

steps = json.load(open(sys.argv[1]))['segments'][0]['steps']

def slip_shown(i):
    if i >= len(steps):
        return False
    lines = []
    for line in (steps[i].get('screen') or '').split('\n'):
        line = re.sub(r'\[([0-9]+)C', lambda m: ' ' * int(m.group(1)), line)
        lines.append(re.sub(r'\[[0-9;]*m', '', line))
    return any('Slip' in l for l in lines[-3:])

coated = any('coat your fingers with grease' in (steps[i].get('screen') or '')
             for i in range(20, 25))
if not coated:
    print('cannot evaluate: the greasing did not replay as recorded')
    sys.exit(2)

quiet = [slip_shown(i) for i in range(23, 31)]   # slippery, waiting
reveal = slip_shown(31)                          # right after ^R

print(f'steps 23-30 (fingers slippery, no redraw): '
      f'{"Slip shown" if any(quiet) else "no Slip shown"}')
print(f'step 31 (after ^R): {"Slip shown" if reveal else "no Slip"}')

if not any(quiet) and reveal:
    print()
    print('BUG CONFIRMED — the Slip condition displayed only after a')
    print('forced redraw; the transition never marked the status dirty.')
    sys.exit(0)
elif all(quiet):
    print()
    print('BUG NOT PRESENT — Slip displayed as soon as the fingers')
    print('were greased (is this a build with proposed-fix.patch?)')
    sys.exit(1)
else:
    print()
    print('unexpected pattern; replay drifted from the recording')
    sys.exit(2)
EOF
