#!/bin/bash
# repro.sh -- bug 28: a monster hidden under an object is unhidden whenever
# its level is read back in by getlev() (save/restore, changing levels, bones).
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints and WIZARDS=* in sysconf, then plays
# three short wizard-mode games through a pty:
#   game 1: #wizloaddes a small level whose garter snake is created hidden
#           under a random object (makemon() does this for snakes made during
#           level creation), look at the snake's square with ';', save
#   game 2: restore that save, look at the square again
#   game 3: load the level again, go down the stairs and come back, look
# The map character at the square is the object while the snake is hidden
# and 'S' once it is not.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen, 1 = not seen, 2 = build failed.
set -e
WORK=$(mktemp -d -t bugrep28_XXXX)
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
if ! make PREFIX="$WORK/inst" -j8 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
HACKDIR=$(dirname "$NH")
echo "    binary: $NH"
sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$HACKDIR/sysconf"

# des files are found in HACKDIR when they are not in nhdat
cat > "$HACKDIR/hider.lua" <<'LUA'
-- #wizloaddes hider: a lit, open level with a down staircase at <40,10>
-- and a sleeping garter snake two squares east of it, at <42,10>.
-- makemon() gives a snake created during level creation a random object
-- and calls hideunder(), so the snake starts out hidden under that object.
-- (Without a des.map, des coordinates are offset by xstart=1.)
des.level_init({ style = "solidfill", fg = ".", lit = true })
des.level_flags("noflip")
des.stair("down", 39, 10)
des.monster({ id = "garter snake", x = 41, y = 10, asleep = true })
LUA

cat > "$WORK/screen.py" <<'PY'
import re
def render(data, rows=24, cols=80):
    scr = [[" "] * cols for _ in range(rows)]
    r = c = 0
    tok = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])|\x1b[()][0-9A-B]|\x1b[=>78M]|.", re.S)
    for m in tok.finditer(data):
        s = m.group(0)
        if m.group(2):
            args = [int(a) if a.isdigit() else 0 for a in m.group(1).replace("?", "").split(";")] if m.group(1) else []
            f = m.group(2); a0 = args[0] if args else 0
            if f == "H": r = (args[0] - 1 if args and args[0] else 0); c = (args[1] - 1 if len(args) > 1 and args[1] else 0)
            elif f == "A": r = max(0, r - (a0 or 1))
            elif f == "B": r = min(rows - 1, r + (a0 or 1))
            elif f == "C": c = min(cols - 1, c + (a0 or 1))
            elif f == "D": c = max(0, c - (a0 or 1))
            elif f == "K":
                if a0 == 0: scr[r][c:] = [" "] * (cols - c)
                elif a0 == 2: scr[r] = [" "] * cols
            elif f == "J":
                if a0 == 2: scr = [[" "] * cols for _ in range(rows)]
                elif a0 == 0:
                    scr[r][c:] = [" "] * (cols - c)
                    for k in range(r + 1, rows): scr[k] = [" "] * cols
        elif s == "\r": c = 0
        elif s == "\n": r = min(rows - 1, r + 1)
        elif s == "\b": c = max(0, c - 1)
        elif s.startswith("\x1b") or ord(s) < 32: pass
        else:
            if c < cols: scr[r][c] = s
            c += 1
    return ["".join(x).rstrip() for x in scr]
PY

echo "=== Three wizard-mode games"
set +e
python3 - "$NH" "$WORK" <<'PY'
import os, pty, re, select, sys, time
sys.path.insert(0, sys.argv[2])            # screen.py: a minimal vt100 screen
from screen import render
nh = sys.argv[1]; hackdir = os.path.dirname(nh)
home = os.path.join(os.path.dirname(hackdir), "home"); os.makedirs(home, exist_ok=True)
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
       "NETHACKOPTIONS": "role:valkyrie,race:human,gender:female,align:neutral,"
       "!tutorial,!legacy,!tips,!autopickup,number_pad:0"}
SX, SY = 42, 10                      # snake; tty column x-1, row y+1
def cleanup():
    for f in os.listdir(hackdir):
        if re.match(r"^\d+\w+(\.\d+)?$", f) or f.endswith("lock"):
            os.remove(os.path.join(hackdir, f))
def game(steps):
    """steps: list of (keys, tag); returns {tag: screen lines} after each"""
    cleanup()
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(hackdir); os.execve(nh, ["nethack", "-D"], env)
    out = b""; shots = {}
    def rd(t):
        nonlocal out
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: out += os.read(fd, 65536)
                except OSError: return
    rd(2)
    for keys, tag in steps:
        for k in keys:
            os.write(fd, k.encode()); rd(0.3)
        rd(0.5)
        if tag: shots[tag] = render(out.decode("latin-1"))
    try: os.kill(pid, 9)
    except OSError: pass
    os.waitpid(pid, 0)
    cleanup()
    return shots
def at(scr):                       # map character at the snake's square
    line = scr[SY + 1]
    return line[SX - 1] if len(line) >= SX else " "
def look(scr):
    return scr[0].strip()
FARLOOK = [";", ">", "l", "l", "."]       # cursor to '>' then two east
for f in os.listdir(os.path.join(hackdir, "save")):
    os.remove(os.path.join(hackdir, "save", f))
res = []
LOAD = [(["\033", "#wizloaddes\r", "hider\r", "\033", "\033", "\033"], None),
        (["\x14", ">", "."], None)]          # ^T onto the down stairs
# game 1: load the level, look, save; game 2: restore it, look
s1 = game(LOAD + [(FARLOOK, "start"), (["\033", "S", "y"], None)])
s2 = game([(["n", "\033", "\033"], None), (FARLOOK, "restore")])
# game 3: load the level again, go down to level 2 and back up, look
s3 = game(LOAD + [([">"] + ["\033"] * 4 + ["<"] + ["\033"] * 4, None), (FARLOOK, "stairs")])
for tag, scr in (("after #wizloaddes ", s1["start"]),
                 ("after save/restore", s2["restore"]),
                 ("after > and <     ", s3["stairs"])):
    hidden = at(scr) != "S"
    res.append(hidden)
    print(f"  {tag}: map shows '{at(scr)}' at <{SX},{SY}>; farlook: {look(scr)}")
if not res[0]:
    print("VERDICT: setup failed, the snake was not hidden to begin with"); sys.exit(3)
if not all(res):
    print("VERDICT: BUG - the hidden snake was unhidden by reloading its level"); sys.exit(0)
print("VERDICT: no bug - the snake stayed hidden across both reloads"); sys.exit(1)
PY
rc=$?; [ $rc -le 1 ] || rc=2; exit $rc
