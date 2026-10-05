#!/bin/bash
# repro.sh -- bug 32: on tty, a message that follows one shown with
# SUPPRESS_HISTORY (show_topl()) without a keystroke in between is appended
# as if the line held only the earlier history messages, so it can be
# written past column 80.
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, starts a wizard-mode game in an
# 80x24 pty, and runs #wizloadlua on this script:
#
#     nh.pushkey("\29")   -- ^] is unbound: "Unknown command '^]'." (21 cols,
#     nh.doturn()         --   shown by show_topl(), not in gt.toplines)
#     nh.pline("The first message here is fifty-five characters in all.")
#     nh.pline("Second one")
#
# The queued key is read without tty_nhgetch(), which is what normally
# downgrades TOPLINE_NEED_MORE, the same as the debug fuzzer's keys.
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen (cursor addressed past column 80), 1 = not seen,
# 2 = build failed.
set -e
WORK=$(mktemp -d -t bugrep32_XXXX)
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
HACKDIR=$(dirname "$NH")
sed -i 's/^WIZARDS=.*/WIZARDS=*/' "$HACKDIR/sysconf"
cat > "$HACKDIR/bug32.lua" <<'LUA'
nh.pushkey("\29")
nh.doturn()
nh.pline("The first message here is fifty-five characters in all.")
nh.pline("Second one")
LUA
echo "    binary: $NH"

echo "=== Wizard-mode game in an 80x24 pty: #wizloadlua bug32"
python3 - "$NH" "$WORK" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time
nh, work = sys.argv[1], sys.argv[2]
home = os.path.join(work, "home"); os.makedirs(home)
open(os.path.join(home, ".nethackrc"), "w").write(
    "OPTIONS=!autopickup,!legacy,!tutorial,!tips,!splash_screen,pettype:none\n"
    "OPTIONS=role:valkyrie,race:human,gender:female,align:neutral\n")
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "wizard"}
winsz = struct.pack("HHHH", 24, 80, 0, 0)
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, winsz)
    os.chdir(os.path.dirname(nh)); os.execve(nh, ["nethack", "-D", "-u", "wizard"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, winsz)
out = b""
def rd(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: return
def more_pending():
    return out.rstrip(b"\x1b[?12l\x1b[?25h").endswith(b"--More--")
rd(3)
for _ in range(10):                  # dismiss any startup --More--
    if not more_pending(): break
    os.write(fd, b" "); rd(0.5)
start = len(out)
for k in "#wizloadlua\rbug32\r":
    os.write(fd, k.encode()); rd(0.3)
for _ in range(3):                   # the fixed version stops at --More--
    if not more_pending(): break
    os.write(fd, b" "); rd(0.5)
os.kill(pid, 9); os.waitpid(pid, 0)
s = out[start:].decode("latin-1")
s = s[s.find("Unknown command"):] if "Unknown command" in s else s
# top-line writes: cursor address on row 1 followed by text
bad = []
for m in re.finditer(r"\x1b\[1;(\d+)H([^\x1b]*)", s):
    print(f"    row 1, column {int(m.group(1)):3d}: {m.group(2)!r}")
    if int(m.group(1)) > 80:
        bad.append(m)
if "--More--" in s:
    print("    (a --More-- was shown before the next message)")
if bad:
    print(f"BUG: tty addressed the cursor to column {bad[0].group(1)} of an "
          f"80-column terminal to write {bad[0].group(2)!r}")
    sys.exit(0)
print("OK: every top-line message started at or before column 80")
sys.exit(1)
PY
