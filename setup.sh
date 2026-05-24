#!/bin/bash
# setup.sh — One-time setup for nethack-bugreport.
# Initializes the upstream NetHack submodule (pinned to the commit
# bugs were recorded against) and builds the recorder binary that
# repro.sh scripts depend on.
#
# Safe to re-run; subsequent invocations are no-ops if everything
# is already in place.

set -e

cd "$(dirname "$0")"

echo "=== 1/2: Initializing nethack-c/upstream submodule ==="
git submodule update --init nethack-c/upstream
echo "  upstream is at: $(cd nethack-c/upstream && git describe --always --tags)"
echo

echo "=== 2/2: Building the recorder binary ==="
if [ -x nethack-c/recorder/install/games/lib/nethackdir/nethack ]; then
    echo "  recorder binary already built at"
    echo "    nethack-c/recorder/install/games/lib/nethackdir/nethack"
    echo "  delete that file and rerun setup.sh to force a rebuild."
else
    bash nethack-c/build-recorder.sh
fi
echo

echo "=== Setup complete ==="
echo "Run a bug repro:  bash bugs/01-vault-guard-parkguard-newsym/repro.sh"
echo "Visualize:        open tools/session-viewer/index.html"
