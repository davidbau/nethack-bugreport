**Title:** Dwarves dig 2.6x to 5.3x faster than the code reads as intending

**Version:** `NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0),
checked 2026-09-18; identical in `NetHack-3.6`; unchanged since the 3.4.0-era
import of 2002-01-05. A balance question, not a crash.

### Symptom

The dwarf digging bonus compounds instead of doubling speed:

```
non-dwarf:  12, 24, 36, 48, 60, ...     (a typical increment is ~12)
dwarf:      24, 72, 168, 360, 744, ...
```

Over 200,000 simulated digs per case:

| dig | hero | non-dwarf | dwarf | advantage |
|---|---|---|---|---|
| down (effort > 250) | no bonuses, plain pick-axe | 21.4 turns | 4.0 turns | **5.3x** |
| down (effort > 250) | abon 2, +3 weapon | 15.2 turns | 3.8 turns | **4.0x** |
| sideways (effort > 100) | no bonuses, plain pick-axe | 8.9 turns | 3.0 turns | **3.0x** |
| sideways (effort > 100) | abon 2, +3 weapon | 6.3 turns | 2.4 turns | **2.6x** |

A 2x speed bonus would give the same ratio in every row. Here it depends on dig
length, and strength, enchantment and erosion barely matter for a dwarf.

### Cause

[`src/dig.c:365-368`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L365-L368):

```c
    svc.context.digging.effort +=
        10 + rn2(5) + abon() + uwep->spe - greatest_erosion(uwep) + u.udaminc;
    if (Race_if(PM_DWARF))
        svc.context.digging.effort *= 2;
```

`effort` is a running total, zeroed only when a dig starts or restarts
([`dig.c:412`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L412),
[`:423`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L423),
[`:1303`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L1303),
[`:1347`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L1347)),
so doubling it each turn compounds. Thresholds:
[`dig.c:372`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L372)
(down, `> 250`) and
[`dig.c:440`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L440)
(sideways, `> 100`). `holetime()`'s shopkeeper estimate `(250 - effort) / 20`
([`dig.c:595-602`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L595-L602))
also assumes linear progress.

Whether the snowball is intended is the DevTeam's call; it has shaped play
since 2002. If it is wanted, a comment would document it.

### Fix

Double the increment ([`proposed-fix.patch`](proposed-fix.patch); branch
[`bugreport/11-dwarf-dig-accumulator`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/11-dwarf-dig-accumulator),
[commit de5628951](https://github.com/davidbau/NetHack/commit/de56289519c8b4776fe14d194a58fb7d7c742e37),
[fixed code](https://github.com/davidbau/NetHack/blob/de56289519c8b4776fe14d194a58fb7d7c742e37/src/dig.c#L365-L376)):

```c
    {
        int inc = 10 + rn2(5) + abon() + uwep->spe
                  - greatest_erosion(uwep) + u.udaminc;

        if (Race_if(PM_DWARF))
            inc *= 2;
        svc.context.digging.effort += inc;
    }
```

### Repro

`bash bugs/11-dwarf-dig-accumulator/repro.sh` compiles [`repro.c`](repro.c),
which simulates the upstream and proposed formulas (no game build), then
checks your `src/dig.c`. Proposed-formula results:

```
  dig down  (effort > 250)      no bonuses, plain pick-axe      21.4      11.0    1.9x
  dig down  (effort > 250)      abon 2, +3 weapon               15.2       8.0    1.9x
  dig sideways (effort > 100)   no bonuses, plain pick-axe       8.9       4.8    1.9x
  dig sideways (effort > 100)   abon 2, +3 weapon                6.3       3.4    1.8x

Advantage across the four scenarios:
  upstream  2.6x to 5.3x   (spread 2.7)
  proposed  1.8x to 1.9x   (spread 0.1)
```

The ratio is under 2.0 because turn counts are whole numbers; the script tests
that it is the same in every scenario. It prints `AFFECTED` for the upstream
`dig.c` and `PATCHED` (exit 1) for the fixed one. There is no recorded session:
the patch changes dwarf dig timings by construction.
