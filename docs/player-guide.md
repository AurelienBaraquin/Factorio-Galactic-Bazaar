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

## Credits and overdraft

Your force may spend below zero: purchases, contract guarantees, lease deposits and charges, power
imports and orders all go through as long as they keep the balance above minus the **overdraft
limit**: 10 000 credits, raised to 25 000 by the **Overdraft 1** research and to 100 000 by
**Overdraft 2** (with a reputation of 0 or more; from −5 down, a level gives only half of what it
adds to 10 000). The market window shows the overdraft you have left next to the balance.
Each minute your balance went below zero, it pays **0.5 % interest** on the lowest it reached in
that minute (counted up to the limit, so at most 50 credits a minute at 10 000), even if that takes
it past the limit; past the limit, nothing more can be bought until sales bring the balance back,
and your force is **insolvent** (see below).

## Price signal combinators

Researched with **Market signals** (after Galactic Bazaar and Circuit network). Place one within
10 tiles of a powered trading hub of your force and wire it like any combinator; it cannot be
opened, since the mod writes its signals.

| Combinator | Emits |
|---|---|
| Buy price combinator | for every tradeable item and fluid, the price to **buy** one unit now |
| Sell price combinator | for every tradeable item and fluid, the price the market **pays** for one unit now |

Both also emit your force's balance on the **Credits** virtual signal, and 1 on the **Price feed**
virtual signal (always, even when the balance is 0).

### Units

Circuit signals are whole numbers, so:

- **Prices are in milli-credits**: a price of 1.32 credits reads **1320**; water at 0.001 credit
  reads 1. A price that would round to 0 is not emitted.
- **The balance is in whole credits**: 12 345.4 credits reads 12 345; it is negative while your
  force is on overdraft (see below).
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
  most your force spends through all its order combinators in 10 s (never more than your available
  funds: your balance plus what is left of your overdraft).
  Set it to 0 to pause buying. An order that does not fit in what is left is skipped.
- **Never wire a price combinator to it**: an input carrying the **Credits** or **Price feed** signal is refused,
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

## Loans

The **Contracts** window has a credit line: your debt, what your reputation allows, and one
**Borrow** button per amount (5 000, 20 000, 100 000 credits); hover one to see its rate and
installments, or why it is refused. Borrowing needs the **Credit** research (after Contracts); loans
you already have are repaid whether or not you have it.

- The amount is paid at once. You repay it with interest in **12 installments, one every 5 minutes**.
  The rate is fixed when you borrow: 10 % over the hour at reputation 0, down to 5 % at 20, up to
  15 % at −20.
- Your **debt** (what your loans still have to repay, plus arrears) may not exceed 50 000 credits at
  reputation 0, 150 000 at 20, 25 000 at −5 and below.
- Installments are paid from your available funds, overdraft included: one can take your balance
  below zero, which then pays the overdraft's interest. Your debt does not count the overdraft.
- **Repay** on a loan's row pays every installment left at once, interest included; it is refused if
  your available funds cannot cover it. A loan cannot be abandoned.
- If your available funds cannot cover an installment, the loan **defaults**: reputation −1, and that
  installment and every one left become **arrears**, taken at once from your available funds, down to
  your overdraft limit: your balance drops into the overdraft (and pays its interest), and what does
  not fit is taken from your income as it comes. No new loan until they are paid.
- No loan either while your balance is beyond the overdraft limit.
- Loans take rows of the Contracts window (8 at most, with your other contracts).

## Insolvency and bankruptcy

Your force is **insolvent** when its balance goes past the overdraft limit (interest can push it
there), or when it owes arrears it cannot pay. You are told so in the chat, and the market window
shows **Insolvent: bankruptcy in m:ss**.

- You have **10 minutes** to recover: bring your balance back until 5 % of your overdraft limit is
  left (**−9 500 credits** at the base limit; the message says the figure) and keep it there for a
  whole second, with no arrears left. A sale just
  before the check does not count if the balance was still too low earlier in that second.
- Meanwhile no contract is accepted and no loan is granted. You can still sell, from the window,
  export chests, export manifolds and power substations, and deliver to your contracts.
- Still insolvent after 10 minutes, your force goes **bankrupt**: every open contract ends (offers
  declined, active contracts failed, their guarantees kept), your debt is written off (a negative
  balance goes back to 0, arrears and the installments left on your loans are cancelled), your
  reputation falls to −20, and you get **no credit for 60 minutes**: no loan, and an overdraft limit
  of 0. Each new bankruptcy doubles that time, up to 8 hours. The market window shows **Bankrupt: no
  credit for m:ss**; you are told when credit returns.
- What was already paid still arrives: capsules in flight, shipments from planets in transit.

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

Researched with **Planetary concessions** (after Contracts), the **Planets** button of the market
window lists the planets of the galaxy: what each extracts or
crafts, how far it is, and how many of its slots are free for your force. Each force has its own
slots, and its transit terms: how much longer goods from it take to land, and the most of a
shipment that can be lost on the way (farther planets risk more). With Space Age, Vulcanus, Fulgora,
Gleba and Aquilo are listed too, with their own ores and their signature craft: metallurgy,
electromagnetics, organic, cryogenics; they only craft the recipes they could host themselves.

### Mining concessions

Open the Planets window from the market window of a hub with an import chest, and press **Lease**
next to an ore. For 30 minutes the planet ships you 150 units of it every 5 minutes, by transit, to
that hub's import chests. Each shipment is charged at the ore's base value — usually between what the
market pays and what it asks — and only when it is shipped; if your hub or its import chest is gone,
that period is skipped, free. Ore in flight when the hub is removed is sold back for you. One period's charge is held as a guarantee and
comes back at the end. If you cannot pay a charge, or abandon the lease in the Contracts window, the
guarantee is lost and your reputation drops by 1. Each planet has only a few slots per ore.

### Outsourced production

Researched with **Outsourcing** (after Planetary concessions and chemical science). On a crafting
row of the Planets window (smelting, assembly, chemistry…), pick one of your recipes and press
**Book**. For 30 minutes the planet buys the ingredients, crafts the recipe as one machine
of speed 1 would, and ships you the products every 5 minutes by transit, charged at 105 % of their base
value (the market price without the freight fee) — otherwise the terms of a mining concession. The
message printed when you book gives the amount, the charge and the guarantee. Only recipes you have unlocked, with a single sure product,
can be booked.
