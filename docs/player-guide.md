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

Prices and balance are taken once every **10 seconds** per force; a combinator shows the last
complete reading. Without a powered hub in range, it emits nothing.

### Example: sell iron plates only when they fetch a good price

1. Place a sell price combinator next to your hub and wire it (red) to a decider combinator.
2. Decider condition: `Iron plate > 1500` (1.5 credits), output: `signal-check = 1`.
3. Wire the decider's output to an inserter that feeds an export chest, with the enable condition
   `signal-check = 1`.

The inserter then only loads the export chest while plates sell for more than 1.5 credits.
