#!/bin/bash
# repro.sh -- bug 31: the tutorial's nh.parse_config("OPTIONS=mention_decor")
# (dat/tut-1.lua) is silently ignored, so mention_decor stays off in the
# tutorial while mention_walls, set two lines earlier, is on.
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, starts a new game with no config
# file, accepts the character, answers 'y' to "Do you want a tutorial?", then
# opens #optionsfull and reads the values of mention_decor and mention_walls.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen (mention_decor off in the tutorial), 1 = not seen,
# 2 = build failed or the game could not be driven.
set -e
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep31_XXXX")
trap 'rm -rf "$WORK"' EXIT

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

echo "=== Building (sys/unix/hints/linux.501, PREFIX in the work dir)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
echo "    binary: $NH"

echo "=== New game, 'y' to the tutorial, then #optionsfull"
set +e
python3 - "$NH" "$WORK" <<'PY'
import os, pty, re, select, sys, tempfile, time
nh, work = sys.argv[1], sys.argv[2]
hackdir = os.path.dirname(nh)
home = tempfile.mkdtemp(prefix="home_", dir=work)
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin",
       "USER": "tester", "LINES": "24", "COLUMNS": "80"}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(hackdir); os.execve(nh, ["nethack", "-u", "tester"], env)
out = b""
def rd(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: return
rd(3)
# accept character, dismiss intro, 'y' to tutorial, dismiss messages,
# then page through the full options menu
keys = ["y", " ", " ", " ", "y"] + [" "] * 6 + ["\x1b"] \
       + list("#optionsfull\r") + [">"] * 8
for k in keys:
    os.write(fd, k.encode()); rd(0.6)
os.kill(pid, 9); os.waitpid(pid, 0)
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]", "\n",
              out.decode("latin-1"))
def val(name):
    m = re.search(r"\b" + name + r"\s+\[(true|false)\]", text)
    return m.group(1) if m else None
intut = "Entering the tutorial." in text
decor, walls = val("mention_decor"), val("mention_walls")
print(f"  in the tutorial: {'yes' if intut else 'no'}")
print(f"  mention_walls = {walls}   (tut-1.lua: OPTIONS=mention_walls)")
print(f"  mention_decor = {decor}   (tut-1.lua: OPTIONS=mention_decor)")
if not intut or decor is None or walls is None:
    print("=== could not drive the game to the options menu"); sys.exit(2)
if decor == "false":
    print("=== BUG: the tutorial's mention_decor setting was ignored"); sys.exit(0)
print("=== OK: the tutorial's mention_decor setting is in effect"); sys.exit(1)
PY
