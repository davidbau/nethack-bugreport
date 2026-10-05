#!/bin/bash
# repro.sh -- bug 35: a des.map whose rows differ in length makes
# mapfrag_get() read past the end of the map string.
#
# Builds a NetHack-5.0 checkout (the upstream head, or the source tree given
# as $1) with the stock Linux hints and AddressSanitizer (WANT_ASAN=1),
# starts a wizard-mode game, and loads this level script with #wizloaddes:
#
#     des.map([[
#     ---
#     |.|
#     |...........|
#     ---
#     ]]);
#
# The rows are 3, 3, 13 and 3 characters, so the map is 13 wide and the
# string is 26 bytes (alloc() rounds the block to 32); mapfrag_get() reads
# row y from offset y*14, so row 2 runs from 28 to 40 and row 3 from 42.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = ASan reports the over-read, 1 = not seen, 2 = build failed.
set -e
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep35_XXXX")
[ -n "$KEEP" ] || trap 'rm -rf "$WORK"' EXIT

if [ -n "$1" ]; then
    SRC=$(cd "$1" && pwd)
    echo "=== Copying $SRC ($(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?'))"
    cp -r "$SRC" "$WORK/NetHack"
else
    echo "=== Cloning the NetHack-5.0 head"
    git clone -q --depth 1 -b NetHack-5.0 https://github.com/NetHack/NetHack.git "$WORK/NetHack"
fi
cd "$WORK/NetHack"
echo "    at $(git rev-parse --short HEAD 2>/dev/null): $(git log -1 --format='%cd %s' --date=short 2>/dev/null)"

echo "=== Building with AddressSanitizer (sys/unix/hints/linux.501, WANT_ASAN=1)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make WANT_ASAN=1 PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
   || ! make WANT_ASAN=1 PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
[ -n "$NH" ] || { echo "no nethack binary installed"; exit 2; }
HACKDIR=$(dirname "$NH")
sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$HACKDIR/sysconf"
cat > "$HACKDIR/ragged.lua" <<'EOF'
des.map([[
---
|.|
|...........|
---
]]);
EOF

echo "=== Wizard mode: #wizloaddes ragged.lua"
mkdir "$WORK/log"
python3 - "$NH" "$WORK/log" <<'PY'
import os, pty, select, sys, tempfile, time
nh, logdir = sys.argv[1:3]
home = tempfile.mkdtemp(dir=logdir)
open(os.path.join(home, ".nethackrc"), "w").write(
    "OPTIONS=!tutorial,!legacy,!news,role:valkyrie,race:human,"
    "gender:female,align:neutral,pettype:none\n")
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
       "ASAN_OPTIONS": "detect_leaks=0:log_path=" + os.path.join(logdir, "asan")}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.path.dirname(nh))
    os.execve(nh, ["nethack", "-D", "-u", "tester"], env)
out = b""
def rd(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: return False
    return True
rd(3)
for k in [" ", " ", "#wizloaddes\r", "ragged.lua\r", " ", " "]:
    os.write(fd, k.encode())
    if not rd(1.5): break
try: os.kill(pid, 9)
except OSError: pass
os.waitpid(pid, 0)
open(os.path.join(logdir, "screen.txt"), "wb").write(out)
PY
REPORT=$(cat "$WORK"/log/asan.* 2>/dev/null || true)
if [ -n "$REPORT" ]; then
    echo "$REPORT" | grep -m1 'ERROR: AddressSanitizer'
    echo "$REPORT" | grep -m3 -E '#[0-9]+ .* in (mapfrag_get|lspo_map|wiz_load_splua) '
    echo "$REPORT" | grep -m1 'located'
    if echo "$REPORT" | grep -q 'in mapfrag_get '; then
        echo "BUG CONFIRMED -- mapfrag_get() read past the end of the ragged map"
        exit 0
    fi
    echo "ASan reported something else (see above)"
    exit 1
fi
if ! grep -aq 'Load which des lua file' "$WORK/log/screen.txt"; then
    echo "cannot evaluate: #wizloaddes did not run"; exit 2
fi
echo "not seen -- the ragged map loaded with no ASan report"
exit 1
