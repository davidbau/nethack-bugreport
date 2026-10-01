#!/bin/bash
# repro.sh -- bug 15: the order pairs() visits a callback table in, and so
# the order nh_callback_run() runs two callbacks on one event in, changes
# from run to run of the same program.
#
# Builds a standalone interpreter from the Lua that the recorder build
# embeds (lib/lua-5.4.8), then runs order.lua five times.
#
# Exit 0 = bug confirmed (the orders differ), 1 = not reproduced.
set -e
cd "$(dirname "$0")/../.."
LUASRC=nethack-c/recorder/lib/lua-5.4.8/src
[ -f "$LUASRC/lua.c" ] || { echo "build the recorder first: bash setup.sh"; exit 2; }
TMP=$(mktemp -d -t bugrep15_XXXX); trap "rm -rf $TMP" EXIT
cc -O1 -w -DLUA_USE_LINUX -o "$TMP/lua" $(ls "$LUASRC"/*.c | grep -v /luac.c) -lm -ldl
for i in 1 2 3 4 5; do "$TMP/lua" bugs/15-lua-callback-order/order.lua; done | tee "$TMP/orders"
n=$(sort -u "$TMP/orders" | wc -l)
echo "$n distinct orders in 5 runs"
[ "$n" -gt 1 ]
