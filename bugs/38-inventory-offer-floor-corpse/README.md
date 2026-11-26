# Offering a carried corpse through inventory can send its letter to the floor-corpse prompt

Stand on an altar with a corpse at your feet and another in your pack. Open
inventory, select the carried corpse, and choose **O — Offer this corpse as a
sacrifice at this altar**. The selection should be complete. With the carried
corpse in slot `l`, NetHack instead displays a request to report an error.
After acknowledging it, the player must choose the offering again.

[Watch the error at step 40](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/38-inventory-offer-floor-corpse/session.json#step=40) ·
[Watch the same keys with the patch](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/38-inventory-offer-floor-corpse/session-fixed.json#step=40)

## Reproduce

Run `bash bugs/38-inventory-offer-floor-corpse/repro.sh` after the repository's
recorder setup. For a manual test, start a wizard-mode priest, wish for an
altar, a newt corpse, and a jackal corpse. Drop the newt corpse on the altar.
In the recording the remaining jackal corpse is inventory letter `l`.
Type `i`, select the jackal corpse, then press uppercase `O`.

The recording shows the jackal selected at step 39, the DevTeam message at
step 40, and “What do you want to sacrifice? [l or ?*]” after Space at
step 41. Escape cancels the offer. With the patch, step 40 instead reads
“Your sacrifice is consumed in a burst of flame!”

## Cause and proposed fix

The inventory action queues `dosacrifice` followed by the selected inventory
letter. The command calls `floorfood("sacrifice", 1)`, which first asks about
the newt on the altar. That yes/no/quit question consumes the queued `l`.
The invalid-answer handler reports the error and substitutes the default
`n`. By the time inventory selection begins, the queued letter is gone.

The proposed patch queues the existing `m` prefix (`do_reqmenu`) immediately
before the sacrifice command. For an offer this prefix skips floor items.
The inventory **Eat** action already uses the same mechanism. Players issuing
an ordinary `#offer` can still select a corpse on the altar.

[Upstream inventory actions](https://github.com/NetHack/NetHack/blob/968eedd06392f431dce5b0f3e1a5d3348d04261b/src/iactions.c#L175-L204) ·
[Upstream floor selection](https://github.com/NetHack/NetHack/blob/968eedd06392f431dce5b0f3e1a5d3348d04261b/src/eat.c) ·
[Proposed patch](proposed-fix.patch)

## Upstream status

The DevTeam added the invalid-answer diagnostic in 2024 while investigating
canned responses. A search of the public NetHack issues, pull requests and
5.0.0 bug lists on 2026-11-26 found no report specific to this inventory
sacrifice. The action on the NetHack-5.0 tip `968eedd06` still queues the
letter without the prefix. Both recordings here were made with this
repository's C recorder, the second with the proposed patch applied.

[Upstream diagnostic commit](https://github.com/NetHack/NetHack/commit/49a669a863b5d1f2eca0f7bc628d7436a997de33)
