#!/bin/bash
# repro.sh -- bug 30: two defects in Lua selections (src/selvar.c, src/nhlsel.c)
#   (a) a point set after a point was cleared lies outside the selection's
#       cached bounds, and |, &, ~ and - drop it;
#   (b) a selection holding the value -1 is cloned with dupstr(), which
#       stops at the NUL that -1 is stored as; the clone's map is a short
#       heap block and setting a point in it writes past the end.
#
# Builds the NetHack-5.0 head (or the source tree given as $1) with the stock
# Linux hints plus USE_ASAN=1, then starts a wizard-mode game and runs
# selbug_a.lua and selbug_b.lua with #wizloadlua.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = a bug is seen, 1 = neither is seen, 2 = build or run failure.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep30_XXXX")
trap 'rm -rf "$WORK"' EXIT

if [ -n "$1" ]; then
    SRC=$(cd "$1" && pwd)
    echo "=== Copying $SRC"
    cp -r "$SRC" "$WORK/NetHack"
    rm -rf "$WORK/NetHack/.git"
else
    echo "=== Cloning the NetHack-5.0 head"
    git clone -q --depth 1 -b NetHack-5.0 https://github.com/NetHack/NetHack.git "$WORK/NetHack"
fi
cd "$WORK/NetHack"

echo "=== Building with -fsanitize=address (hints/linux.501, USE_ASAN=1)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
# (a -j4 build can race on src/hacklib.a; finish it serially if so)
if ! { make USE_ASAN=1 PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
       || make USE_ASAN=1 PREFIX="$WORK/inst" >>"$WORK/build.log" 2>&1; } \
   || ! make USE_ASAN=1 PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
HACKDIR=$(dirname "$NH")
sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$HACKDIR/sysconf"
cp "$HERE/selbug_a.lua" "$HERE/selbug_b.lua" "$HACKDIR/"

echo "=== Wizard mode: #wizloadlua selbug_a, then selbug_b"
python3 - "$NH" "$WORK" <<'PY'
import glob, os, pty, re, select, sys, time
nh, work = sys.argv[1], sys.argv[2]
hackdir = os.path.dirname(nh)
env = {"HOME": work, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
       "NETHACKOPTIONS": "role=val,race=hum,gender=fem,align=neu,!legacy,"
                         "!tutorial,!autopickup,msg_window:s",
       "ASAN_OPTIONS": "detect_leaks=0:log_path=" + work + "/asan"}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(hackdir)
    os.execve(nh, ["nethack", "-D", "-u", "tester"], env)
out = b""
def rd(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: return
rd(4)
for k in ["#wizloadlua\r", "selbug_a\r", " ", " ", "\033",
          "#wizloadlua\r", "selbug_b\r", " ", " "]:
    os.write(fd, k.encode()); rd(1.5)
try: os.kill(pid, 9)
except OSError: pass
os.waitpid(pid, 0)
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]", "", out.decode("latin-1"))
res = dict(re.findall(r"SELBUG (a1|a2|b) (\w+=\d+(?: of \d+)?)", text))
asan = "".join(open(f).read() for f in glob.glob(work + "/asan*"))
bad = 0
for k in ("a1", "a2"):
    m = re.match(r"union=(\d+) of (\d+)", res.get(k, ""))
    if not m:
        print(f"  ({k}) no result; screen tail: {text[-300:]!r}"); sys.exit(2)
    lost = int(m.group(1)) != int(m.group(2))
    bad |= lost
    print(f"  ({k}) s has {m.group(2)} point(s); s | selection.new() has "
          f"{m.group(1)}: {'BUG, point dropped' if lost else 'ok'}")
if "heap-buffer-overflow" in asan:
    bad = 1
    print("  (b) BUG, AddressSanitizer:")
    for l in asan.splitlines():
        m = re.search(r"#([0-3]) \S+ in (\w+) \S*?([\w.]+:\d+)", l)
        if "ERROR: AddressSanitizer" in l:
            print("      " + re.sub(r" at pc.*", "", l.split("ERROR: ")[1]))
        elif "is located" in l or l.startswith(("READ", "WRITE")):
            print("      " + l.strip())
        elif m:
            print(f"        #{m.group(1)} {m.group(2)} {m.group(3)}")
elif "b" in res:
    print(f"  (b) clone of a selection holding -1: {res['b']}, no ASan report: ok")
else:
    print("  (b) no result"); sys.exit(2)
print("=== verdict:", "BUG SEEN" if bad else "no bug seen")
sys.exit(0 if bad else 1)
PY
