# Dwarves dig 2.6x to 5.3x faster than the code reads as intending

`dig_effort()` adds this turn's digging progress to a running total and then
doubles it for dwarves. The doubling lands on the running total rather than on
the increment that was just added, so a dwarf's progress grows geometrically
instead of twice as fast:

```
non-dwarf:  12, 24, 36, 48, 60, ...     (a typical increment is ~12)
dwarf:      24, 72, 168, 360, 744, ...
```

Digging down completes above 250 effort and sideways above 100. A dwarf
therefore breaks through the floor in four turns where a non-dwarf takes about
twenty-one, and the advantage is not the 2x the two-line bonus reads as.

The tell is that the advantage is not even constant. Over 200,000 simulated
digs per case:

| dig | hero | non-dwarf | dwarf | advantage |
|---|---|---|---|---|
| down (effort > 250) | no bonuses, plain pick-axe | 21.4 turns | 4.0 turns | **5.3x** |
| down (effort > 250) | abon 2, +3 weapon | 15.2 turns | 3.8 turns | **4.0x** |
| sideways (effort > 100) | no bonuses, plain pick-axe | 8.9 turns | 3.0 turns | **3.0x** |
| sideways (effort > 100) | abon 2, +3 weapon | 6.3 turns | 2.4 turns | **2.6x** |

A bonus that doubled digging speed would show the same ratio in all four rows.
Doubling the accumulator instead makes the advantage depend on how many turns
the dig takes, so a weak dwarf with a plain pick-axe gains more from being a
dwarf than a strong one with an enchanted mattock does. After a few turns the
increment stops mattering at all: once the total is being doubled every turn,
strength, enchantment and erosion barely move the finish line.

