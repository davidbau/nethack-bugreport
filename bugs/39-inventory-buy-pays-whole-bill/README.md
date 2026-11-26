# Buying one inventory item can pay the whole shop bill

A shop has billed the hero for a scroll of gold detection (100 zorkmids) and a piece of glass (5). The hero has 5007 gold. Select the glass from inventory, then choose **Buy this unpaid item**. The expected balance is 5002, with the scroll still unpaid.

| Menu style | Observed result |
|---|---|
| Traditional | The first purchase message names the scroll. The second names the glass. The hero has 4902 gold. |
| Default | A new bill menu opens with neither item selected. Escape leaves both unpaid and the hero has 5007 gold. |
| Either, with the proposed patch | The glass alone is purchased. The hero has 5002 gold and the scroll remains unpaid. |

[Traditional replay](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/39-inventory-buy-pays-whole-bill/session.json#step=148) · [Default replay](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/39-inventory-buy-pays-whole-bill/session-menu.json#step=148) · [Patched replay](https://davidbau.github.io/nethack-bugreport/tools/session-viewer/?session=bugs/39-inventory-buy-pays-whole-bill/session-fixed.json#step=148)

## Why the slot letter matters

The recordings use the two-item Minetown bill from [report 25](../25-gem-learned-bill-skip/) and adjust the glass to slot `n`. The inventory action queues ordinary `dopay` followed by that letter. In traditional mode the next prompt is “Itemized billing?” Answering no means “pay everything.” In default mode the billing menu assigns its own accelerators. The glass in inventory slot `n` is bill entry `b`.

[Inventory action](https://github.com/NetHack/NetHack/blob/968eedd06392f431dce5b0f3e1a5d3348d04261b/src/iactions.c#L203-L206) · [Billing code](https://github.com/NetHack/NetHack/blob/968eedd06392f431dce5b0f3e1a5d3348d04261b/src/shk.c#L2074-L2150)

## Proposed C fix

Dispatch an internal inventory-buy command. It consumes the slot immediately with `getobj` and passes the selected object to the existing payment code. The current shop must own the bill for that object. The payment loop selects matching itemized bill entries by object identity and uses the existing pricing, credit, container and bill-update logic. The proposal leaves a separate shop debit for the player to settle explicitly with ordinary pay.

The [patch](proposed-fix.patch) applies to upstream revision `968eedd06`. Run `bash repro.sh` from this directory to verify the original behavior. With a patched recorder, run `NETHACK_BINARY=/path/to/nethack bash repro.sh fixed`. Both checks inspect the final inventory. Separate ordinary-pay controls produced identical screens before and after in both menu styles. Partly used stacks, unpaid containers, shop credit and multiple shopkeepers merit further testing before upstream adoption.

[Report 38](../38-inventory-offer-floor-corpse/) shows the same ambiguity with a floor offering. Its one-line remedy uses the offer command's inventory prefix. For payment, that prefix only inverts the menu style.
