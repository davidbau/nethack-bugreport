#!/bin/bash
# repro.sh -- bug 36: after #force on a box, the lock-picking context still
# holds the door of an earlier lock-picking attempt; carried to another
# level with the box, a resumed attempt locks the door at the same x,y there.
#
# Builds a NetHack-5.0 checkout (the upstream head, or the source tree given
# as $1) with the stock Linux hints and plays a wizard-mode game in a pty
# with OPTIONS=autounlock:untrap:
#   level 1: a locked large box under the hero and a closed door to the west
#            (both made with #wizloadlua); apply a skeleton key west and lock
#            the door; wield a mace and #force the box; a hostile grid bug
#            placed diagonally (it cannot reach the hero) stops the #force
#            after one turn; pick up the box.
#   ^V to level 2; #wizloadlua makes a closed door at the level-1 door's x,y
#            (far from the hero) and a scroll of scare monster under the
#            hero; throw the box down (t, >) and #loot it.
# A Lua script reads the level-2 door before and after the #loot.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = the level-2 door was locked by the #loot, 1 = not seen,
# 2 = build failed or the game did not go as scripted.
set -e
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep36_XXXX")
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

echo "=== Building (sys/unix/hints/linux.501, PREFIX in the work dir)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
[ -n "$NH" ] || { echo "no nethack binary installed"; exit 2; }
HACKDIR=$(dirname "$NH")
sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$HACKDIR/sysconf"
echo "    binary: $NH"

echo "=== Wizard-mode game"
set +e
python3 - "$NH" "$WORK" <<'PY'
import os, pty, re, select, sys, time
nh, work = sys.argv[1], sys.argv[2]
hackdir = os.path.dirname(nh)
def lua(name, text):
    with open(os.path.join(hackdir, name + ".lua"), "w") as f:
        f.write(text)
# des.* coordinates are relative to xstart/ystart; R() converts from absolute
PRE = ('des.level_flags("noflip")\n'
       'local ox, oy = nh.abscoord(0, 0)\n'
       'local function R(x, y) return x - ox, y - oy end\n')
lua("xl1", PRE + """
local bx, by = R(u.ux, u.uy)
des.object({ id = "large box", coord = { bx, by }, locked = true })
des.door("closed", bx - 1, by)
nh.pline("XL1 door at " .. (u.ux - 1) .. "," .. u.uy)
""")
lua("xl2", PRE + """
-- a diagonal neighbour that is already floor, so the hero's view of it is current
local x, y
for _, d in ipairs({ {1, 1}, {1, -1}, {-1, 1}, {-1, -1} }) do
   if not x and nh.getmap(R(u.ux + d[1], u.uy + d[2])).typ_name == "ROOM" then
      x, y = R(u.ux + d[1], u.uy + d[2])
   end
end
if not x then x, y = R(u.ux + 1, u.uy + 1) end
des.terrain(x, y, ".")
des.terrain(x - 1, y, "-"); des.terrain(x + 1, y, "-")
des.terrain(x, y - 1, "-"); des.terrain(x, y + 1, "-")
des.monster({ id = "grid bug", x = x, y = y, peaceful = 0, asleep = 0 })
""")
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]|\x1b[=>]|[\x08\x0f\x0e]")

