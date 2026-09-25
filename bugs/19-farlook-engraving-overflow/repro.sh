#!/bin/bash
# repro.sh -- Bug 19: farlook writes one byte past temp_buf for a long
# remembered engraving.
#
# The overflow has no visible effect in a normal build, so a normal
# recording cannot show it.  This script checks it three ways:
#
# 1. repro.c copies the string handling of do_screen_description() and
#    add_quoted_engraving() and shows, for every engraving length, whether
#    the closing paren's NUL lands one byte past temp_buf.  No NetHack build
#    needed.
# 2. It looks at your tree's src/pager.c for the upstream or patched form.
# 3. If you point NETHACK_ASAN_INSTALL at the nethackdir of a recorder built
#    with -fsanitize=address (see README.md), it re-records session.json
#    with that binary and looks for AddressSanitizer's report.
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed),
# 2 = inconclusive.
set -e
cd "$(dirname "$0")"
BUNDLE=$(pwd)

echo "=== 1/3: the string handling (repro.c) ==="
BIN=$(mktemp -t bugrep19_XXXX)
LOG=$(mktemp -t bugrep19_XXXX.log)
OUT=$(mktemp -t bugrep19_XXXX.json)
trap "rm -f $BIN $LOG $OUT" EXIT
${CC:-cc} -o "$BIN" repro.c
set +e
"$BIN"
MATH=$?
set -e

echo
echo "=== 2/3: your tree ==="
PAGER=""
for cand in ../../nethack-c/upstream/src/pager.c ../../src/pager.c; do
    [ -f "$cand" ] && PAGER="$cand" && break
done
TREE=unknown
if [ -z "$PAGER" ]; then
    echo "src/pager.c not found (looked in nethack-c/upstream/src and ../../src)."
elif grep -q 'temp_buf\[sizeof temp_buf - 2\]' "$PAGER"; then
    echo "PATCHED: $PAGER truncates temp_buf before adding the paren."
    TREE=patched
elif grep -q 'Strcat(temp_buf, ")");' "$PAGER"; then
    echo "AFFECTED: $PAGER adds the paren to a possibly full temp_buf:"
    grep -n -B 2 'Strcat(temp_buf, ")");' "$PAGER" | sed 's/^/    /'
    TREE=affected
else
    echo "UNRECOGNISED: $PAGER has neither form; check do_screen_description()."
fi

echo
echo "=== 3/3: an AddressSanitizer build (optional) ==="
ASAN=skipped
if [ -n "$NETHACK_ASAN_INSTALL" ]; then
    (cd ../.. && ASAN_OPTIONS=detect_leaks=0 \
        NETHACK_INSTALL="$NETHACK_ASAN_INSTALL" \
        NETHACK_BINARY="$NETHACK_ASAN_INSTALL/nethack" \
        node scripts/record-session.mjs "$BUNDLE/session.json" "$OUT") \
        > "$LOG" 2>&1 || true
    if grep -q 'stack-buffer-overflow' "$LOG" \
       && grep -q 'in do_screen_description' "$LOG"; then
        echo "ASan: stack-buffer-overflow in do_screen_description:"
        grep -E 'ERROR: AddressSanitizer|#1 |overflows this variable' "$LOG" \
            | sed 's/^/    /'
        ASAN=overflow
    else
        echo "ASan: no report for this keystream."
        ASAN=clean
    fi
else
    echo "NETHACK_ASAN_INSTALL not set; skipped (asan-stock.txt has a saved report)."
fi

echo
if [ "$ASAN" = overflow ]; then
    echo "BUG CONFIRMED in the real binary."
    exit 0
fi
if [ "$ASAN" = clean ] || [ "$TREE" = patched ]; then
    echo "BUG NOT REPRODUCED in your build or tree; it is probably fixed."
    exit 1
fi
if [ $MATH -eq 0 ] && [ "$TREE" != unknown ]; then
    echo "BUG CONFIRMED: the upstream code overflows (repro.c) and your tree"
    echo "still has it."
    exit 0
fi
if [ $MATH -eq 0 ]; then
    echo "The upstream code overflows (repro.c); your tree was not checked."
    exit 2
fi
exit 1
