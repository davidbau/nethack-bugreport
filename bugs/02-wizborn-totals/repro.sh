#!/bin/bash
# repro.sh — Re-record bug 02 through a freshly-built NetHack recorder
# binary and assert that the #wizborn totals row is MISSING.
#
# Prerequisites:
#   - nethack-c/recorder/ submodule populated and built
#     (run `bash setup.sh` from the repo root once before this)
#   - node >= 22

set -e

cd "$(dirname "$0")/../.."

SESSION=bugs/02-wizborn-totals/session.json
TMP_OUT=$(mktemp -t bugrep02_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Inspecting #wizborn page screen (step 10) ==="
RESULT=$(python3 -c "
import json, re
d = json.load(open('$TMP_OUT'))
seg = d['segments'][0] if 'segments' in d else d
steps = seg.get('steps') or d.get('steps', [])
scr = steps[10].get('screen', '') or ''
# Find rows that look like per-species output: '\\s+\\d+\\s+\\d+\\s+.\\s+\\w+'
species_rows = re.findall(r'^\\s*\\d+\\s+\\d+\\s+.\\s+\\S+', scr, flags=re.M)
# Find rows that look like a totals row: '\\s+\\d+\\s+\\d+\\s+.\\s*\$' (no name)
totals_rows  = re.findall(r'^\\s*\\d+\\s+\\d+\\s+.\\s*\$', scr, flags=re.M)
print(f'PER_SPECIES_ROWS={len(species_rows)}')
print(f'TOTALS_ROWS={len(totals_rows)}')
print(f'HEADER_PRESENT={int(\"died born\" in scr)}')
")
echo "$RESULT"

PER=$(echo "$RESULT" | grep PER_SPECIES_ROWS | cut -d= -f2)
TOT=$(echo "$RESULT" | grep TOTALS_ROWS | cut -d= -f2)
HDR=$(echo "$RESULT" | grep HEADER_PRESENT | cut -d= -f2)

if [ "$HDR" = "1" ] && [ "$PER" -gt 0 ] && [ "$TOT" = "0" ]; then
    echo
    echo "BUG CONFIRMED — header present, $PER per-species rows present,"
    echo "but $TOT totals rows (expected: 1 once the patch is applied)."
    exit 0
elif [ "$TOT" -ge 1 ]; then
    echo
    echo "BUG NOT REPRODUCED — a totals row was found ($TOT)."
    echo "This may mean the patch is already in your nethack-c/upstream"
    echo "or the recorder binary was built from a fixed source tree."
    exit 1
else
    echo
    echo "BUG NOT REPRODUCED — header missing or no per-species rows;"
    echo "the session may have desynced. Check that nethack-c/upstream"
    echo "is at the recorded commit and that #wizborn is enabled."
    exit 1
fi
