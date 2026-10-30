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
| List | tradeable items (`storage.tradeable_items`, built with the base values), filtered by the search text against internal names (every word must appear; case and separators ignored), `catalog.PAGE_SIZE` (15) rows per page: icon, name, buy price, sell price, trend (▲ ▼ – from the price history), in fixed-width columns with prices right-aligned; a name too long for its column is clipped and shown whole in its tooltip. Only the rows shown are read from the market (ADR-0004). The 15 rows are built once and updated in place, so a refresh never destroys a button a player is clicking (multiplayer latency) |
| Detail | for the selected item: a quantity field (whole number up to 10⁹) and a live preview of what buying and selling that quantity would cost and bring, market impact included; the buying cost includes the freight fee. A purchase is exactly the preview; a sale may trade fewer units (the plain units in the inventory), and the printed result gives the real numbers |
| Buy | needs a powered hub with at least one import chest of its force; pays the market cost plus the freight fee at once and queues the units in orbital capsules (`freight.order`, see below); the printed result says when the last capsule lands |
| Sell | needs a powered hub; sells plain stacks of the item, of every quality, each at its quality's price, from the player's main inventory (`cargo.sell_stacks`, no price floor); the list shows normal-quality prices |
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
| Export | every `cargo.EXPORT_INTERVAL` (6) ticks, the next `cargo.EXPORT_BATCH` (2) export chests — 20 chests a second — sell their plain stacks while each unit still fetches at least `min_price_ratio` (default 0.5) × its base value. Plain (any quality, sold at its quality's price, [ADR-0008](adr/0008-quality-values-by-level.md)): no extra data (equipment grid, inventory, blueprint, tags), full health, unused tools and ammunition. The sale is made first; the stack only shrinks for what was paid |
| Import | `cargo.deliver(hub_unit_number, name, count)` inserts landed items into that hub's import chests and returns how many fit; `cargo.has_import(hub_unit_number)` says whether the hub has an import chest of its force |
| Budget | 0.09 ms per batch of 2 chests holding 4 item kinds each, measured on 2.1.24 with 164 chests in range (≈ 0.015 ms per tick on average); the in-game test logs it, since LuaProfiler cannot be compared from Lua |
| Throughput | each chest is visited every `n / 20` seconds for `n` export chests: with 2000 chests, every 100 s — fewer, fuller chests sell faster than many small ones |

The export price floor is per chest; its interface comes with #19.

## Technologies

| Technology | Prerequisites | Cost | Unlocks |
|---|---|---|---|
| `gb-galactic-bazaar` (Galactic Bazaar) | Electronics, Steel processing | 75 × red science, 15 s each | trading hub, export chest, import chest |

Defined in `prototypes/technologies.lua`. The orbital capsule is added to it when it exists (#20). Research itself always happens in the player's labs.

## Orbital capsule (delivery tier 1)

Purchases are delivered by logistics tier ([ADR-0006](adr/0006-deliveries-by-logistics-tier.md)).
The orbital capsule is the tier unlocked with the hub. Code: `scripts/freight.lua`, with the pure
scheduling in `scripts/core/freight.lua`; parameters in `freight.TIERS.capsule`.

| | |
|---|---|
| Payment | at order time: the market cost plus `fee_rate` (5 %) of it, journaled as a `buy` and a `freight` entry; refused whole if the balance does not cover both. Each capsule records the force that paid and the market price paid per unit |
| Capsules | an order is split into capsules of at most `capacity_stacks` (10) stacks of the item |
| Throughput | each hub launches one capsule every `launch_interval_ticks` (600, 10 s), so at most 1 stack a second per hub |
| Latency | a capsule lands `delay_ticks` (1800, 30 s) after its launch |
| Queue bound | at most `max_capsules` (20) capsules per hub, landed ones included; a larger order is refused (`queue-full`) |
| Unloading | every `freight.UNLOAD_INTERVAL` (60) ticks, landed capsules are unloaded into the hub's import chests of the hub's force, in landing order; what does not fit stays landed and is retried, holding back the capsules behind it. Landing needs no power. A delivery only visits the chests of its hub (`storage.cargo.imports`), so its cost does not grow with the other cargo chests of the map |
| Hub removed | the cargo still queued is sold back to the market for the force that paid; what the market refuses (item no longer tradeable, no liquidity) is refunded at the price paid (`freight-refund`). The fee is not refunded |
| Item removed | on a configuration change, capsules of items that no longer exist are refunded at the price paid and dropped |
| Force merge | capsules paid by the merged force are credited to the destination force |

Purchases are normal quality. Space Age cargo pods are not reused (ADR-0006).
