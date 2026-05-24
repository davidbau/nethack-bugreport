# nethack-c/

The C side of the contest. Three things live here:

```
nethack-c/
├── upstream/        ← submodule: github.com/NetHack/NetHack @ NetHack-5.0.0_Release
├── patches/         ← 6 patches: pinned datetime+seed, RNG logging, deterministic capture
├── build-recorder.sh   ← clones submodule, applies patches, builds the recorder binary
└── recorder/        ← (gitignored) built source tree
    recorder-install/   ← (gitignored) installed binary + data
```

## You don't need to build this

To enter the contest, you don't need any C compiler at all. You're
porting NetHack 5.0 to JavaScript — the upstream submodule is the
**reference C source you're porting from**, and you read it with your
eyes, not with a compiler.

## When you would build this

You only need the recorder build if you want to:

- **Record your own debugging session.** Pin a seed + datetime, play
  any keyplan you want, get back a `.session.json` your JS port can
  be diff'd against.
- **Audit the public sessions.** Verify they really came from
  unmodified upstream + these specific patches and nothing else.
- **Cross-check live.** Run a session in C and JS side-by-side to
  see where their RNG sequences diverge.

## Build

```bash
git submodule update --init nethack-c/upstream
bash nethack-c/build-recorder.sh
```

Requires: `clang` (not gcc — see below), `make`, `bison`, `flex`.

## Why clang specifically

C's argument-evaluation order is officially undefined. In practice,
gcc evaluates right-to-left and clang evaluates left-to-right. A
single line like `d(rn2(5), rn2(3))` consumes RNG calls in opposite
orders depending on the compiler — completely scrambling the PRNG
sequence. We pin to clang so the recorder's behavior is reproducible
across machines, and the JS port (which evaluates left-to-right) can
match it.

## What the patches do

See `patches/README.md` for a per-patch table. The short version:

- **Determinism**: pin date/time, pin seed, replace `qsort` with
  a stable sort.
- **Observability**: log every PRNG call (three contexts: core, Lua,
  display) and capture the 24×80 terminal at every input boundary.

That's the entire delta from upstream NetHack 5.0. No internal
debugging machinery, no porting hints.

## Recording your own sessions

Once built, the recorder is just a NetHack binary that reads a few
env vars and writes a few files.

| Env var | What it does |
|---|---|
| `NETHACK_SEED=<int>` | Pin the core PRNG seed |
| `NETHACK_FIXED_DATETIME=YYYYMMDDHHMMSS` | Pin the wall clock (moon phase, hire date, shopkeeper line all derive from this) |
| `NETHACK_RNGLOG=<path>` | Write every core PRNG call as one line (`rn2(N)=M @ <caller>(file:line)`) |
| `NETHACK_RNGLOG_DISP=<path>` | Same, for the display/hallucination PRNG context |
| `HACKDIR=<dir>` | NetHack data files location (use the install dir) |

The patched tty driver writes 24×80 ANSI frames to stdout at every
input boundary; pipe stdout to a file to capture the visual stream.

Stitching these into the same `.session.json` format the judge
consumes is left as an exercise — the format is documented in
`docs/API.md`. Most contestants don't need to: they play the public
sessions in `sessions/` and watch where their JS port diverges
from the recorded screens.
