#!/bin/bash
# repro.sh -- bug 33: a Lua boolean given as a string ("true", "false",
# "yes", "no") is read with the wrong value by get_table_boolean().
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, drops a small des-file script,
# boolstr.lua, into the installed data directory, starts a wizard-mode game
# and runs it with #wizloaddes.  For each form of
#     des.object({ id = "chest", coord = { u.ux, u.uy }, locked = V })
# the script creates 8 chests under the hero and prints how many came out
# locked.  (#wizloaddes then finalizes the ordinary level 1 as if it were a
# special level, which prints "Couldn't place lregion"; that is unrelated.)
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen (locked="true" gives unlocked chests and locked="false"
# gives locked ones), 1 = not seen, 2 = build or run failed.
set -e
WORK=$(mktemp -d -t bugrep33_XXXX)
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
if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1 \
   || ! make PREFIX="$WORK/inst" install >>"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi
NH=$(find "$WORK/inst" -name nethack -type f -perm -u+x | head -1)
HACKDIR=$(dirname "$NH")
echo "    binary: $NH"
sed -i "s/^WIZARDS=.*/WIZARDS=*/" "$HACKDIR/sysconf"

cat > "$HACKDIR/boolstr.lua" <<'LUA'
local forms = { {"true", true}, {"false", false},
                {'"true"', "true"}, {'"false"', "false"},
                {'"yes"', "yes"}, {'"no"', "no"} }
for _, f in ipairs(forms) do
   local n = 0
   for i = 1, 8 do
      local box = des.object({ id = "chest", coord = { u.ux, u.uy },
                               locked = f[2] })
      if box:totable().olocked ~= 0 then n = n + 1 end
   end
   nh.pline("RESULT locked=" .. f[1] .. ": " .. n .. "/8 locked")
end
LUA

echo "=== Wizard mode: #wizloaddes boolstr"
python3 - "$NH" <<'PY'
import os, pty, re, select, sys, tempfile, time
nh = sys.argv[1]
home = tempfile.mkdtemp(prefix="nhhome_")
env = {"HOME": home, "TERM": "xterm", "PATH": "/usr/bin:/bin", "USER": "tester",
       "NETHACKOPTIONS": "role:valkyrie,race:human,gender:female,align:neutral,"
                         "!legacy,!tutorial,!splash_screen,!autopickup"}
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
            except OSError: return
rd(3)
for k in ["\r", " ", " ", "\033", "#wizloaddes\r", "boolstr\r"] + [" "] * 12:
    os.write(fd, k.encode()); rd(0.6)
os.kill(pid, 9); os.waitpid(pid, 0)
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]|\x1b[=>]", "", out.decode("latin-1"))
res = dict(re.findall(r"RESULT locked=(\S+): (\d)/8 locked", text))
for k in ["true", "false", '"true"', '"false"', '"yes"', '"no"']:
    print(f"  locked = {k:8s} -> {res.get(k, '?')}/8 chests locked")
need = ["true", "false", '"true"', '"false"']
if not all(k in res for k in need):
    print("=== could not read the script's output"); sys.exit(2)
if res["true"] != "8" or res["false"] != "0":
    print("=== unexpected result for the Lua boolean forms"); sys.exit(2)
if res['"true"'] == "0" and res['"false"'] == "8":
    print('=== BUG: locked="true" makes unlocked chests and locked="false" locked ones')
    sys.exit(0)
if res['"true"'] == "8" and res['"false"'] == "0":
    print('=== OK: string booleans match the Lua booleans'); sys.exit(1)
print("=== inconclusive"); sys.exit(2)
PY
