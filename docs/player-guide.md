# Player guide: circuit network and market feed

What the Galactic Bazaar puts on the circuit network, and how to read it. In-game descriptions say
the same in short; this page gives the details and examples. Developer details are in
[terminal.md](terminal.md).

## Market feed

The prices listed in the market window and emitted by price combinators are read at most once per
period: 30 s without research, 10 s with **Galactic telecommunications 1**, 2 s with **level 2**,
which also shows the trend column and a price history line for the selected item. What you pay or
receive is always the live price, shown in the window's preview. With many price combinators,
the last ones get new prices a little later: about 0.1 s per combinator.

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

Prices are read once per period: **30 seconds** without research, **10 seconds** with Galactic
telecommunications 1, **2 seconds** with level 2; a combinator shows the last complete reading.
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
trading hub that has an import chest (for items) or an import manifold (for fluids), and wire
signals into it; it cannot be opened and emits
nothing.

- Every **10 seconds**, it buys, for each **item or fluid signal** with a positive value, that many
  units (items of normal quality). They arrive by orbital capsule about 30 s later, items in the
  hub's import chests and fluids in its import manifolds, with
  the freight fee, like a purchase from the market window.
- **Budget**: it buys **nothing** without a positive **Budget** signal on its input. The value is the
  most your force spends through all its order combinators in 10 s (never more than your balance).
  Set it to 0 to pause buying. An order that does not fit in what is left is skipped.
- **Never wire a price combinator to it**: an input carrying the **Credits** signal is refused,
  since its item signals are prices, not orders.
- A signal left on keeps buying every 10 s. The capsule queue (20 per hub) stops it when the import
  chests stay full; removing the hub sells the queued capsules back at the market price.
- Negative values, qualities other than normal and goods that cannot be traded are ignored.

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

## Incoming contracts

Researched with **Contracts** (after the Galactic Bazaar and logistic science). Every 5 minutes, up
to 3 at a time, a counterparty offers you to craft something you already know how to make. Open
them with the **Contracts** button of the market window.

- **Accept** at the hub you opened the window from: it needs an **import chest**, and enough
  credits for the **guarantee** (deposit plus penalty), which is held until the end. The
  ingredients arrive free by orbital capsule about 30 s later.
- Craft the products and put them in a **contract chest** within 10 tiles of a hub: every second,
  it hands over what your contracts still need, oldest first.
- **On time**: you get the reward and the whole guarantee back, and +1 reputation. **Late or
  abandoned**: the guarantee is lost, and −1 reputation. The guarantee is set at acceptance above
  what the ingredients sell for then, so keeping them does not pay.
- The reward is the value your crafting adds, so recipes that add little value pay little.
- **Reputation** (from −20 to 20, shown in the market window) lowers your freight fees, down to half
  at 20, and makes offers larger, up to three times at 20. Below zero, fees rise and offers shrink, down to half their size at −5.
- At most 8 contracts are open at a time, offers and active ones together.
- An offer not accepted within 5 minutes expires; **Decline** removes it at once.

## Machine rental

Researched with **Capacity rental** (after Contracts and Automation 2). Build **rental assemblers**
within 10 tiles of a trading hub and power them; you cannot open them. Every 5 minutes, each idle
one is offered for rent in the **Contracts** window (hover the counterparty to see the kind).

- **Accept**: the guarantee is held and the machine starts on the counterparty's recipe. Its
  ingredients arrive in it, a few crafts at a time; its products leave it as they come.
- The rental lasts **30 minutes** and promises 80 % of what the machine makes at full speed: keep it
  powered and running. Rent is paid **every 5 minutes** for what it made.
- **Do not put an output inserter next to it**: products it takes out never reach the
  counterparty, and the contract falls short.
- On time, you get the rest of the rent and the guarantee back, and +1 reputation. Short of the
  promise at the end, or if you remove the machine, the guarantee is lost (rent already paid stays).

## NPC planets

The **Planets** button of the market window lists the planets of the galaxy: what each extracts or
crafts, how far it is, and how many of its slots are free for your force. Each force has its own
slots, and its transit terms: how much longer goods from it take to land, and the most of a
shipment that can be lost on the way (farther planets risk more).

### Mining concessions

Open the Planets window from the market window of a hub with an import chest, and press **Lease**
next to an ore. For 30 minutes the planet ships you 150 units of it every 5 minutes, by transit, to
that hub's import chests. Each shipment is charged at the ore's base value — usually between what the
market pays and what it asks — and only when it is shipped; if your hub or its import chest is gone,
that period is skipped, free. Ore in flight when the hub is removed is sold back for you. One period's charge is held as a guarantee and
comes back at the end. If you cannot pay a charge, or abandon the lease in the Contracts window, the
guarantee is lost and your reputation drops by 1. Each planet has only a few slots per ore.

### Outsourced production

On a crafting row of the Planets window (smelting, assembly, chemistry…), pick one of your recipes
and press **Book**. For 30 minutes the planet buys the ingredients, crafts the recipe as one machine
of speed 1 would, and ships you the products every 5 minutes by transit, charged at 105 % of their base
value (the market price without the freight fee) — otherwise the terms of a mining concession. The
message printed when you book gives the amount, the charge and the guarantee. Only recipes you have unlocked, with a single sure product,
can be booked.
