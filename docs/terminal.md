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

## Market tab

The Market tab of the Galactic Bazaar window ([window.md](window.md)). Clicking a hub of the
player's force **within reach** (`custom-input` `gb-open-hub`, linked to the game's "open GUI"
control; `prototypes/inputs.lua`) opens the window on this tab, bound to that hub; the hotkey or the
mod button open the window anywhere. Prices can be read anywhere, but buying and selling go
through the window's hub, which must be within reach when the action runs: there is no remote
trading, and selling takes items from the player's own inventory. Code: `scripts/market_gui.lua`,
with the pure list logic in `scripts/core/catalog.lua`; the item detail in `scripts/item_detail_gui.lua`,
its figures computed by `scripts/core/item_detail.lua` (pure).

| Part | Behaviour |
|---|---|
| Status | the force's balance, the overdraft it has left out of its limit (tooltip: the interest terms, [ADR-0020](adr/0020-overdraft-and-debit-interest.md)), while it applies the force's insolvency with the time left before bankruptcy or the credit ban with the time left and the bankruptcy debt still to repay (tooltip: what to do or what is refused, [contracts.md](contracts.md)), its reputation (tooltip: its freight fee and contract size factors, [contracts.md](contracts.md)), whether the window's hub has power (or that no hub is within reach), and with a hub its delivery tier and the capsules queued out of `max_capsules` |
| List | tradeable items then fluids (`storage.tradeable_items`, `storage.tradeable_fluids`, built with the base values; keys `item/<name>` and `fluid/<name>`), filtered by the search text against internal names (every word must appear; case and separators ignored), `catalog.PAGE_SIZE` (15) rows per page: icon, name, buy price, sell price as the force sees them (`telecom.quote`, at most its telecommunications period old, [ADR-0012](adr/0012-telecommunications-set-price-freshness.md)), and with telecommunications 2 the trend (▲ ▼ – from the price history), in fixed-width columns with prices right-aligned; a name too long for its column is clipped and shown whole in its tooltip. Only the rows shown are read from the market (ADR-0004). The 15 rows are built once and updated in place, so a refresh never destroys a button a player is clicking (multiplayer latency) |
| Detail | beside the list, for the selected item, in a panel that scrolls beyond 640 px: a quantity field (whole number up to 10⁹) and a live preview of what buying and selling that quantity would cost and bring, market impact included; the buying cost includes the freight fee of the tier the window's hub would ship by (the orbital capsule's without a hub). A purchase is exactly the preview shown in the same tick (a price, tier or reputation change between the refresh and the click shows in the printed result); a sale may trade fewer units (the plain units in the inventory), and the printed result gives the real numbers. Below it, the [item detail](#item-detail) |
| Buy | needs a powered hub with an import chest of its force (items) or an import manifold of its force that is empty or already holds the fluid (fluids); pays the market cost plus the freight fee at once and queues the units in orbital capsules (`freight.order`, see below); the printed result says when the last capsule lands |
| Sell | items only (fluids are sold by export manifolds); needs a powered hub; sells plain normal-quality stacks of the item from the player's main inventory (`cargo.sell_stacks`, floor `cargo.WINDOW_MIN_PRICE_RATIO` = 0.05 of the base value), each unit at its price times its freshness, the preview scaled by the average freshness of the stacks it would take (`cargo.sale_freshness`) ([ADR-0013](adr/0013-spoilable-goods-priced-by-freshness.md)); other qualities stay in the inventory until the window can pick a quality |
| Refresh | while shown, once a second, by the window ([window.md](window.md)); a hub gone, foreign or out of reach is no longer the window's, which stays open. Measured on 2.1.24: 0.32 to 0.66 ms per refresh without a selected item (208 items in vanilla, 296 with Space Age), 0.45 to 0.62 ms with a selected item, its preview and its [item detail](#item-detail) (averages of 10 or 20, vanilla and Space Age, run alone; one run measured 0.93 ms, costlier with nothing to rewrite than with the price changed, which points to a garbage collection), within the window's budget of 0.7 ms ([window.md](window.md#refresh-and-budget)) |

Every part also has a tooltip with its rule (#111, [window.md](window.md#explanations)): the
balance, the hub line (which hub the window trades through), the delivery line (the tier's terms
for the force, as in the Logistics tab), each column header and its cells (buy and sell: mid price
plus or minus half the spread, the price freshness by telecommunications level; trend: over the
NPC history, flat within `catalog.FLAT_TREND`), the quantity field, Buy, Sell (its floor) and the
preview.

Every action re-checks the hub (exists, same force, within reach, powered), the item and the
quantity, since GUI events are player input; only elements created by this mod trigger actions.
Results are printed to the player. The tab's layout has only been checked by tests, not by eye.

### Item detail

Why the selected item's prices are what they are (#110). `item_detail_gui.read(force, kind, name,
quality_name, quantity)` reads the key once and returns plain figures; the panel shows them, each
market line with a tooltip giving its rule in plain words (EN and FR locale section `gb-detail`).

| Part | Shows | Computed by |
|---|---|---|
| Order impact | for the quantity typed, buying and selling: the average unit price and the next unit's price after the order, or why the market cannot take it; live prices, like the preview | `item_detail.impact` (`market.quote_buy`, `quote_sell`) |
| Market | buy, sell and mid prices; base value; gap of the mid price from the base value in percent, with the shortage or surplus in units (the displacement, [market.md](market.md)); liquidity left on each side before the bound and the bounds of the mid price; spread in percent and credits; NPC drift per step in units, with the largest rise and fall of the mid price it causes; half-life and the mid price after it without trades; how old the prices are and the force's telecommunications period | `item_detail.market`, from the price the force sees (its feed, [ADR-0012](adr/0012-telecommunications-set-price-freshness.md)): the displacement is found back from the seen buy price (`item_detail.displacement_from_buy`), so the panel never shows fresher prices than the list |
| Price history | with telecommunications 2, the sparkline of the last 30 NPC steps, its lowest and highest points, the current mid price and the change over the period; once the market has two points. Below level 2, the research that unlocks it | `item_detail.history`, `telecom.sparkline` |
| Why it is worth | the source the valuation chose ([pricing.md](pricing.md#value-sources)): a recipe (rich-text icon and name), mining (gathering for a natural source), pumping, a rocket launch or burning a fuel; up to `MAX_INPUTS` (10) ingredient lines (amount × value = total; more are counted), the crafting or mining time cost, the run's total divided over its products and the amount made; a value set by a mod, or the factor a mod applies; a note when the key was priced in the fallback tier (from a planet-bound process, its own or its ingredients'); the base value multiplier when not 1 (not for a value a mod set, which it does not scale); for items with a quality mod, the value of each higher quality | `item_detail.breakdown`, `item_detail.quality_ladder` |

When the selected key has no market any more (its value was removed since the list was taken), the
panel's figures and breakdown are hidden and its marks reset. The quality of the list is normal; `item_detail_gui.read` also takes a quality (figures live, as the
feed holds normal quality only). Elements are built once with the tab and updated in place; a
refresh writes only what may have changed: the order impact and the prices' age always, the market
figures and history when the seen buy price or the telecommunications level changes, the tooltips
and the breakdown when the item or its base value changes (marks kept in the view,
[data-model.md](data-model.md#storagebazaar_gui)); the breakdown is computed only then. Budget:
0.1 ms per detail refresh, within the tab's. Measured on 2.1.24 (averages of 10 or 20, run alone):
0.04 to 0.055 ms when nothing changed and 0.07 to 0.10 ms when the price seen changed, vanilla and
Space Age; 0.17 ms when everything is rewritten, which happens when the player selects an item (an
action, not the periodic refresh) or base values are rebuilt. See the Refresh line above for the tab.

## Logistics tab

The Logistics tab of the Galactic Bazaar window ([window.md](window.md)) shows what is in flight
and the state of each hub's buildings (#109). Read only: it works anywhere, remote view included.
Code: `scripts/logistics_gui.lua`; the rows (hub order, selection, queue use, each shipment's state
and origin, module order and counts, pages) come from `scripts/core/logistics.lua` (pure,
`spec/core/logistics_spec.lua`); texts in the `[gb-logistics]` locale section.

| Part | Behaviour |
|---|---|
| Hubs | every hub of the player's force, by surface then unit number, `HUB_ROWS` (5) a page: a button with its surface and position that selects it, its power, its status as the building shows it (`entity_status.shown`: diode and text, or "not read yet" before its first refresh) and how full each tier's queue is (`x / max_capsules` for each tier with a shipment queued; tooltip: what the bound does). The hub selected stays selected while it exists and is the force's; otherwise the window's hub, otherwise the first |
| Selected hub | a camera on the hub (or on the module in focus), its location, power, the tier it ships by now (`freight.tier`; tooltip: delay, launch interval, capacity, the fee for the force with its reputation, queue bound, and which building gives which tier) and its queue use, the current tier always listed |
| Shipments | the force's shipments at the hub (`freight.capsules`), by landing tick, `SHIPMENT_ROWS` (8) a page: goods (icon and count still to unload), tier, state, landing time (the game time, `h:mm:ss`, and the time left), origin and unit cost. States: waiting for its launch (with the time until it; the tier launches one shipment per interval), in flight, in transit from a planet, landed (no unloading pass, every `freight.UNLOAD_INTERVAL` ticks, has run since it landed), waiting for room in the import chests or for an import manifold that can take the fluid (a pass found none), held (its tier cannot deliver: `freight.delivers`, a teleporter without power); each has a tooltip saying why. Origins: purchase (unit cost = market price paid, fee not included), incoming contract ingredients (contract number, free), concession or outsourcing (the planet; tooltip: the share lost in transit and the planet's maximum, unit cost = the charge per arriving unit), or a planet whose contract is no longer known. The kind and counterparty come from the force's open contracts, then its history; shipments queued before 0.1.33 carry no planet or loss: the planet is then the contract's counterparty, and a paid contract shipment whose contract is gone is shown as from a planet (contract ingredients are never paid) |
| Modules | the buildings of the force attached to the hub, `MODULE_ROWS` (8) a page, by kind order, building and unit number, with a summary per building (count, and how many are red or yellow); each row: a button with the building's icon that points the camera at it (again: back to the hub; only a building listed for the selected hub can be focused), its name and location, its status as the building shows it, read at each refresh. They come from `entity_status.modules_of`, which reads the modules the status passes found attached to that hub in the last and the current cycle (`members`, `joining`), each checked again (still listed, attached to the hub, valid, of the force): its cost follows the hub's modules, not the map's. A module attached since (built: at once; re-attached to another hub: at its next status refresh) shows within one status cycle (5 s) |
| Refresh | while shown, once a second, by the window. Selecting a hub accepts only a hub of the player's force (GUI events are player input). The module list is read again when another hub is selected or every `MODULE_RESCAN_TICKS` (300, the status cycle); statuses are read at each refresh. Rows are built once; the cells of a hub, shipment or module row are rewritten only when the facts that row shows changed (`drawn`; a status cell when the building's descriptor changed), except the countdowns, while the headings, counts, pagers and the selected hub's header are written at each refresh; rows are shown or hidden only when their number changes (`visible`), every cell of a hidden row together. Budget: 0.7 ms per refresh, module listing included; measured in [window.md](window.md#refresh-and-budget) |

The tab's layout has only been checked by tests, not by eye; whether the camera, the
`[img=…]` diodes and the toggled buttons look right is still to be checked on screen.

## Building status

Every building below tells what it is doing (#106). Code: `scripts/entity_status.lua` reads the
facts from the game, `scripts/core/entity_status.lua` turns them into a status (unit-tested), and
the texts are in the `[gb-status]` locale section.

| | |
|---|---|
| Custom status | `LuaEntity.custom_status`: a diode (green: working, yellow: waiting or limited, red: stopped) and a text, which the game shows where it shows an entity's status; written only when it changed (`storage.entity_status.shown`). Texts hold no moving value (no age, no countdown): they state facts that stay true until the next refresh. A rented rental assembler keeps the game's own status (its crafting diagnostics); its contract's progress is in the Contracts tab |
| Alert | while a building is stopped, an icon is drawn on it, visible to its force only: `utility/warning_icon` with no hub of its force in range ("No hub"), `utility/electricity_icon` when its hub has no power ("Hub unpowered") or when it has none itself, a hub or a teleporter ("No power"); the text shows under it in alt mode. It is redrawn when the building changes force, removed as soon as the cause goes, and with the building |
| Attachment | a module without a hub of its force in range is red "no trading hub" (alert); with an unpowered hub, a module that trades through it (export chest and manifold, power substations, price and order combinators, catapult) is red "stopped" (alert), the others (import chest and manifold, docking bay, teleporter, contract chest, rental assembler) keep their own status, yellow, behind "its trading hub has no power" |
| Cadence | the buildings are kept in one list (`storage.entity_status`), in step with build and destroy events and rebuilt on configuration change; every `PASS_TICKS` (10) ticks a pass refreshes the next ones, `ceil(n / 30)` of them, at most `MAX_VISITS` (8): each building once every `CYCLE_TICKS` (300, 5 s) up to 240 buildings, then every `n / 48` s (21 s with 1000). The costly reads — a hub's delivery tier and its bays' fuel, a force's contract needs and price period — are made once per hub or force and cycle (`facts`), and a pass never makes more than `MAX_COSTLY_READS` (2) of them: each kind reserves the costly reads its status may make (a docking bay 2, a hub, price combinator or contract chest 1) and the pass stops before a building whose reservation would exceed the cap. A building removed before the cursor trades places so that the one replacing it is still refreshed in the cycle. A building is also refreshed when built. Each hub's modules of its force are counted as they are refreshed and shown from the next cycle |
| Budget | at most 0.3 ms per pass (one pass every 10 ticks, so at most 0.03 ms per tick on average) with 1000 buildings, whatever the layout: a pass does at most 8 refreshes and 2 costly reads, its costliest case being 7 of the dearest refresh without a costly read (price combinators) and a docking bay whose hub's tier and fuel are not read yet. Measured on 2.1.24 with 20 hubs and about 1000 modules, seven runs in vanilla and Space Age on a machine shared with other test runs: average pass 0.09–0.23 ms, costliest pass 0.11–0.19 ms (`tests/entity_status.lua` logs both). With 12 refreshes per pass the costliest reached 0.39 ms, hence 8 |

| Building | What its status says |
|---|---|
| Trading hub | powered: modules of its force attached (counted over the last cycle), shipments queued, delivery tier; unpowered: red, trading suspended ("No power" alert) |
| Export chest | waiting for goods; selling; yellow when its last visit sold nothing of what it holds (below its price floor, or damaged, used, carrying data) |
| Import chest | ready to receive; receiving, with the shipments queued at its hub |
| Export manifold | waiting for fluid; selling the fluid it holds; yellow when its last visit sold none (below its price floor) |
| Import manifold | ready to receive fluids; or the fluid it holds, the only one it can receive until emptied |
| Power substations | the MJ the force's substations of that direction sold or bought at the last settlement (every 5 s); otherwise waiting for surplus or shortage, or yellow when that same settlement left export energy unsold below the floor, or import energy unbought (no funds, no supply) |
| Price combinators | how many prices it emits and how often they are refreshed (the telecommunications period); yellow while the first snapshot is being built |
| Order combinator | its last reading: the orders it placed and the budget left this period, or why it bought nothing: price signals on its input (red), no Budget signal, no orders, budget spent, no funds, each order larger than the budget left or than the funds, queue full, or the market's refusal |
| Docking bay | its own fuel in MJ, whether its hub's bays hold a shuttle shipment's fuel (yellow otherwise), and the tier its hub actually ships by (a powered teleporter outranks the shuttle) |
| Teleporter | powered: its hub ships by teleporter; otherwise red with its charge ("No power" alert) |
| Catapult | its capacitor's charge; charging (yellow) below a shot's 50 MJ; waiting for goods; yellow when its last shot that could fire sold nothing (below the floor, or not plain); otherwise ready, shooting at most every 2 s |
| Contract chest | the normal-quality items its force's active incoming contracts still need, summed, oldest contract first (4 named, the rest counted); idle without any |
| Rental assembler | idle; offered (yellow, with the contract number to find in the Contracts tab); rented: the game's own status |

Facts recorded for it: an export chest's, an export manifold's and a catapult's `held`, each force's
last power settlement (`storage.power.last`) and an order combinator's last reading (`last`)
([data-model.md](data-model.md)). The texts, diodes and alerts are checked by in-game tests, not by
eye: whether the game shows a custom status on hover for containers, storage tanks, combinators and
electric-energy-interfaces (the hub has `gui_mode = "none"`), whether `[item=…]` and `[fluid=…]`
render in it, and how the alerts look, are still to be checked on screen.

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

Every technology of the mod (`prototypes/technologies.lua`), vanilla science packs only. The
**space logistics** branch (#68) grows the delivery tiers in step with the vanilla tree: the cargo
shuttle once rocket fuel exists (blue science), then the catapult and, with production and utility science, the
teleporter.

```text
gb-galactic-bazaar (red) ── hub, export and import chests (orbital capsule delivery)
├── gb-power-trading (red, green) ── gb-power-trading-2 (+ blue)
├── gb-market-signals (red, green) ── gb-market-orders (red, green)
├── gb-telecommunications-1 (red, green) ── gb-telecommunications-2 (red, green, after advanced circuits)
├── gb-fluid-trading (red, green) ── fluid manifolds
├── gb-contracts (red, green) ── contract chest, incoming contract offers
│   ├── gb-capacity-rental (red, green, after automation 2) ── rental assembler
│   ├── [financial engineering branch]
│   │   └── gb-credit (red, green) ── loans
│   │       └── gb-overdraft-1 (red, green) ── overdraft limit 25 000
│   │           └── gb-overdraft-2 (red, green, blue, after chemical science) ── overdraft limit 100 000
│   └── gb-planetary-concessions (red, green) ── Planets tab, mining concessions
│       └── gb-outsourcing (red, green, blue) ── crafting slot bookings
└── [space logistics branch]
    └── gb-cargo-shuttle (red, green, blue) ── docking bay
        ├── gb-catapult (red, green, blue) ── electromagnetic catapult
        └── gb-teleporter (red, green, blue, purple, yellow) ── teleporter
```

The **financial engineering** branch (#98) opens borrowing, then raises the overdraft limit
([contracts.md](contracts.md#research)).

`tests/technologies.lua` checks, in vanilla and with Space Age, that each of these technologies uses
vanilla packs only, never needs fewer packs than a prerequisite, and unlocks recipes whose
ingredients its prerequisites (or the start of the game) already give.

Each building's section below gives its technology's prerequisites and cost. Research itself always
happens in the player's labs.

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
`supply(hub, shipments)` after payment, `delivers(hub)` true, false or nil to hold queued shipments; `freight.delivers(hub, tier)` says whether that tier's shipments can land now); an order a tier cannot supply, or whose queue is full, falls back to the next tier (`freight.tier_for(hub, name, units, kind)` gives the tier an order would ship by); `freight.tier(hub_unit_number)`
gives the hub's tier. An order is scheduled, charged and bounded with the tier at order time and each
shipment records it. Each tier launches on its own schedule and has its own queue bound
(`freight.queued(hub, tier)`), and unloading takes every landed shipment, so tiers never hold each
other back. The Market tab's status line shows the tier and its queue; a purchase from it is
refused (`tier-changed`, and the preview refreshed) when the tier changed since the tab showed it, or when the preview was computed for another hub; when no tier can take the quantity, the preview names the reason (`queue-full`, `not-tradeable`) and a purchase is refused with it. The rows below describe the capsule; the
other tiers differ only by their parameters.

| Payment | at order time: the market cost plus `fee_rate` (5 %) of it, scaled by the force's reputation (×0.5 to ×1.5, [contracts.md](contracts.md)), journaled as a `buy` and a `freight` entry; refused whole if the available funds (balance plus overdraft) do not cover both. Each capsule records the force that paid and the market price paid per unit |
| Capsules | an order is split into capsules of at most `capacity_stacks` (10) stacks of the item |
| Throughput | each hub launches one capsule every `launch_interval_ticks` (600, 10 s), so at most 1 stack a second per hub |
| Latency | a capsule lands `delay_ticks` (1800, 30 s) after its launch |
| Queue bound | at most `max_capsules` (20) capsules per hub, landed ones included; a larger order is refused (`queue-full`) |
| Unloading | every `freight.UNLOAD_INTERVAL` (60) ticks, landed capsules are unloaded into the hub's import chests (items) or import manifolds (fluids) of the hub's force, in landing order; what does not fit stays landed and is retried, without holding back the other landed capsules. Landing needs no power. A delivery only visits the chests of its hub (`storage.cargo.imports`), so its cost does not grow with the other cargo chests of the map. Each force is told by one alert per hub and pass how many of its shipments finished landing there, at most every 30 s per hub, the shipments of passes not told counted in the next alert ([notifications.md](notifications.md)) |
| Hub removed | the cargo still queued is sold back to the market for the force that paid (purchases, and a concession's ore, [planets.md](planets.md)); what the market refuses (item no longer tradeable, no liquidity) is refunded at the price paid (`freight-refund`). The fee is not refunded. Goods a counterparty ships free (incoming contract ingredients) are dropped |
| From a planet | goods shipped from an NPC planet (`freight.ship` with an origin) ride the orbital capsule schedule, land after the planet's transit delay and lose a share on the way ([planets.md](planets.md)) |
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
| Settlement | every `power.SETTLE_TICKS` (300, 5 s): per force, the export buffers are sold in one trade while electricity fetches at least `power.MIN_PRICE_RATIO` (0.5) × its base value (unsold energy stays), and the import buffers are refilled in one trade, scaled down to what the force can pay (its available funds, overdraft included) and the market can supply |
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
| Prototypes | copies of the constant combinator, tinted green (buy) and orange (sell); the virtual signals `gb-credits` and `gb-price-feed` |
| Recipe | 1 constant combinator + 5 electronic circuits, 2 s |
| Technology | `gb-market-signals` (after the Galactic Bazaar and circuit network; 100 × red and green) |
| Hub | attached like the power substations: nearest hub of the force within `price_signals.HUB_RANGE` (10 tiles), re-checked at each visit; silent (`enabled = false`) without a powered one |
| Signals | section 1: buy or sell price of every item in `storage.tradeable_items` and fluid in `storage.tradeable_fluids`, normal quality, in milli-credits; section 2: the balance on `gb-credits` in credits (negative on overdraft), read live at each visit, and the marker `gb-price-feed` = 1, always present so an order combinator can tell prices from orders even at a balance of 0 (`signals.price`, `signals.balance`: rounded, clamped to int32, zero values left out) |
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
| Budget | nothing is bought without a positive `gb-budget` signal; its value caps what the force spends through order combinators in the period (`storage.circuit_orders.spent`), within the available funds (balance plus overdraft); an input carrying `gb-credits` or `gb-price-feed` (a price combinator's balance or marker) is refused whole |
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
| 2 | `gb-telecommunications-2` (after level 1 and advanced circuits; 200 × red and green) | at most 2 s old | trend column and price history in the Market tab's item detail |

`telecom.quote(force_index, kind, name, period)` returns `{buy, sell, history}` from the force's
feed (`storage.forces[i].feed[key]`), quoted again when older than the period; the feed is cleared
whenever base values are rebuilt. Trade previews and executions always use live prices
(`market.quote`, `market.preview`). Below level 2 the trend column stays in place with empty cells
(hiding table cells would shift the others), and the item detail names the research that shows the
price history; the history appears once the item's market has two history points.

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
| Import | fluids bought from the Market tab or an order combinator travel by orbital capsule (`freight.order(…, "fluid")`), `freight.FLUID_UNITS_PER_STACK` (500) units taking the room of one stack, and land in the hub's import manifolds of its force at the fluid's default temperature (`manifold.deliver`, through the index `storage.manifold.imports`); without an import manifold that is empty or already holds the fluid, the order is refused (`no-import-manifold`) |
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
| Tier | the hub has the shuttle while its bays hold at least `FUEL_MJ_PER_SHIPMENT` (100 MJ, one rocket fuel); an order needing more shipments than the fuel covers, or finding the shuttle's queue full, goes by the next tier (orbital capsule), burning nothing. The Market tab plans the tier for the quantity typed and names it in the preview |
| Budget | a tier read of a hub with 5 bays among 50: 0.06 ms (2.1.24) — budget 0.1 ms |
| Burning | when a shuttle order is paid, `shipments × 100 MJ` are burnt from the bays in unit-number order: each bay's buffer first, then whole items in name order; what the last item gives beyond the need goes to the bay's buffer (lost if the bay is removed) |

## Teleporter (`gb-teleporter`)

Gives its hub the teleporter tier (#66, [ADR-0014](adr/0014-delivery-tier-per-hub.md)). Code:
`scripts/teleporter.lua`; prototype: `prototypes/teleporter.lua`.

| | |
|---|---|
| Prototype | an `electric-energy-interface` derived from the base one, tinted violet, drawing 20 MW (`secondary-input`, 40 MJ buffer, intake capped at 24 MW so a network that cannot keep up drains it; a fresh one reaches half its buffer in about 5 s) |
| Recipe | 100 processing units, 50 low density structures, 200 steel plates, 30 s |
| Technology | `gb-teleporter` (after the cargo shuttle, processing unit, low density structure, production and utility science; 500 × red, green, blue, purple and yellow) |
| Hub | attached like the other modules (`teleporter.HUB_RANGE`, 10 tiles), indexed per hub (`storage.teleporters.by_hub`) |
| Tier | the hub has the teleporter while one of its teleporters of its force holds at least `POWERED_SHARE` (half) of its buffer |
| Without power | while all the hub's teleporters are unpowered, its teleporter shipments already queued wait (`delivers`); once the hub has no teleporter at all (mined, attached elsewhere), they land, since they were paid for |

## Electromagnetic catapult (`gb-catapult`)

Bulk exports (#67). Code: `scripts/catapult.lua`; prototypes: `prototypes/catapult.lua`.

| | |
|---|---|
| Prototypes | a 48-slot chest derived from the steel chest, tinted red; under it, a hidden `gb-catapult-capacitor` (electric-energy-interface, not selectable, not blueprintable, not repairable, indestructible, no collision layers but the chest's footprint for pole coverage; `secondary-input`, 100 MJ buffer, intake capped at 30 MW) placed and removed by the script with the catapult; a catapult adopts a capacitor already under it (an area clone copies both) |
| Recipe | 100 steel plates, 30 advanced circuits, 10 accumulators, 20 electric engines, 20 s |
| Technology | `gb-catapult` (after the cargo shuttle and accumulators; 250 × red, green and blue) |
| Hub | attached like the other modules (`catapult.HUB_RANGE`, 10 tiles); shoots only through a powered hub of its force |
| Shot | every `catapult.PASS_TICKS` (6), catapults are visited in turn, up to `VISITS` (5), empty ones passed over, until one shoots: it shoots if its interval (`SHOT_TICKS`, 120) passed and its capacitor holds `SHOT_MJ` (50 MJ): it sells every plain stack while each unit fetches at least `cargo.DEFAULT_MIN_PRICE_RATIO` (0.5) × its base value, then spends the 50 MJ, only if something sold |
| Journal | entries merged per item and minute (`cargo.JOURNAL_MERGE_TICKS`), like export chests |
| Budget | a shot of 48 full stacks: 0.44–0.48 ms with 4 kinds, 0.65 ms with 48 different items (2.1.24); one shot per pass — budget 0.8 ms |
| Throughput | at most one shot per pass for the whole map (10 a second): with more than 20 loaded catapults, each waits about `n` × 0.1 s rather than 2 s |
| Lifecycle | a catapult whose capacitor is gone (another mod destroyed it) gets a new one at its next shot or on configuration change |

## Contract chest (`gb-contract-chest`)

Hands products over to incoming contracts (#76). Code: `scripts/incoming_contracts.lua`;
prototypes: `prototypes/contract_chest.lua`.

| | |
|---|---|
| Prototypes | a copy of the steel chest, tinted gold |
| Recipe | 1 steel chest, 5 electronic circuits |
| Technology | `gb-contracts` (after the Galactic Bazaar and logistic science; 100 × red and green) |
| Hub | attached like the other modules (`incoming.HUB_RANGE`, 10 tiles); hands nothing over without a hub, powered or not |
| Delivery | every second, the normal-quality items active incoming contracts still need leave the chest, oldest contract first ([contracts.md](contracts.md)) |

## Rental assembler (`gb-rental-assembler`)

Rented out to counterparties (#78, [ADR-0017](adr/0017-capacity-rental-with-installments.md)).
Code: `scripts/rental.lua`; prototypes: `prototypes/rental_assembler.lua`.

| | |
|---|---|
| Prototypes | a copy of assembling machine 2, tinted teal; no module slots, beacons may change only its speed, consumption and pollution; not operable and its circuit recipe setting off (the script sets both on build and on configuration change) |
| Recipe | 1 assembling machine 2, 10 electronic circuits |
| Technology | `gb-capacity-rental` (after contracts and automation 2; 150 × red and green) |
| Hub | attached like the other modules (`rental.HUB_RANGE`, 10 tiles); offered and served only through a hub of its force |
| Work | idle, no recipe; rented, the counterparty's recipe, ingredients and products, served every second ([contracts.md](contracts.md)); the force provides power |
