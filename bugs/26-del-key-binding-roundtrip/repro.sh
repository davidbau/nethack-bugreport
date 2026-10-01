#!/bin/bash
# repro.sh -- bug 26: a BIND line for the Delete key, in the form
# #saveoptions writes it (key2txt(): "<del>"), is rejected when the config
# file is read back (txt2key() does not know "<del>").
#
# Starts the recorder binary with a config file containing
#     BIND=<del>:pray
# and looks for the config error on the opening screen.
#
# Exit 0 = bug confirmed, 1 = not reproduced (probably fixed).
set -e
cd "$(dirname "$0")/../.."
NH=nethack-c/recorder/install/games/lib/nethackdir/nethack
[ -x "$NH" ] || { echo "build the recorder first: bash setup.sh"; exit 2; }
python3 - "$NH" <<'PY'
import os, pty, re, select, sys, tempfile, time
nh = os.path.abspath(sys.argv[1])
home = tempfile.mkdtemp(prefix='bugrep26_')
open(os.path.join(home, '.nethackrc'), 'w').write(
    'OPTIONS=name:rc,role:valkyrie,race:human,gender:female,align:neutral\n'
    'OPTIONS=!tutorial,!legacy,!splash_screen\n'
    'BIND=<del>:pray\n')
env = dict(os.environ, HOME=home, NETHACKDIR=os.path.dirname(nh), HACKDIR=os.path.dirname(nh)); env.pop('NETHACKOPTIONS', None)
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.path.dirname(nh)); os.execve(nh, ['nethack'], env)
out, end = b'', time.time() + 5
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try: out += os.read(fd, 65536)
        except OSError: break
os.kill(pid, 9)
text = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07', ' ', out.decode('latin-1'))
m = re.search(r"Unknown key binding key '<del>'", text)
print('config error:', m.group(0) if m else '(none)')
sys.exit(0 if m else 1)
PY