The affected code is `dig_effort()` in `src/dig.c`. It is present at the
`NetHack-5.0` tip
[`c63ee6ac7`](https://github.com/NetHack/NetHack/tree/c63ee6ac7ef78639db31660c52aaa2e60cb6afd0),
checked 2026-09-18, identical in the `NetHack-3.6` line, and unchanged since
the 3.4.0-era import of 2002-01-05. The branch
[`bugreport/11-dwarf-dig-accumulator`](https://github.com/davidbau/NetHack/compare/16ff59115315917b93185d026aeefea06db9b0f4...bugreport/11-dwarf-dig-accumulator)
holds one proposed commit.

Severity: low, and it is a balance question rather than a crash or a
corruption. See "Is this even a bug?" below, which is a fair thing to ask
about a line that has behaved this way for twenty-four years.

## Reproducing it

No game build, no headers, no recorded session: the behaviour follows from the
formula, so [`repro.c`](repro.c) contains both the upstream formula and the
proposed one and simulates them side by side.

```
bash bugs/11-dwarf-dig-accumulator/repro.sh
```

That compiles and runs the simulation, and then looks at your `src/dig.c` and
reports whether it still has the upstream form. Output on an unpatched tree:

```
UPSTREAM  (effort *= 2 -- the running total)
  dig                           hero                        non-dwarf     dwarf   ratio
  dig down  (effort > 250)      no bonuses, plain pick-axe      21.4       4.0    5.3x
  dig down  (effort > 250)      abon 2, +3 weapon               15.2       3.8    4.0x
  dig sideways (effort > 100)   no bonuses, plain pick-axe       8.9       3.0    3.0x
  dig sideways (effort > 100)   abon 2, +3 weapon                6.3       2.4    2.6x

PROPOSED  (inc *= 2 -- the per-turn increment)
  dig                           hero                        non-dwarf     dwarf   ratio
  dig down  (effort > 250)      no bonuses, plain pick-axe      21.4      11.0    1.9x
  dig down  (effort > 250)      abon 2, +3 weapon               15.2       8.0    1.9x
  dig sideways (effort > 100)   no bonuses, plain pick-axe       8.9       4.8    1.9x
  dig sideways (effort > 100)   abon 2, +3 weapon                6.3       3.4    1.8x

Advantage across the four scenarios:
  upstream  2.6x to 5.3x   (spread 2.7)
  proposed  1.8x to 1.9x   (spread 0.1)
```

The proposed form lands near 1.9x rather than exactly 2.0x because turn counts
are whole numbers; a dig that needs 11.0 turns at double speed needed 21.4, not
22.0. So "is it exactly 2.0" is the wrong test, and the script tests whether
the advantage is the *same* in every scenario instead.

To see it in a real game rather than a simulation: wield a pick-axe as a dwarf
and as a non-dwarf with matching stats and count the turns to break through a
floor, or instrument `svc.context.digging.effort` once per tick.

## What the code is doing

```c
    svc.context.digging.effort +=
        10 + rn2(5) + abon() + uwep->spe - greatest_erosion(uwep) + u.udaminc;
    if (Race_if(PM_DWARF))
        svc.context.digging.effort *= 2;
```

Source: [`src/dig.c:365-368`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L365-L368).

`svc.context.digging.effort` is the accumulator. It is zeroed when a dig starts
or is restarted somewhere else
([`dig.c:412`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L412),
[`:423`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L423),
[`:1303`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L1303),
[`:1347`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L1347))
and otherwise carries from turn to turn, which is exactly what makes the
doubling compound. `dig()` is an occupation, so the two lines above run once
per turn of digging.

The thresholds it is measured against are
[`dig.c:372`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L372)
for down (`> 250`) and
[`dig.c:440`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L440)
for sideways (`> 100`).

One consequence worth stating separately: `holetime()`, the "very rough
indication used by shopkeeper" of when a hole will be finished, is
`(250 - effort) / 20`
([`dig.c:595-602`](https://github.com/NetHack/NetHack/blob/16ff59115315917b93185d026aeefea06db9b0f4/src/dig.c#L595-L602)).
It assumes progress accumulates linearly, so for a dwarf it is off by a
growing amount as the dig proceeds.

## Is this even a bug?

A fair question, and the honest answer is that the *effect* is not in doubt but
the *intent* is a decision for the DevTeam.

Reasons to think the current form is not what was meant:

- The advantage drifts between 2.6x and 5.3x depending on the hero's other
  bonuses. Nothing else in the game grants a racial advantage shaped like
  that, and there is no comment suggesting a deliberate snowball.
- It makes the hero's strength, weapon enchantment and weapon erosion nearly
  irrelevant for dwarves, which inverts the usual relationship between gear
  and speed.
- Both the immediately surrounding code and the estimate at `dig.c:601` treat
  effort as accumulating linearly.

Reasons for caution:

- It has behaved this way since the 3.4.0-era import in 2002 and is identical
  in 3.6, so a quarter of a century of play has been balanced around it,
  whether deliberately or not.
- Dwarves being dramatically good at digging is thematically defensible, and
  four turns to dig down is a real gameplay affordance that players may be
  relying on.

So this is filed as "here is what the code does, here is what it reads as
intending, and the two differ by a factor that is not constant". If the
snowball is wanted, the fix is a comment rather than a patch.

## Proposed fix

[`proposed-fix.patch`](proposed-fix.patch): double the increment.

```c
    {
        int inc = 10 + rn2(5) + abon() + uwep->spe
                  - greatest_erosion(uwep) + u.udaminc;

        /* the dwarven bonus doubles this turn's progress; applying it to
           svc.context.digging.effort instead would double the running
           total every turn, making the advantage grow with the length of
           the dig rather than staying at 2x */
        if (Race_if(PM_DWARF))
            inc *= 2;
        svc.context.digging.effort += inc;
    }
```

Fixed code:
[`dig.c:365-376`](https://github.com/davidbau/NetHack/blob/de56289519c8b4776fe14d194a58fb7d7c742e37/src/dig.c#L365-L376)
· diff:
[commit de5628951](https://github.com/davidbau/NetHack/commit/de56289519c8b4776fe14d194a58fb7d7c742e37).

The increment is lifted into a named local so the bonus has something to apply
to, and the comment records why it must not go back on the accumulator. Nothing
else changes: the same expression, the same `Race_if` test, the same
accumulator, the same thresholds.

A maintainer who wants to keep the current timings but make the intent explicit
could instead leave the arithmetic alone and comment it, which is why this
bundle leads with the measurement rather than the patch.

## Not verified by rebuild

Unlike the session-replay bundles here, this one has no before-and-after
recording. The change alters dwarf dig timings by construction, so a recorded
session would diverge from the first dig onward and the diff would be the
timings themselves rather than a defect appearing or disappearing. The
simulation in `repro.c` is the evidence, and it is exact rather than sampled in
the sense that matters: it runs the real formula, not an approximation of it.

## Credit

Found and analysed by AI agents collaborating on a JavaScript port of NetHack
5.0, under human direction, with the analysis, simulation and patch from Claude
Opus 5. The port reproduces the upstream form verbatim, because the porting
rule is to match the implementation including its defects, so this is filed
rather than fixed locally.
