# Player guide: circuit network

What the Galactic Bazaar puts on the circuit network, and how to read it. In-game descriptions say
the same in short; this page gives the details and examples. Developer details are in
[terminal.md](terminal.md).

## Price signal combinators

Researched with **Market signals** (after Galactic Bazaar and Circuit network). Place one within
10 tiles of a powered trading hub of your force and wire it like any combinator; it cannot be
opened, since the mod writes its signals.

| Combinator | Emits |
|---|---|
| Buy price combinator | for every tradeable item and fluid, the price to **buy** one unit now |
| Sell price combinator | for every tradeable item and fluid, the price the market **pays** for one unit now |

Both also emit your force's balance on the **Credits** virtual signal.

### Units

Circuit signals are whole numbers, so:

- **Prices are in milli-credits**: a price of 1.32 credits reads **1320**; water at 0.001 credit
  reads 1. A price that would round to 0 is not emitted.
- **The balance is in whole credits**: 12 345.4 credits reads 12 345.
- Values past 2 147 483 647 (or below −2 147 483 648) are capped there.
- Prices are for **normal quality**; electricity has no signal.

### Freshness

Prices are read once every **10 seconds** per force; a combinator shows the last complete reading.
After a reading in which prices changed, combinators are rewritten one after another, about ten a
second, so with many combinators the last ones lag a few seconds more. The balance is updated at
every visit, within a few seconds. Without a powered hub in range, a combinator emits nothing.

### Example: sell iron plates only when they fetch a good price

1. Place a sell price combinator next to your hub and wire it (red) to a decider combinator.
2. Decider condition: `Iron plate > 1500` (1.5 credits), output: the check mark signal (✓), set to 1.
3. Wire the decider's output to an inserter that feeds an export chest, with the enable condition
   `✓ = 1`.

The inserter then only loads the export chest while plates sell for more than 1.5 credits.

## Order combinator

Researched with **Market orders** (after Market signals). Place it within 10 tiles of a powered
trading hub that has an import chest, and wire signals into it; it cannot be opened and emits
nothing.

- Every **10 seconds**, it buys, for each **item signal** with a positive value, that many units
  (normal quality). They arrive by orbital capsule in the hub's import chests about 30 s later, with
  the freight fee, like a purchase from the market window.
- **Budget**: it buys **nothing** without a positive **Budget** signal on its input. The value is the
  most your force spends through all its order combinators in 10 s (never more than your balance).
  Set it to 0 to pause buying. An order that does not fit in what is left is skipped.
- **Never wire a price combinator to it**: an input carrying the **Credits** signal is refused,
  since its item signals are prices, not orders.
- A signal left on keeps buying every 10 s. The capsule queue (20 per hub) stops it when the import
  chests stay full; removing the hub sells the queued capsules back at the market price.
- Negative values, fluids, qualities other than normal and items that cannot be traded are ignored.

### Example: keep about 2 000 iron plates in stock

1. Place a constant combinator emitting `Iron plate = 200` and `Budget = 500`.
2. Place a decider combinator. Wire the import chest to its input with **red**, and the constant
   combinator to its input with **green**. Condition: `Iron plate` on the **red** wire `< 2000`.
   Outputs: `Iron plate`, *input count*, read from the **green** wire only; and `Budget`, *input
   count*, green only.
3. Wire the decider's output to the order combinator. Keep the chest's wire away from the order
   combinator: it would read the chest's contents as orders.

While the chest holds fewer than 2 000 plates, the order combinator buys 200 plates every 10 s,
spending at most 500 credits each time. Plates in flight are not counted, so the stock overshoots
by up to about 600 plates (three orders land within 30 s); lower the threshold if that matters.
