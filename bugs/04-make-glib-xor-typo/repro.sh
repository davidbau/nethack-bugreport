#!/bin/bash
# repro.sh — Compile and run repro.c.  Exits 0 if the XOR typo is present
# (which it is in vanilla NetHack 5.0); exits 1 if absent (e.g., the
# proposed `!` -> `!!` fix has been applied to your tree).
#
# Self-contained: needs only a C compiler.  No NetHack build required.
# The bug is in a one-line boolean expression; the repro is a
# standalone C program that runs the same expression against all four
# (old, new) state combinations and prints a truth table.

set -e

cd "$(dirname "$0")"

CC="${CC:-cc}"
TMP_BIN=$(mktemp -t bugrep04_XXXX)
trap "rm -f $TMP_BIN" EXIT

echo "=== Compiling repro.c with $CC ==="
"$CC" -O0 -Wall -Wextra -o "$TMP_BIN" repro.c
echo "  -> $TMP_BIN"

echo
echo "=== Running repro ==="
"$TMP_BIN"
RC=$?

if [ "$RC" -eq 0 ]; then
    echo
    echo "BUG CONFIRMED — (!Glib ^ !!xtime) returns the inverse of the"
    echo "real boolean-transition predicate on all four state combinations."
    exit 0
else
    echo
    echo "BUG NOT REPRODUCED — the expression agrees with the real-transition"
    echo "predicate.  Either the proposed `!` -> `!!` fix has been applied,"
    echo "or the line has otherwise been rewritten."
    exit 1
fi
