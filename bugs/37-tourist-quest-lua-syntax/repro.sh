#!/bin/bash
# repro.sh -- bug 37: dat/Tou-loca.lua and dat/Tou-strt.lua do not compile,
# so the Tourist quest home and locate levels fail to load; Tou-strt.lua
# also gives des.monster() tables positional entries it does not read.
#
# Compiles luac from the tree's own Lua (nhlua/lua/src) and runs `luac -p`
# over every dat/*.lua, then lists des.monster({"name", ...}) calls in
# dat/*.lua (a table whose species is not given as id=).  With GAME=1 it also builds the game with the stock
# Linux hints and, in a pty-driven wizard-mode game, runs
# `#wizloaddes Tou-strt` and `#wizloaddes Tou-loca` (the same load_special()
# that runs on entering those levels) and prints the impossible() text.
#
#   bash repro.sh                 # clone the upstream head
#   bash repro.sh ~/src/NetHack   # use an existing checkout instead
#   GAME=1 bash repro.sh ...      # also the in-game check (builds NetHack)
#
# Exit 0 = some dat/*.lua fails to compile or load, or has a positional
# des.monster table; 1 = none; 2 = build failed.
set -e
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep37_XXXX")
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

echo "=== Building luac from nhlua/lua/src"
L=nhlua/lua/src
if ! ${CC:-cc} -O1 -w -o "$WORK/luac" $(ls $L/*.c | grep -v -e '/lua\.c$' -e '/onelua\.c$') -lm \
     >"$WORK/luac.log" 2>&1; then
    tail -20 "$WORK/luac.log"; exit 2
fi

echo "=== luac -p dat/*.lua"
bad=0
for f in dat/*.lua; do
    if ! out=$("$WORK/luac" -p "$f" 2>&1); then
        echo "  ${out#*/luac: }"
        bad=$((bad + 1))
    fi
done
echo "  $(ls dat/*.lua | wc -l) files, $bad fail to compile"

echo "=== des.monster tables with a positional species"
pos=$(grep -n 'des\.monster *( *{ *"' dat/*.lua || true)
npos=0
[ -z "$pos" ] || npos=$(echo "$pos" | wc -l)
[ -z "$pos" ] || echo "$pos" | sed 's/^/  /'
echo "  $npos found"

ingame=1
if [ -n "$GAME" ]; then
    echo "=== Building NetHack (sys/unix/hints/linux.501)"
    ( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
    if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
       || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
        tail -20 "$WORK/build.log"; exit 2
    fi
    NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
    [ -n "$NH" ] || { echo "no nethack binary installed"; exit 2; }
    sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$(dirname "$NH")/sysconf"
    echo "=== Wizard-mode Tourist: #wizloaddes Tou-strt, #wizloaddes Tou-loca"
    set +e
    python3 - "$NH" "$WORK" <<'PY'
import os, pty, re, select, sys, time
nh, work = sys.argv[1], sys.argv[2]
hackdir = os.path.dirname(nh)
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]|\x1b[=>]|[\x08\x0f\x0e]")
home = os.path.join(work, "home"); os.makedirs(home)
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
       "NETHACKOPTIONS": "role:tourist,race:human,gender:female,"
                         "!legacy,!tutorial,!splash_screen,pettype:none"}
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
def send(k, t=0.8):
    start = len(buf[0])
    os.write(fd, k.encode()); rd(t)
    for _ in range(20):        # dismiss --More-- and "Program in disorder" prompts
        tail = ansi.sub("", buf[0][start:].decode("latin-1")).rstrip()
        if tail.endswith("--More--"):
            os.write(fd, b"\r")
        elif re.search(r"\[ynq?\] \(.\)$", tail):
            os.write(fd, b"n")
        else:
            break
        rd(0.5)
    return ansi.sub("", buf[0][start:].decode("latin-1"))
rd(3); send("y", 2.0); send("\033")
seen = 0
for lev in ("Tou-strt", "Tou-loca"):
    s = send("#wizloaddes\r") + send(lev + "\r", 2.0)
    m = re.search(r"luaL_loadbuffer: Error loading .*?near (?:'[^']*'|<eof>)", s, re.S)
    if m:
        print("  " + lev + ": " + re.sub(r"\s+", " ", m.group(0)))
        seen += 1
    else:
        print("  " + lev + ": loaded without a load error")
try:
    os.kill(pid, 9); os.waitpid(pid, 0)
except OSError:
    pass
sys.exit(0 if seen else 1)
PY
    ingame=$?
    set -e
fi

if [ "$bad" -gt 0 ] || [ "$npos" -gt 0 ] || [ "$ingame" -eq 0 ]; then
    echo "=== BUG CONFIRMED -- $bad dat/*.lua file(s) are not valid Lua;" \
         "$npos des.monster table(s) name the species without id="
    exit 0
fi
echo "=== not seen -- every dat/*.lua compiles and every des.monster table uses id="
exit 1
