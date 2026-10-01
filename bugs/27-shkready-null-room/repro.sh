#!/bin/bash
# repro.sh -- bug 27: starting the tutorial on a development build of the
# NetHack-5.0 branch reports
#     untrustworthy null shkp; level_status.shkready is FALSE (1, 0, 0, 0)
#     Program in disorder! ...
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, then starts GAMES new games with no
# config file, exactly as a new player would: name "tester", let the game pick
# the character, accept, dismiss the intro, and answer 'y' to "Do you want a
# tutorial?".  Each game is a fresh process with an empty HOME.
#
# The message appears once per random item the tutorial's large box was
# generated with (0-3 items, so about three games in four).
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#   GAMES=20 bash repro.sh
#
# Exit 0 = bug confirmed in at least one game, 1 = not seen, 2 = build failed.
set -e
GAMES=${GAMES:-10}
WORK=$(mktemp -d -t bugrep27_XXXX)
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
grep -m1 "define NH_DEVEL_STATUS" include/patchlevel.h

echo "=== Building (sys/unix/hints/linux.501, PREFIX in the work dir)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make PREFIX="$WORK/inst" -j8 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(ls "$WORK"/inst/*/nethack "$WORK"/inst/games/lib/nethackdir/nethack 2>/dev/null | head -1)
[ -n "$NH" ] || NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
echo "    binary: $NH"

echo "=== Starting $GAMES new games and choosing the tutorial"
python3 - "$NH" "$GAMES" <<'PY'
import os, pty, re, select, sys, tempfile, time
nh, games = sys.argv[1], int(sys.argv[2])
keys = list("tester") + ["\r", "y", "\r", " ", " ", "y"] + [" "] * 16
hits = []
hackdir = os.path.dirname(nh)
plog = os.path.join(hackdir, "paniclog")    # every impossible() is logged here
def logged():
    try: return [l for l in open(plog) if "untrustworthy null shkp" in l]
    except OSError: return []
for g in range(games):
    home = tempfile.mkdtemp(prefix="nhhome_")
    env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester"}
    before = len(logged())
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(hackdir); os.execve(nh, ["nethack"], env)
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
    for k in keys:
        os.write(fd, k.encode()); rd(0.8)
    os.kill(pid, 9); os.waitpid(pid, 0)
    for f in os.listdir(hackdir):               # stale lock from the kill
        if re.match(r"^\d+tester(\.\d+)?$", f) or f.endswith("lock"):
            try: os.remove(os.path.join(hackdir, f))
            except OSError: pass
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]", "", out.decode("latin-1"))
    new = logged()[before:]
    tut = "utorial" in text
    hits.append(len(new))
    print(f"  game {g + 1:2d}: in the tutorial: {'yes' if tut else 'NO '}  "
          f"'untrustworthy null shkp' x{len(new)}")
    if new and sum(1 for h in hits if h) == 1:
        print("            paniclog:", new[0].strip())
seen = sum(1 for h in hits if h)
print(f"=== the message appeared in {seen} of {games} games")
sys.exit(0 if seen else 1)
PY
