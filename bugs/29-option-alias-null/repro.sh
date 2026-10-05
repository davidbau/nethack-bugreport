#!/bin/bash
# repro.sh -- bug 29: a duplicate option in a comma-separated OPTIONS list
# is reported as
#     compound option specified multiple times: name (via alias: (null)).
# when an element to its right named an option by its alias.
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, then starts one game on a pty with
# this ~/.nethackrc and captures the config-error report:
#     OPTIONS=name:nonesuch
#     OPTIONS=name:Xorn,align:neutral
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen, 1 = not seen, 2 = build failed.
set -e
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bugrep29_XXXX")
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

echo "=== Building (sys/unix/hints/linux.501, PREFIX in the work dir)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
echo "    binary: $NH"

mkdir -p "$WORK/home"
printf 'OPTIONS=name:nonesuch\nOPTIONS=name:Xorn,align:neutral\n' > "$WORK/home/.nethackrc"
echo "=== ~/.nethackrc:"; sed 's/^/    /' "$WORK/home/.nethackrc"

python3 - "$NH" "$WORK/home" <<'PY'
import os, pty, re, select, sys, time
nh, home = sys.argv[1], sys.argv[2]
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester"}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.path.dirname(nh)); os.execve(nh, ["nethack"], env)
out = b""
end = time.time() + 5
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try: out += os.read(fd, 65536)
        except OSError: break
    if b"error" in out and b"multiple times" in out: time.sleep(0.5); break
os.kill(pid, 9); os.waitpid(pid, 0)
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]", "", out.decode("latin-1"))
lines = [l.strip() for l in text.splitlines() if "multiple times" in l]
msg = lines[0] if lines else "(no duplicate-option message)"
print("=== config error:", msg)
bad = "via alias" in msg      # 'name' has no alias and was not named by one
print("=== BUG SEEN: 'name' reported as given via an alias" if bad
      else "=== bug not seen")
sys.exit(0 if bad else 1)
PY
