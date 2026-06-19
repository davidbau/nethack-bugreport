#!/bin/bash
# repro.sh — Compile and run repro.c.  Exits 0 if the bit collision is
# present (which it is in vanilla NetHack 5.0); exits 1 if absent
# (e.g., the proposed patch has been applied to your tree).
#
# Self-contained: needs only a C compiler.  No NetHack build required.
# The bug is in pure bit math involving header-defined constants, so
# the repro is a standalone C program that hard-codes the relevant
# macros from `nethack-c/upstream/include/{align,dgn_file}.h`.

set -e

cd "$(dirname "$0")"

CC="${CC:-cc}"
TMP_BIN=$(mktemp -t bugrep03_XXXX)
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
    echo "BUG CONFIRMED — init_level's fallback returns AM_CHAOTIC for the"
    echo "Tutorial inputs, but the Lua-parsed alignment is AM_NONE."
    exit 0
else
    echo
    echo "BUG NOT REPRODUCED — the two derivations agree.  Either the"
    echo "proposed patch has been applied, or the constants this repro"
    echo "hard-codes from nethack-c/upstream/include/ have changed."
    exit 1
fi
