# Terminal: the trading hub and its modules

The buildings through which a force trades. How modules attach is decided in
[ADR-0005](adr/0005-modules-attach-to-a-hub-in-range.md); the market they trade on is in
[market.md](market.md).

## Trading hub (`gb-hub`)

| | |
|---|---|
| Prototype | `prototypes/hub.lua`: an `electric-energy-interface` derived from the base game's, 2×2, tinted accumulator sprite, `gui_mode = "none"` (its interface is the mod's own) |
| Power | draws 100 kW constantly (`secondary-input`, 200 kJ buffer) |
| Recipe | 20 electronic circuits, 10 steel plates, 10 iron gear wheels, 10 s; unlocked by the technology below |
| Placement | item subgroup `galactic-bazaar` in the Logistics tab |
| Runtime | `scripts/hubs.lua` keeps `storage.hubs[unit_number] = {entity}` for every hub, from all build events (player, robot, space platform, script, revive, clone) and `on_object_destroyed` |

## Market window

Opened by clicking a hub of the player's force **within reach** (`custom-input` `gb-open-hub`,
linked to the game's "open GUI" control; `prototypes/inputs.lua`), like the game's own entity
windows: there is no remote trading, and selling takes items from the player's own inventory. Code: `scripts/market_gui.lua`, with the pure list
logic in `scripts/core/catalog.lua`.

| Part | Behaviour |
|---|---|
| Status | the force's balance, whether the hub has power, and its capsules queued out of `max_capsules` |
| List | tradeable items then fluids (`storage.tradeable_items`, `storage.tradeable_fluids`, built with the base values; keys `item/<name>` and `fluid/<name>`), filtered by the search text against internal names (every word must appear; case and separators ignored), `catalog.PAGE_SIZE` (15) rows per page: icon, name, buy price, sell price as the force sees them (`telecom.quote`, at most its telecommunications period old, [ADR-0012](adr/0012-telecommunications-set-price-freshness.md)), and with telecommunications 2 the trend (▲ ▼ – from the price history), in fixed-width columns with prices right-aligned; a name too long for its column is clipped and shown whole in its tooltip. Only the rows shown are read from the market (ADR-0004). The 15 rows are built once and updated in place, so a refresh never destroys a button a player is clicking (multiplayer latency) |
| Detail | for the selected item: with telecommunications 2, a history line (sparkline of the last 30 NPC steps); a quantity field (whole number up to 10⁹) and a live preview of what buying and selling that quantity would cost and bring, market impact included; the buying cost includes the freight fee. A purchase is exactly the preview; a sale may trade fewer units (the plain units in the inventory), and the printed result gives the real numbers |
| Buy | needs a powered hub with an import chest of its force (items) or an import manifold of its force that is empty or already holds the fluid (fluids); pays the market cost plus the freight fee at once and queues the units in orbital capsules (`freight.order`, see below); the printed result says when the last capsule lands |
| Sell | items only (fluids are sold by export manifolds); needs a powered hub; sells plain normal-quality stacks of the item from the player's main inventory (`cargo.sell_stacks`, floor `cargo.WINDOW_MIN_PRICE_RATIO` = 0.05 of the base value), each unit at its price times its freshness, the preview scaled by the average freshness of the stacks it would take (`cargo.sale_freshness`) ([ADR-0013](adr/0013-spoilable-goods-priced-by-freshness.md)); other qualities stay in the inventory until the window can pick a quality |
| Refresh | once a second per open window of a connected player, spread over `SLOTS` (10) slots of `SLOT_TICKS` (6) ticks by player index; a window whose hub is gone, foreign or out of reach is closed. Measured on 2.1.24: 0.18 ms per window refresh in vanilla (196 items), 0.40 ms with Space Age (284) — budget 0.5 ms per window |
| Closing | close button, E/Esc or another window (`on_gui_closed`), hub destroyed, player leaves, changes force or is removed, out of reach on refresh, configuration change |

Every action re-checks the hub (exists, same force, within reach, powered), the item and the
quantity, since GUI events are player input; only elements created by this mod trigger actions. Results are printed to the player. Fluids are not listed yet (fluid
module, M3). The window's layout has only been checked by tests, not by eye.

