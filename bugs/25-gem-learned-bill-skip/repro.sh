#!/bin/bash
# repro.sh -- Re-record bug 25 through the NetHack recorder binary and check
# the price of the unpaid glass after it has been identified.
#
# The session goes to Minetown (seed 6260) in wizard mode, enters the general
# store, picks up a shop scroll and reads it (a used up item on the bill),
# then sells a wished-for worthless piece of white glass to the shopkeeper,
# picks it back up (billed at 800 zorkmids, the price the shopkeeper asks for
# unidentified white glass in this game), and identifies it with a scroll of
# identify.  gem_learned() should reprice it to 5 zorkmids; on the stock
# build it stays at 800 because the used up scroll comes first on the bill.
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed), 2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."

SESSION=bugs/25-gem-learned-bill-skip/session.json
TMP_OUT=$(mktemp -t bugrep25_XXXX.json)
trap "rm -f $TMP_OUT" EXIT

echo "=== Re-recording $SESSION ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the identified glass's bill price ==="
PRICE=$(python3 - "$TMP_OUT" <<'PY'
import json, re, sys
steps = json.load(open(sys.argv[1]))['segments'][0]['steps']
price = 'none'
for s in steps:
    top = (s.get('screen') or '').split('\n')[0]
    m = re.search(r'worthless piece of white glass \(unpaid, (\d+) zorkmids\)', top)
    if m:
        price = m.group(1)
print(price)
PY
)
echo "identified glass is billed at: $PRICE zorkmids"

case "$PRICE" in
  800)
    echo
    echo "BUG CONFIRMED -- identifying the glass did not reprice it, because"
    echo "gem_learned() stopped advancing at the used up scroll on the bill."
    exit 0 ;;
  5)
    echo
    echo "BUG NOT REPRODUCED -- the glass was repriced to 5 zorkmids."
    echo "proposed-fix.patch (or an equivalent) is probably applied."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the scenario did not reach the identified glass."
    exit 2 ;;
esac
