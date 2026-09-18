#!/bin/bash
# repro.sh — Bug 11 has two halves, and this runs both.
#
# 1. repro.c is pure math: it contains the upstream formula and the proposed
#    one, simulates both, and shows that the upstream dwarf advantage drifts
#    between roughly 2.6x and 5.3x instead of being the constant 2x the code
#    reads as.  No NetHack build or headers needed.
#
# 2. Then it looks at your tree, which repro.c cannot do, and reports whether
#    src/dig.c still has the upstream form.
set -e
cd "$(dirname "$0")"

echo "=== 1/2: the arithmetic ==="
${CC:-cc} -o /tmp/bugrep11_$$ repro.c
trap "rm -f /tmp/bugrep11_$$" EXIT
set +e
/tmp/bugrep11_$$
MATH=$?
set -e

echo
echo "=== 2/2: your tree ==="
DIG=""
for cand in ../../nethack-c/upstream/src/dig.c ../../src/dig.c; do
    [ -f "$cand" ] && DIG="$cand" && break
done

if [ -z "$DIG" ]; then
    echo "src/dig.c not found (looked in nethack-c/upstream/src and ../../src)."
    echo "Run bash setup.sh from the repo root to populate the submodule, or"
    echo "check the formula by hand at dig.c's 'Race_if(PM_DWARF)'."
    exit $MATH
fi

if grep -qE 'digging\.effort \*= 2' "$DIG"; then
    echo "AFFECTED: $DIG still doubles the accumulated effort:"
    grep -nE -B 2 'digging\.effort \*= 2' "$DIG" | sed 's/^/    /'
    exit $MATH
fi

if grep -qE 'inc \*= 2' "$DIG"; then
    echo "PATCHED: $DIG doubles the per-turn increment."
    exit 1
fi

echo "UNRECOGNISED: $DIG has neither form; the dwarf bonus may have been"
echo "rewritten. Check dig.c's 'Race_if(PM_DWARF)' by hand."
exit 2
