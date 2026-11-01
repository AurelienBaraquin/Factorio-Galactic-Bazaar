# Player guide: circuit network and market feed

What the Galactic Bazaar puts on the circuit network, and how to read it. In-game descriptions say
the same in short; this page gives the details and examples. Developer details are in
[terminal.md](terminal.md).

## The Galactic Bazaar window

Once **Galactic Bazaar** is researched, a button with the trading hub's icon appears at the top
left of the screen. It, or **Ctrl + Shift + G** (change it in the game's control settings), opens
or closes the Galactic Bazaar window anywhere; clicking a trading hub opens it on the Market tab.
Its tabs:

- **Overview**: your balance; the overdraft used, its limit and what is left; the interest rate
  and about how much the next interest charge takes and when; your reputation and what it changes
  (freight fees, contract sizes, loan rate and the most you may owe on loans); whether you are
  solvent, insolvent (and what to do) or barred from credit after a bankruptcy (and the debt left);
  and how many offers, contracts, leases and loans you have open, with the next deadline. Hover a
  line to see what it means.
- **Market**: prices, buying and selling (below). Select an item to see, beside the list, what
  buying or selling the quantity you type would cost or bring, the average price and the next price
  after such an order, and why its prices are what they are: its base value and how far the market
  is from it (the shortage or surplus other trades left), what market events add to it now, how much the market can still take each
  way, the spread, how the other traders move it each minute and how fast it returns to balance
  (hover a line for its rule); its price history once **Galactic telecommunications 2** is
  researched; and why it is worth its base value: the recipe (or mining, pumping...) that makes it
  cheapest, each ingredient and its value, the time it takes, a value set by another mod, and what
  each higher quality is worth.
- **Events**: the market's shortages, surpluses and crises, forecast, active or fading, with their
  goods, when they start or how long they may still last, how far they could move the price and how much they move it now ([below](#market-events)).
- **Logistics**: every trading hub of your force, with its power, its status and how full each
  delivery tier's queue is. Select one to see it on a camera, the tier it delivers by (hover it for
  the delay, launch interval, capacity, fee and queue limit), the shipments bought, sent by a
  contract or shipped from a planet that are waiting for their launch, in flight or landed — what
  they carry, when they land, where they come from, what you paid per unit and, from a planet, the
  share lost on the way — and the buildings attached to it with their status. Hover a shipment's
  state to see why it waits (no room in the import chests, a teleporter without power); click a
  building's icon to show it on the camera.
- **Contracts**: offers, contracts under way and your loans.
- **Planets**: once **Planetary concessions** is researched, the NPC planets and their slots.
- **Statement**: where your credits came from and went to. The journal lists your force's
  transactions, newest first, a page at a time: when (game time), what (hover it for the rule
  behind it: fee rates, interest, what a contract's outcome gives back), the goods or contract, the
  quantity, the amount (green received, red paid) and your balance after it. Pick a category to see
  only its transactions. Above it, the income, spending and net of each category (sales, purchases,
  freight, power, contracts, loans, interest, bankruptcy) over the last 10 minutes, the last hour or
  since records began; they count every transaction, even those the journal merged (automatic
  sales and power settle into one entry per minute) or no longer keeps (its newest 500 entries).

Every tab can be read anywhere, even from remote view, but buying, selling, accepting, declining or
abandoning a contract, borrowing, repaying and leasing need a trading hub of your force **within
reach of your character**, never from remote view: the window uses the hub you clicked, or else the
nearest one within reach, and the Market tab says when there is none. If a purchase's preview was
shown for another hub, or without a hub, the purchase is refused once and the preview updated (when
no delivery can take the quantity, the preview says why: a full queue, for instance), so
that you always see the freight fee before paying.

## In-game help

Hover a figure, column header or button of the window: its tooltip says what it is and the rule
behind it, with your own figures where they matter (your fee factor, the delivery tier's terms, a
planet's transit, a contract's guarantee...). The game's **Tips and tricks** window has a
**Galactic Bazaar** section, suggested once Galactic Bazaar is researched: one entry for the
window, the trading hub and its buildings, prices, deliveries, credits and the overdraft,
insolvency and bankruptcy, research and price freshness, alerts and statuses, and then, as you
research them, power trading, the circuit network, crafting contracts, reputation, machine rental,
storage rental, NPC planets, outsourced production and loans; with quality, how qualities are valued; with Space
Age, what changes with it. The descriptions of the mod's buildings and researches give their
figures (range, power, throughput, fees).

## Building status

Every building of the mod carries a status, next to a coloured light: green when it works,
yellow when it waits or is held back, red when it is stopped. The game shows it where it shows an
entity's status (where exactly, for each kind of building, is still to be checked on screen). A
building that is stopped shows an icon on it: a warning sign when no trading hub of your force is
within 10 tiles, a lightning bolt when its hub, or the building itself, has no power; hold Alt to
read why under the icon. What each building says (sales held below their price floor, shipments on
the way, an order combinator's last reading and budget left, a catapult's charge, what a contract
chest still waits for...) is listed in [terminal.md](terminal.md#building-status); a rented machine
keeps the game's own status, and its contract's progress is in the Contracts tab. Statuses
refresh about every 5 seconds (longer with more than 240 buildings of the mod).

## Market feed

The prices listed in the Market tab and emitted by price combinators are read at most once per
period: 30 s without research, 10 s with **Galactic telecommunications 1**, 2 s with **level 2**,
which also shows the trend column and the price history of the selected item. What you pay or
receive is always the live price, shown in the window's preview. With many price combinators,
the last ones get new prices a little later: about 0.1 s per combinator.

## One good saturates its market

Every unit you sell lowers that good's price, and the price recovers by half every 10 minutes.
Export chests sell a good only while it fetches at least half its base value, so one good earns at
most about **26 700 credits an hour**, however much of it you make and whatever it is worth. To earn
more, sell more kinds of goods ([balance.md](balance.md)).

## Credits and overdraft

Your force may spend below zero: purchases, contract guarantees, lease deposits and charges, power
imports and orders all go through as long as they keep the balance above minus the **overdraft
limit**: 10 000 credits, raised to 25 000 by the **Overdraft 1** research and to 100 000 by
**Overdraft 2** (with a reputation of 0 or more; from −5 down, a level gives only half of what it
adds to 10 000). The Market tab shows the overdraft you have left next to the balance.
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
  the freight fee, like a purchase from the Market tab.
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
them in the **Contracts** tab.

- **Accept** within reach of a hub: it needs an **import chest**, and enough
  credits for the **guarantee** (deposit plus penalty), which is held until the end. The
  ingredients arrive free by orbital capsule about 30 s later.
- Craft the products and put them in a **contract chest** within 10 tiles of a hub: every second,
  it hands over what your contracts still need, oldest first.
- **On time**: you get the reward and the whole guarantee back, and +1 reputation. **Late or
  abandoned**: the guarantee is lost, and −1 reputation. The guarantee is set at acceptance above
  what the ingredients sell for then, so keeping them does not pay.
- Crafting contracts are how you build **reputation**; their reward is modest: the value your
  crafting adds plus a small margin (about 4 to 5 % of the products for most recipes), at most 1
  credit per second of recipe time at speed 1 — less than buying the products and selling the
  ingredients would lose.
- While a market event makes goods short, half of the offers ask for a recipe that makes them.
- **Reputation** (from −20 to 20, shown in the Market tab) lowers your freight fees, down to half
  at 20, and makes offers larger, up to three times at 20. Below zero, fees rise and offers shrink, down to half their size at −5.
- At most 8 contracts are open at a time, offers and active ones together.
- An offer not accepted within 5 minutes expires; **Decline** removes it at once.

## Loans

The **Contracts** tab has a credit line: your debt, what your reputation allows, and one
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
- Loans take rows of the Contracts tab (8 at most, with your other contracts).

## Insolvency and bankruptcy

Your force is **insolvent** when its balance goes past the overdraft limit (interest can push it
there), or when it owes arrears it cannot pay. You are told so by an alert and in the chat, the Market tab
shows **Insolvent: bankruptcy in m:ss**, and the Overview says what balance to keep.

- You have **10 minutes** to recover: bring your balance back until 5 % of your overdraft limit is
  left (**−9 500 credits** at the base limit; the message says the figure) and keep it there for a
  **whole minute**, with no arrears left. A sale just before a check does not count if the balance
  was still too low earlier in that second, and a dip under that figure restarts the minute.
- Meanwhile no contract is accepted and no loan is granted. You can still sell, from the window,
  export chests, export manifolds and power substations, and deliver to your contracts.
- Still insolvent after 10 minutes, your force goes **bankrupt**. Nothing you owe is cancelled:
  - every open contract ends (offers declined, active contracts failed, their guarantees kept);
  - everything you owe — a negative balance, arrears, the installments left on your loans — plus a
    **25 % restructuring surcharge** becomes one **bankruptcy debt**, frozen: it earns no interest.
    Your balance is set to 0, and every credit you receive (sales, exports, rewards) goes to the debt
    first, so you cannot spend income before it is repaid;
  - your reputation falls to −20;
  - you get **no credit**: no loan and an overdraft limit of 0, for **60 minutes and until the debt is
    repaid**. Each new bankruptcy doubles that time, up to 8 hours. When credit returns, a researched
    overdraft gives only half its extra at reputation −20, until your reputation recovers.
- The Market tab shows **Bankrupt: no credit for m:ss, X of debt to repay**, then **no credit
  until X of debt is repaid** once the time has passed; you are told when credit returns.
- Going bankrupt on purpose rarely pays: the surcharge costs more than the overdraft's interest
  unless your debt would take you more than about 100 minutes of income to repay, and you still
  lose every contract, your reputation and your credit.
- What was already paid still arrives: capsules in flight, shipments from planets in transit.

## Machine rental

Researched with **Capacity rental** (after Contracts and Automation 2). Build **rental assemblers**
within 10 tiles of a trading hub and power them; you cannot open them. Every 5 minutes, each idle
one is offered for rent in the **Contracts** tab (hover the counterparty to see the kind).

- **Accept**: the guarantee is held and the machine starts on the counterparty's recipe. Its
  ingredients arrive in it, a few crafts at a time; its products leave it as they come.
- The rental lasts **30 minutes** and promises 80 % of what the machine makes at full speed: keep it
  powered and running. Rent is paid **every 5 minutes** for what it made: 0.5 credits per second of
  crafting promised, about 540 credits for the 30 minutes, whatever the recipe.
- **Do not put an output inserter next to it**: products it takes out never reach the
  counterparty, and the contract falls short.
- On time, you get the rest of the rent and the guarantee back. Rentals are a modest income and earn
  no reputation. Short of the
  promise at the end, or if you remove the machine, the guarantee is lost (rent already paid stays).

## Storage rental

Researched with **Storage rental** (after Contracts). It works both ways ([ADR-0024](adr/0024-storage-rental.md)).

**Rent a vault from a NPC.** In the **Contracts** tab, near a trading hub with an import chest,
press **Rent a vault**: 50 stacks for 30 minutes, 150 credits every 5 minutes whatever it holds, one
period held as a guarantee.

- Put goods in a **vault uplink** within 10 tiles of that hub: about once a second (more rarely
  with more than 20 uplinks) they go into the vault, until its stacks are full. Uplinks are visited
  two at a time, and each visit moves at most 10 stacks for the two together (a stack split between
  two vaults counts twice). Only items of normal quality that are not spoilable, damaged, used or carrying
  data go; the rest stays in the uplink, whose status says so.
- **Retrieve** on the vault's row ships its goods to that hub's import chests by orbital capsule,
  free: one capsule of up to 10 stacks of one item leaves every 10 seconds and lands 30 seconds
  later, so 50 stacks of one item take about 70 seconds. The hub queues at most 20 capsules: what
  does not fit stays in the vault (you are told how many stacks) for a later Retrieve. Retrieve
  only delivers to the vault's own hub while it is rented.
- The vault is charged every 5 minutes whatever happens to its hub: it keeps your goods either way.
  If its hub is removed, the vault takes over a hub of yours built within 10 tiles of where it
  stood; otherwise it can neither be filled nor retrieved until its term ends, when its goods come
  back. Goods on their way back when their hub is removed return to the vault.
- When the vault ends — its term, a charge you cannot pay, Abandon or a bankruptcy — its goods are
  shipped back the same way, a queue's worth each second: they are never seized. The Overview's
  **Vault goods returning** line shows what is still waiting. A charge you cannot pay, or Abandon,
  fails it: the guarantee is kept and your reputation drops by 1. If its hub has no import chest,
  another of your hubs on the same surface with one receives them (any surface, only if that
  surface was deleted: a deleted space platform's vault goods can land on a planet).

**Rent your warehouses to NPCs.** Build **rental warehouses** within 10 tiles of a trading hub; you
cannot open them. Every 5 minutes each idle, empty one is offered in the Contracts tab: a
counterparty stores goods your factory makes for 30 minutes.

- **Accept**: the guarantee (at least what buying the goods on the market would cost, plus 10 %) is
  held and the goods appear in the warehouse.
- In the last second of the term the counterparty takes them back through a hub of yours within
  10 tiles: you get the rent (2 credits per stack and 5 minutes) and the guarantee back. Storing
  earns no reputation.
- **Never take them out** (an inserter, mining or deconstructing the warehouse, which gives you its
  goods): a missing unit, or no hub in range at the end, fails the contract, the guarantee is kept
  and your reputation drops by 1.

## NPC planets

Researched with **Planetary concessions** (after Contracts), the **Planets** tab lists the planets
of the galaxy: what each extracts or
crafts, how far it is, and how many of its slots are free for your force. Each force has its own
slots, and its transit terms: how much longer goods from it take to land, and the most of a
shipment that can be lost on the way (farther planets risk more). With Space Age, Vulcanus, Fulgora,
Gleba and Aquilo are listed too, with their own ores and their signature craft: metallurgy,
electromagnetics, organic, cryogenics; they only craft the recipes they could host themselves.

### Mining concessions

Within reach of a hub with an import chest, open the Planets tab and press **Lease**
next to an ore. For 30 minutes the planet ships you 150 units of it every 5 minutes, by transit, to
that hub's import chests. Each shipment is charged at the ore's base value — usually between what the
market pays and what it asks — and only when it is shipped; if your hub or its import chest is gone,
that period is skipped, free. Ore in flight when the hub is removed is sold back for you. One period's charge is held as a guarantee and
comes back at the end. If you cannot pay a charge, or abandon the lease in the Contracts tab, the
guarantee is lost and your reputation drops by 1. Each planet has only a few slots per ore.

### Outsourced production

Researched with **Outsourcing** (after Planetary concessions and chemical science). On a crafting
row of the Planets tab (smelting, assembly, chemistry…), pick one of your recipes and press
**Book**. For 30 minutes the planet buys the ingredients, crafts the recipe as one machine
of speed 1 would, and ships you the products every 5 minutes by transit, charged at 105 % of their base
value (the market price without the freight fee) — otherwise the terms of a mining concession. The
message printed when you book gives the amount, the charge and the guarantee. Only recipes you have unlocked, with a single sure product,
can be booked.

## Market events

Now and then the galaxy has a **shortage** (buyers of one good pay more, and less of it can be
bought before the market's bound), a **surplus** (sellers of one good get less) or a **crisis** (a
shortage over up to 12 goods of one family, a row of the inventory). It moves the market's stock
like a stream of other traders, so the cost of large orders and the return to balance work as
usual, and your own trades add to it: selling into a shortage brings its price down. Every force
sees the same events.

**An event only ever makes prices worse.** In a shortage buyers pay more while sellers still get the
usual sell price; in a surplus sellers get less while buyers still pay the usual buy price. So no
trade, and no way of timing trades, does better with an event than it would without it, whatever you
know or guess of the event. Events are risks to plan around: make what is short rather than buy it,
and hold back what is in surplus rather than sell it.

An event's course is uncertain: it drifts at random within the range shown and may end early; it
lasts at most 10 to 30 minutes (about 14 on average), then fades, halving every 10 minutes. About
half are forecast 5 minutes ahead, and a quarter of the forecasts are called off. You are told by an
alert and a chat line once you have researched Galactic Bazaar; the **Events** tab lists them, and
the Market tab's item detail shows what they add to a price. With default settings about two come an
hour; the map settings **Market events: frequency** (0 turns them off; at 4, about seven an hour)
and **Market events: magnitude** (0.25 to 3: how far they can move prices) change that; a frequency
change waits for the draw already scheduled. Details: [market.md](market.md#market-events-scriptscoremarket_eventslua-scriptsmarket_eventslua).

## Alerts and notifications

The mod raises game alerts (the icons above the minimap; hover for the message, click to see the
building on the map) and, for most of them, prints a line in the chat:

- **Contracts**: a new offer (incoming, machine or warehouse rental), a contract due within 2 minutes with goods still to
  deliver, a contract fulfilled or failed.
- **Deliveries**: shipments landed at a trading hub, one alert per hub at most every 30 seconds,
  counting every shipment since the last one; no chat line. A shipment waiting for room in your
  import chests is counted once it is unloaded.
- **Finance**: a loan installment missed (the loan defaulted), insolvency, recovery, bankruptcy, and
  credit restored.
- **Market**: a market event forecast, started, called off or over.

Each category can be turned off for yourself only in *Settings → Mod settings → Per player*
(**Notify: contracts**, **Notify: deliveries**, **Notify: finance**, **Notify: market events**). The insolvency and bankruptcy
messages are always printed in the chat; the finance setting hides only their alerts. Details:
[notifications.md](notifications.md).
