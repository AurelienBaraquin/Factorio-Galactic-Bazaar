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
  (normal quality). They arrive by orbital capsule in the hub's import chests, with the freight fee,
  like a purchase from the market window.
- **Budget**: it spends at most the value of the **Credits** signal on its input per 10 s; without
  that signal, at most a tenth of your balance. An order that does not fit is skipped.
- A signal left on keeps buying every 10 s. The capsule queue (20 per hub) stops it when the
  import chests stay full.
- Negative values, fluids, qualities other than normal and items that cannot be traded are ignored.

### Example: keep 2 000 iron plates in stock

1. Wire the import chest (red) to a decider combinator: condition `Iron plate < 2000`, output
   `Iron plate = 200` (a constant 200).
2. Wire the decider's output (green) to the order combinator, and a constant combinator emitting
   `Credits = 500` to the same green wire. Keep the chest's red wire away from the order
   combinator: it would read the chest's contents as orders.

While the chest holds fewer than 2 000 plates, the order combinator buys 200 plates every 10 s,
spending at most 500 credits each time.
