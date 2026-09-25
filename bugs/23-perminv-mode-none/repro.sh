#!/bin/bash
# repro.sh -- Re-record bug 23 and check that OPTIONS=perminv_mode:none makes
# the game try to turn persistent inventory ON.
#
# The default Unix tty build has no persistent inventory support, so there the
# bug has no visible effect (session-default-build.json).  This script builds
# a private copy of the recorder with TTY_PERM_INVENT defined in
# include/config.h (the build option config.h documents for this, and the one
# the Windows console port always uses), then re-records session.json with it.
#
# On that build, with perminv_mode:none in the nethackrc, the game starts by
# printing
#     tty perm_invent could not be enabled.
#     tty perm_invent needs a terminal that is at least 52x79, yours is 24x80.
# i.e. it tried to open the persistent inventory window the player asked not
# to have.  With the fix, nothing is printed.
#
# The private build lives in /tmp/nethack-bugreport-23 and takes a minute or
# two.  Set NETHACK_BINARY and NETHACK_INSTALL to use an existing
# TTY_PERM_INVENT build instead.
#
# Exit: 0 = bug confirmed, 1 = not reproduced (probably fixed),
#       2 = inconclusive.
set -e
cd "$(dirname "$0")/../.."
REPO=$(pwd)

SESSION=bugs/23-perminv-mode-none/session.json
TMP_OUT=$(mktemp -t bugrep23_XXXX.json)
trap 'rm -f "$TMP_OUT"' EXIT

if [ -z "$NETHACK_BINARY" ]; then
    echo "=== Building a TTY_PERM_INVENT recorder in /tmp/nethack-bugreport-23 ==="
    rm -rf /tmp/nethack-bugreport-23
    mkdir -p /tmp/nethack-bugreport-23
    rsync -a --exclude=recorder --exclude=.git \
        "$REPO/nethack-c/" /tmp/nethack-bugreport-23/nethack-c/
    # reuse the Lua source the main recorder build already fetched, if any
    if [ -d "$REPO/nethack-c/recorder/lib/lua-5.4.8" ]; then
        mkdir -p /tmp/nethack-bugreport-23/nethack-c/upstream/lib
        rsync -a "$REPO/nethack-c/recorder/lib/lua-5.4.8" \
            /tmp/nethack-bugreport-23/nethack-c/upstream/lib/
    fi
    sed -i.bak 's|^/\* #define TTY_PERM_INVENT \*/|#define TTY_PERM_INVENT|' \
        /tmp/nethack-bugreport-23/nethack-c/upstream/include/config.h
    if ! grep -q '^#define TTY_PERM_INVENT' \
            /tmp/nethack-bugreport-23/nethack-c/upstream/include/config.h; then
        echo "INCONCLUSIVE -- could not enable TTY_PERM_INVENT in config.h"
        exit 2
    fi
    bash /tmp/nethack-bugreport-23/nethack-c/build-recorder.sh \
        > /tmp/nethack-bugreport-23/build.log 2>&1 || {
        echo "INCONCLUSIVE -- build failed; see /tmp/nethack-bugreport-23/build.log"
        exit 2
    }
    export NETHACK_INSTALL=/tmp/nethack-bugreport-23/nethack-c/recorder/install/games/lib/nethackdir
    export NETHACK_BINARY=$NETHACK_INSTALL/nethack
fi

echo "=== Re-recording $SESSION with $NETHACK_BINARY ==="
node scripts/record-session.mjs "$SESSION" "$TMP_OUT"

echo
echo "=== Checking the start of the game ==="
RESULT=$(python3 -c "
import json
d = json.load(open('$TMP_OUT'))
steps = []
for seg in d.get('segments', [d]):
    steps += seg.get('steps', [])
screens = [s.get('screen') or '' for s in steps]
tried = any('tty perm_invent could not be enabled' in s for s in screens)
started = any('welcome to NetHack!' in s for s in screens)
print('STEPS=%d STARTED=%d TRIED_PERM_INVENT=%d' % (len(steps), started, tried))
")
echo "$RESULT"

case "$RESULT" in
  *"STARTED=1 TRIED_PERM_INVENT=1")
    echo
    echo "BUG CONFIRMED -- with perminv_mode:none the game tried to enable"
    echo "persistent inventory at startup."
    exit 0 ;;
  *"STARTED=1 TRIED_PERM_INVENT=0")
    echo
    echo "BUG NOT REPRODUCED -- no attempt to enable persistent inventory."
    echo "proposed-fix.patch is probably already applied, or the binary was"
    echo "built without TTY_PERM_INVENT."
    exit 1 ;;
  *)
    echo
    echo "INCONCLUSIVE -- the recording did not reach the start of the game."
    exit 2 ;;
esac
