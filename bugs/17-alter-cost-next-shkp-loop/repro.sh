#!/bin/bash
# repro.sh -- Bug 17 has no game session that shows it (see README.md), so
# this runs two static checks, in the style of bug 11.
#
# 1. repro.c contains next_shkp() and the alter_cost() loop as written in
#    src/shk.c and runs them on two shopkeepers with bills.  The upstream loop
#    never advances past the first; the proposed one finds the second.
#
# 2. It then looks at your tree and reports whether alter_cost() still passes
#    the current shopkeeper back to next_shkp().
#
# Exit 0 = bug present, 1 = patched, 2 = unrecognised.
set -e
cd "$(dirname "$0")"

echo "=== 1/2: the loop ==="
BIN=$(mktemp -t bugrep17_XXXX)
trap 'rm -f "$BIN"' EXIT
${CC:-cc} -o "$BIN" repro.c
set +e
"$BIN"
LOOP=$?
set -e

echo
echo "=== 2/2: your tree ==="
SHK=""
for cand in ../../nethack-c/upstream/src/shk.c ../../src/shk.c; do
    [ -f "$cand" ] && SHK="$cand" && break
done
if [ -z "$SHK" ]; then
    echo "src/shk.c not found (looked in nethack-c/upstream/src and ../../src)."
    exit $LOOP
fi

# alter_cost()'s loop, from its opening line to the onbill() test
BODY=$(awk '/^alter_cost\(/ {f=1} f && /onbill\(obj, shkp, TRUE\)/ {print; exit} f {print}' "$SHK")
if echo "$BODY" | grep -q 'next_shkp(shkp, TRUE)'; then
    echo "AFFECTED: $SHK: alter_cost() advances with next_shkp(shkp, TRUE):"
    echo "$BODY" | grep -n 'next_shkp' | sed 's/^/    /'
    exit $LOOP
fi
if echo "$BODY" | grep -q 'next_shkp(shkp->nmon, TRUE)'; then
    echo "PATCHED: $SHK: alter_cost() advances with next_shkp(shkp->nmon, TRUE)."
    exit 1
fi
echo "UNRECOGNISED: alter_cost() in $SHK has neither form; check it by hand."
exit 2