## Cargo module (`gb-export-chest`, `gb-import-chest`)

| | |
|---|---|
| Prototypes | `prototypes/cargo.lua`: two 48-slot containers derived from the steel chest, tinted orange (export) and green (import); icons add an up or down arrow |
| Recipe | 1 steel chest + 5 electronic circuits, 2 s; unlocked by the technology below |
| Attachment | the nearest registered hub of the same force within `cargo.HUB_RANGE` (10 tiles), resolved on build, for nearby modules when a hub is built, for a removed hub's modules, for every module on configuration change and force merge ([ADR-0005](adr/0005-modules-attach-to-a-hub-in-range.md)). When its hub has no power or belongs to another force, a module switches to the nearest powered hub of its force in range; if there is none, it stays attached to its nearest hub, powered or not |
| Export | every `cargo.EXPORT_INTERVAL` (6) ticks, the next `cargo.EXPORT_BATCH` (2) export chests — 20 chests a second — sell their plain stacks while each unit still fetches at least `min_price_ratio` (default 0.5) × its base value. Plain (any quality, sold at its quality's price, [ADR-0008](adr/0008-quality-values-by-level.md)): no extra data (equipment grid, inventory, blueprint, tags), full health, unused tools and ammunition. Spoilable goods (Space Age) are plain too, though each of their stacks carries a `LuaItem`; a unit fetches its price × its freshness (`1 - spoil_percent`), the market moving by the units sold, and the floor applies to that, so with the default floor a stack less than about half fresh stays in the chest ([ADR-0013](adr/0013-spoilable-goods-priced-by-freshness.md)). The sale is made first; the stack only shrinks for what was paid; journal entries merge per item and minute (`cargo.JOURNAL_MERGE_TICKS`) |
| Import | `cargo.deliver(hub_unit_number, name, count)` inserts landed items into that hub's import chests and returns how many fit; `cargo.has_import(hub_unit_number)` says whether the hub has an import chest of its force |
| Budget | 0.09 ms per batch of 2 chests holding 4 item kinds each, measured on 2.1.24 with 164 chests in range (≈ 0.015 ms per tick on average); 0.13–0.15 ms with Space Age and quality pricing (budget 0.2 ms); the in-game test logs it, since LuaProfiler cannot be compared from Lua |
| Throughput | each chest is visited every `n / 20` seconds for `n` export chests: with 2000 chests, every 100 s — fewer, fuller chests sell faster than many small ones |

The export price floor is per chest; its interface comes with #19.

## Technologies

| Technology | Prerequisites | Cost | Unlocks |
|---|---|---|---|
| `gb-galactic-bazaar` (Galactic Bazaar) | Electronics, Steel processing | 75 × red science, 15 s each | trading hub, export chest, import chest |

Defined in `prototypes/technologies.lua`. The orbital capsule is added to it when it exists (#20). Research itself always happens in the player's labs.

## Delivery tiers (orbital capsule, cargo shuttle, teleporter)

Purchases are delivered by logistics tier ([ADR-0006](adr/0006-deliveries-by-logistics-tier.md));
each hub ships by the best tier its buildings provide, the orbital capsule otherwise
([ADR-0014](adr/0014-delivery-tier-per-hub.md)). Code: `scripts/freight.lua`, with the pure
scheduling and the tier parameters in `scripts/core/freight.lua` (`freight.TIERS`).

| Tier | Rank | Delay | One shipment every | Capacity | Fee | Queue bound | Provided by |
|---|---|---|---|---|---|---|---|
| `capsule` | 1 | 1800 ticks (30 s) | 600 ticks (10 s) | 10 stacks | 5 % | 20 | always |
| `shuttle` | 2 | 1200 ticks (20 s) | 300 ticks (5 s) | 40 stacks | 3 % | 20 | a docking bay holding fuel (100 MJ per shipment) |
| `teleporter` | 3 | 60 ticks (1 s) | 60 ticks (1 s) | 20 stacks | 1 % | 20 | a powered teleporter (20 MW) |

A module providing a tier registers `freight.register_tier_provider({tier, available, can_supply,
supply})` at file scope (`available(hub)` and `can_supply(hub, shipments)` without side effect,
`supply(hub, shipments)` after payment, `delivers(hub)` true, false or nil to hold queued shipments); an order a tier cannot supply, or whose queue is full, falls back to the next tier (`freight.tier_for(hub, name, units, kind)` gives the tier an order would ship by); `freight.tier(hub_unit_number)`
gives the hub's tier. An order is scheduled, charged and bounded with the tier at order time and each
shipment records it. Each tier launches on its own schedule and has its own queue bound
(`freight.queued(hub, tier)`), and unloading takes every landed shipment, so tiers never hold each
other back. The market window's status line shows the tier and its queue; a purchase from it is
refused (`tier-changed`) when the tier changed since the window showed it. The rows below describe the capsule; the
other tiers differ only by their parameters.

| Payment | at order time: the market cost plus `fee_rate` (5 %) of it, journaled as a `buy` and a `freight` entry; refused whole if the balance does not cover both. Each capsule records the force that paid and the market price paid per unit |
| Capsules | an order is split into capsules of at most `capacity_stacks` (10) stacks of the item |
| Throughput | each hub launches one capsule every `launch_interval_ticks` (600, 10 s), so at most 1 stack a second per hub |
| Latency | a capsule lands `delay_ticks` (1800, 30 s) after its launch |
| Queue bound | at most `max_capsules` (20) capsules per hub, landed ones included; a larger order is refused (`queue-full`) |
| Unloading | every `freight.UNLOAD_INTERVAL` (60) ticks, landed capsules are unloaded into the hub's import chests (items) or import manifolds (fluids) of the hub's force, in landing order; what does not fit stays landed and is retried, without holding back the other landed capsules. Landing needs no power. A delivery only visits the chests of its hub (`storage.cargo.imports`), so its cost does not grow with the other cargo chests of the map |
| Hub removed | the cargo still queued is sold back to the market for the force that paid; what the market refuses (item no longer tradeable, no liquidity) is refunded at the price paid (`freight-refund`). The fee is not refunded |
| Item removed | on a configuration change, capsules of items that no longer exist are refunded at the price paid and dropped |
| Force merge | capsules paid by the merged force are credited to the destination force |

Purchases are normal quality. Space Age cargo pods are not reused (ADR-0006).

## Power module (`gb-power-export`, `gb-power-import`)

Substations that trade electricity with the market ([ADR-0009](adr/0009-power-trading-by-tertiary-substations.md)).
Code: `scripts/power.lua`; prototypes: `prototypes/power.lua`.

| | |
|---|---|
| Prototypes | two 2×2 `electric-energy-interface`s, tinted orange (export) and green (import), `tertiary` priority like accumulators: export charges only from the network's surplus (input 40 MW, output 0), import discharges only on shortage (input 0, output 40 MW) |
| Recipe | 10 steel plates, 10 electronic circuits, 20 copper cables, 5 s |
| Technology | `gb-power-trading` (after the Galactic Bazaar and electric energy distribution 1; 150 × red and green) unlocks both, at 10 MW each; `gb-power-trading-2` (after electric energy distribution 2; 300 × red, green, blue) raises them to 40 MW |
| Hub | the nearest hub of the same force within `power.HUB_RANGE` (10 tiles), attached when the substation is built, when a hub is built or removed nearby, on force merge and on configuration change; at a settlement, a substation whose hub has no power or another force switches to the nearest powered hub in range; without a hub in range it does not trade, and costs no search until a hub is built |
| Settlement | every `power.SETTLE_TICKS` (300, 5 s): per force, the export buffers are sold in one trade while electricity fetches at least `power.MIN_PRICE_RATIO` (0.5) × its base value (unsold energy stays), and the import buffers are refilled in one trade, scaled down to what the force can pay and the market can supply |
| Throughput | the buffer size, set at each settlement to the level's power × 5 s (`power.LEVEL_WATTS`: 10 MW, 40 MW); runtime flow limits cannot be changed in 2.1, so the prototype's are the highest level's |
| Journal | per force, one `sell` and one `buy` entry of `energy/electricity` per minute (`power.JOURNAL_MERGE_TICKS`), the settlements of that minute merged into it, quantity in MJ |
| Integrity | production and usage settings zeroed when built and at each settlement; a new or cloned substation starts empty |
| Budget | 0.35–0.8 ms per settlement of 199 substations (40 around one hub), measured on 2.1.24 — budget 1 ms every 5 s |

Energy prepaid into an import substation is lost when it is mined. The substations share the
tertiary tier with accumulators: on a shortage they discharge alongside the player's accumulators,
and on a surplus they take a share of the charge.

## Price signal combinators (`gb-buy-price-combinator`, `gb-sell-price-combinator`)

Constant combinators whose signals the script writes ([ADR-0010](adr/0010-price-signals-from-script-written-combinators.md));
the player-facing explanation is [player-guide.md](player-guide.md). Code: `scripts/price_signals.lua`,
scaling in `scripts/core/signals.lua`; prototypes: `prototypes/signals.lua`.

| | |
|---|---|
| Prototypes | copies of the constant combinator, tinted green (buy) and orange (sell); the virtual signal `gb-credits` |
| Recipe | 1 constant combinator + 5 electronic circuits, 2 s |
| Technology | `gb-market-signals` (after the Galactic Bazaar and circuit network; 100 × red and green) |
| Hub | attached like the power substations: nearest hub of the force within `price_signals.HUB_RANGE` (10 tiles), re-checked at each visit; silent (`enabled = false`) without a powered one |
| Signals | section 1: buy or sell price of every item in `storage.tradeable_items` and fluid in `storage.tradeable_fluids`, normal quality, in milli-credits; section 2: the balance on `gb-credits` in credits, read live at each visit (`signals.price`, `signals.balance`: rounded, clamped to int32, zero values left out) |
| Snapshot | per force, taken again when older than the force's telecommunications period (30 s, 10 s or 2 s, ADR-0012), quoting `SNAPSHOT_CHUNK` (40) keys per pass from the item and fluid lists captured when it started; combinators keep the last complete snapshot; its version changes only when a price changed. Reading every price keeps a market entry per key and force up to date (`storage.forces[i].markets`) |
| Writing | every `PASS_TICKS` (6), up to `VISITS` (10) combinators are visited in turn, the pass stopping after one price rewrite (a whole `filters` write); the balance slot is set when it changed. Prices thus reach every combinator within 10 s plus 0.1 s per combinator to rewrite |
| Integrity | players cannot open it (`operable = false`); a combinator is registered once; any section that is not one of the script's two plain sections (blueprint, pasted settings, another mod: a group, inactive, a multiplier) is replaced at the next visit; pasted settings force a rewrite |
| Budget | costliest pass (one price rewrite): 0.2–0.5 ms; average pass during a rebuild: 0.17–0.29 ms (2.1.24, vanilla and Space Age) — budgets 0.6 ms and 0.3 ms |

## Order combinator (`gb-order-combinator`)

Buys from circuit signals ([ADR-0011](adr/0011-circuit-orders-by-period.md)); player-facing
explanation in [player-guide.md](player-guide.md). Code: `scripts/circuit_orders.lua`, request
parsing and budget in `scripts/core/orders.lua`; prototype in `prototypes/signals.lua`.

| | |
|---|---|
| Prototype | a copy of the constant combinator, tinted blue; it emits nothing (no section, disabled) and players cannot open it |
| Recipe | 1 constant combinator + 5 electronic circuits, 2 s |
| Technology | `gb-market-orders` (after market signals; 150 × red and green) |
| Hub | attached like the other modules (`circuit_orders.HUB_RANGE`, 10 tiles); orders only through a powered hub of its force |
| Reading | every `circuit_orders.ORDER_TICKS` (600, 10 s), spread over `SLOTS` (10) passes of `PASS_TICKS` (60) by unit number: its red and green inputs, after removing any section or output put on it (a combinator that had to be silenced skips that reading); each positive normal-quality item signal and each positive fluid signal asks to buy that many units |
| Budget | nothing is bought without a positive `gb-budget` signal; its value caps what the force spends through order combinators in the period (`storage.circuit_orders.spent`), within the balance; an input carrying `gb-credits` (a price combinator's balance) is refused whole |
| Orders | fluids first, then items, each in name order, each placed with `freight.order` (capsule delivery, freight fee, refused when it exceeds what is left of the budget: `over-budget`); a full capsule queue stops the combinator's orders for the period |
| Budget (UPS) | a pass with 50 combinators asking for 5 items each: 0.09 ms in vanilla, 0.13 ms with Space Age (2.1.24) — budget 0.2 ms |
| Journal | `buy` and `freight` entries merged per item and minute (`circuit_orders.JOURNAL_MERGE_TICKS`) |

## Telecommunications (`gb-telecommunications-1`, `gb-telecommunications-2`)

Research that sets how fresh the prices a force sees are ([ADR-0012](adr/0012-telecommunications-set-price-freshness.md)).
Code: `scripts/telecom.lua`, levels and sparkline in `scripts/core/telecom.lua`.

| Level | Technology | Prices seen and emitted | Also |
|---|---|---|---|
| 0 | none | at most 30 s old | |
| 1 | `gb-telecommunications-1` (after the Galactic Bazaar and logistic science; 100 × red and green) | at most 10 s old | |
| 2 | `gb-telecommunications-2` (after level 1 and advanced circuits; 200 × red and green) | at most 2 s old | trend column and history line in the market window |

`telecom.quote(force_index, kind, name, period)` returns `{buy, sell, history}` from the force's
feed (`storage.forces[i].feed[key]`), quoted again when older than the period; the feed is cleared
whenever base values are rebuilt. Trade previews and executions always use live prices
(`market.quote`, `market.preview`). Below level 2 the trend column stays in place with empty cells
(hiding table cells would shift the others); the history line appears once the item's market has
two history points.

A price combinator snapshot's period runs from the end of its build. At level 2, a force's
snapshot is rebuilt every 2 s and, while prices move, its combinators are rewritten one per pass:
prices reach the last of `n` combinators within 2 s plus about `n` × 0.1 s. Measured with 30
combinators and moving prices: 0.04–0.05 ms per tick on average (2.1.24) — budget 0.06 ms.

## Manifold module (`gb-fluid-export`, `gb-fluid-import`)

Fluid trading (#63). Code: `scripts/manifold.lua`; prototypes: `prototypes/manifold.lua`.

| | |
|---|---|
| Prototypes | two storage tanks (25 000 units, base storage tank), tinted orange (export) and green (import) |
| Recipe | 1 storage tank + 10 electronic circuits, 3 s |
| Technology | `gb-fluid-trading` (after the Galactic Bazaar and fluid handling; 100 × red and green) |
| Hub | attached like the other modules (`manifold.HUB_RANGE`, 10 tiles) |
| Export | every `manifold.EXPORT_INTERVAL` (6) ticks, the next `manifold.EXPORT_BATCH` (2) export manifolds with a powered hub sell their fluid while it fetches at least `manifold.MIN_PRICE_RATIO` (0.5) × its base value; the fluid leaves the tank first, the market pays for what actually left, and it goes back if the market refuses; journal entries merged per fluid and minute. Fluids are priced by name: temperature does not change the price |
| Import | fluids bought from the market window or an order combinator travel by orbital capsule (`freight.order(…, "fluid")`), `freight.FLUID_UNITS_PER_STACK` (500) units taking the room of one stack, and land in the hub's import manifolds of its force at the fluid's default temperature (`manifold.deliver`, through the index `storage.manifold.imports`); without an import manifold that is empty or already holds the fluid, the order is refused (`no-import-manifold`) |
| Budget | 0.03–0.06 ms per export batch of 2 manifolds (2.1.24, vanilla and Space Age) — budget 0.1 ms |

## Docking bay (`gb-docking-bay`)

Gives its hub the cargo shuttle tier (#65, [ADR-0014](adr/0014-delivery-tier-per-hub.md)). Code:
`scripts/docking_bay.lua`; prototype: `prototypes/docking_bay.lua`.

| | |
|---|---|
| Prototype | a 10-slot chest derived from the steel chest, tinted blue |
| Recipe | 50 steel plates, 20 advanced circuits, 10 electric engines, 10 s |
| Technology | `gb-cargo-shuttle` (after the Galactic Bazaar, rocket fuel and electric engine; 300 × red, green and blue) |
| Hub | attached like the other modules (`docking_bay.HUB_RANGE`, 10 tiles); bays of another force are ignored |
| Fuel | any chemical fuel item, any quality; `docking_bay.fuel(hub, enough)` sums the bays' buffers and fuel items in MJ, stopping once it reaches `enough`; a hub's bays are indexed (`storage.docking_bays.by_hub`) |
| Tier | the hub has the shuttle while its bays hold at least `FUEL_MJ_PER_SHIPMENT` (100 MJ, one rocket fuel); an order needing more shipments than the fuel covers, or finding the shuttle's queue full, goes by the next tier (orbital capsule), burning nothing. The market window plans the tier for the quantity typed and names it in the preview |
| Budget | a tier read of a hub with 5 bays among 50: 0.06 ms (2.1.24) — budget 0.1 ms |
| Burning | when a shuttle order is paid, `shipments × 100 MJ` are burnt from the bays in unit-number order: each bay's buffer first, then whole items in name order; what the last item gives beyond the need goes to the bay's buffer (lost if the bay is removed) |

## Teleporter (`gb-teleporter`)

Gives its hub the teleporter tier (#66, [ADR-0014](adr/0014-delivery-tier-per-hub.md)). Code:
`scripts/teleporter.lua`; prototype: `prototypes/teleporter.lua`.

| | |
|---|---|
| Prototype | an `electric-energy-interface` derived from the base one, tinted violet, drawing 20 MW (`secondary-input`, 40 MJ buffer, intake capped at 24 MW so a network that cannot keep up drains it; a fresh one reaches half its buffer in about 5 s) |
| Recipe | 100 processing units, 50 low density structures, 200 steel plates, 30 s |
| Technology | `gb-teleporter` (after the cargo shuttle, processing unit, low density structure, production and utility science; 500 × the five vanilla packs) |
| Hub | attached like the other modules (`teleporter.HUB_RANGE`, 10 tiles), indexed per hub (`storage.teleporters.by_hub`) |
| Tier | the hub has the teleporter while one of its teleporters of its force holds at least `POWERED_SHARE` (half) of its buffer |
| Without power | while all the hub's teleporters are unpowered, its teleporter shipments already queued wait (`delivers`); once the hub has no teleporter at all (mined, attached elsewhere), they land, since they were paid for |

## Electromagnetic catapult (`gb-catapult`)

Bulk exports (#67). Code: `scripts/catapult.lua`; prototypes: `prototypes/catapult.lua`.

| | |
|---|---|
| Prototypes | a 48-slot chest derived from the steel chest, tinted red; under it, a hidden `gb-catapult-capacitor` (electric-energy-interface, not selectable, not blueprintable, not repairable, indestructible, no collision layers but the chest's footprint for pole coverage; `secondary-input`, 100 MJ buffer, intake capped at 30 MW) placed and removed by the script with the catapult; a catapult adopts a capacitor already under it (an area clone copies both) |
| Recipe | 100 steel plates, 30 advanced circuits, 10 accumulators, 20 electric engines, 20 s |
| Technology | `gb-catapult` (after the Galactic Bazaar, accumulators and electric engine; 250 × red, green and blue) |
| Hub | attached like the other modules (`catapult.HUB_RANGE`, 10 tiles); shoots only through a powered hub of its force |
| Shot | every `catapult.PASS_TICKS` (6), catapults are visited in turn, up to `VISITS` (5), empty ones passed over, until one shoots: it shoots if its interval (`SHOT_TICKS`, 120) passed and its capacitor holds `SHOT_MJ` (50 MJ): it sells every plain stack while each unit fetches at least `cargo.DEFAULT_MIN_PRICE_RATIO` (0.5) × its base value, then spends the 50 MJ, only if something sold |
| Journal | entries merged per item and minute (`cargo.JOURNAL_MERGE_TICKS`), like export chests |
| Budget | a shot of 48 full stacks: 0.44–0.48 ms with 4 kinds, 0.65 ms with 48 different items (2.1.24); one shot per pass — budget 0.8 ms |
| Throughput | at most one shot per pass for the whole map (10 a second): with more than 20 loaded catapults, each waits about `n` × 0.1 s rather than 2 s |
| Lifecycle | a catapult whose capacitor is gone (another mod destroyed it) gets a new one at its next shot or on configuration change |