def game(n):
    home = os.path.join(work, "home%d" % n); os.makedirs(home)
    for f in os.listdir(os.path.join(hackdir, "save")):
        os.remove(os.path.join(hackdir, "save", f))
    env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
           "NETHACKOPTIONS": "role:valkyrie,race:human,gender:female,align:neutral,"
                             "!legacy,!tutorial,!splash_screen,!autopickup,"
                             "pettype:none,autounlock:untrap,number_pad:0"}
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(hackdir)
        os.execve(nh, ["nethack", "-D", "-u", "tester"], env)
    buf = [b""]
    def rd(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: buf[0] += os.read(fd, 65536)
                except OSError: return
    def send(k, t=0.5):
        start = len(buf[0])
        os.write(fd, k.encode()); rd(t)
        for _ in range(20):                     # dismiss --More--
            if not ansi.sub("", buf[0][start:].decode("latin-1")).rstrip().endswith("--More--"):
                break
            os.write(fd, b"\r"); rd(0.4)
        return ansi.sub("", buf[0][start:].decode("latin-1"))
    def done(code):
        try:
            os.kill(pid, 9); os.waitpid(pid, 0)
        except OSError:
            pass
        for f in os.listdir(hackdir):
            if re.match(r"^\d+\w+(\.\d+)?$", f) or f.endswith("lock"):
                os.remove(os.path.join(hackdir, f))
        return code
    rd(3); send("\033")
    s = send("\x17") + send("skeleton key\r")
    m = re.search(r"([a-zA-Z]) - [^\n]*?key\.", s)
    s = send("\x17") + send("mace\r")
    m2 = re.search(r"([a-zA-Z]) - [^\n]*?mace\.", s)
    if not m or not m2:
        print("  wishes failed"); return done(2)
    key, mace = m.group(1), m2.group(1)
    send("w" + mace)
    s = send("#wizloadlua\r") + send("xl1\r")
    m = re.search(r"XL1 door at (\d+),(\d+)", s)
    if not m:
        print("  xl1.lua failed:", repr(s[-200:])); return done(2)
    dx, dy = int(m.group(1)), int(m.group(2))
    s = send("a") + send(key) + send("h")
    if "for a trap?" in s:
        s += send("n")
    s += send("y", 2.5)
    if "You succeed in locking the door." not in s:
        print("  level 1: the key did not lock the door (interrupted?); new game")
        return done(3)
    print("  level 1: door at %d,%d -- You succeed in locking the door." % (dx, dy))
    send("#wizloadlua\r"); send("xl2\r")
    s = send("#force\r") + send("y", 2.0)
    if "You stop forcing the lock." not in s or "succeed in forcing" in s:
        print("  level 1: #force was not interrupted; new game")
        return done(3)
    print("  level 1: #force -- You start bashing it with your mace.  You stop forcing the lock.")
    s = send(",", 1.0)
    for _ in range(3):
        if re.search(r"\[ynq\] \(.\) *$", s):
            s += send("y", 1.0)
    m = re.search(r"([a-zA-Z]) - [^\n]*?large box\.", s)
    if not m:
        print("  could not pick up the box:", repr(s[-200:])); return done(2)
    box = m.group(1)
    print("  level 1: picked up the box (%s); ^V to level 2" % box)
    s = send("\x16", 0.8) + send("2\r", 1.5)
    if "Dlvl:2" not in s:
        print("  level teleport failed:", repr(s[-200:])); return done(2)
    lua("xl3", PRE + """
local x, y = R(%d, %d)
des.door("closed", x, y)
-- keeps level-2 monsters from interrupting the occupation (onscary)
des.object({ id = "scare monster", coord = { R(u.ux, u.uy) } })
local m = nh.getmap(x, y)
nh.pline("XL3 hero at " .. u.ux .. "," .. u.uy .. "; %d,%d is " .. m.typ_name .. ", locked=" .. tostring(m.flags.locked))
""" % (dx, dy, dx, dy))
    lua("xl4", PRE + """
local m = nh.getmap(R(%d, %d))
nh.pline("XL4 hero at " .. u.ux .. "," .. u.uy .. "; %d,%d is " .. m.typ_name .. ", locked=" .. tostring(m.flags.locked))
""" % (dx, dy, dx, dy))
    s = send("#wizloadlua\r") + send("xl3\r")
    m3 = re.search(r"XL3 ([^\n]*?locked=\w+)", s)
    if not m3:
        print("  xl3.lua failed:", repr(s[-200:])); return done(2)
    print("  level 2, before: " + m3.group(1))
    s = send("t") + send(box) + send(">", 0.8)
    if "hits the floor" not in s:
        print("  throwing the box down failed:", repr(s[-200:])); return done(2)
    print("  level 2: t %s > -- A locked large box hits the floor." % box)
    alls = ""
    for _ in range(10):
        s = send("#loot\r", 3.0)
        if re.search(r"loot it\? \[ynq\]", s):
            s += send("y", 3.0)
        if "for a trap?" in s:
            s += send("q")
        alls += s
        if "You resume your attempt" not in alls:
            # the grid bug stopped #force before its first turn, so there
            # was no attempt to resume
            print("  level 2: #loot did not resume an attempt; new game")
            return done(3)
        if "You resume your attempt" not in s or "You succeed in" in s or "give up" in s:
            break
    for msg in re.findall(r"(?:The large box is locked\.|Hmmm, [^.]*\.|You (?:resume your attempt at|succeed in|stop|give up your attempt at) [a-z ]+\.)", alls):
        print("  level 2 #loot: " + msg)
    s = send("#wizloadlua\r") + send("xl4\r")
    m4 = re.search(r"XL4 ([^\n]*?locked=\w+)", s)
    if not m4:
        print("  xl4.lua failed:", repr(s[-200:])); return done(2)
    print("  level 2, after:  " + m4.group(1))
    if "locked=true" in m4.group(1) and "locked=false" in m3.group(1):
        print("=== BUG CONFIRMED -- #loot on level 2 locked the door at %d,%d, "
              "the x,y of the level-1 door" % (dx, dy))
        return done(0)
    print("=== not seen -- the level-2 door at %d,%d is still unlocked" % (dx, dy))
    return done(1)

for n in range(8):
    r = game(n)
    if r != 3:
        sys.exit(r)
print("=== could not set up the attempt in 8 games"); sys.exit(2)
PY
