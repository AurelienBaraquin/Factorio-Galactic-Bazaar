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
| Status | the force's balance, and whether the hub has power |
| List | tradeable items (`storage.tradeable_items`, built with the base values), filtered by the search text against internal names (every word must appear; case and separators ignored), `catalog.PAGE_SIZE` (15) rows per page: icon, name, buy price, sell price, trend (▲ ▼ – from the price history). Only the rows shown are read from the market (ADR-0004). The 15 rows are built once and updated in place, so a refresh never destroys a button a player is clicking (multiplayer latency) |
| Detail | for the selected item: a quantity field (whole number up to 10⁹) and a live preview of what buying and selling that quantity would cost and bring, market impact included. The preview is per unit exact; execution may trade fewer units — purchases are capped by import-chest space, sales by the plain units in the inventory — and the printed result gives the real numbers |
| Buy | needs a powered hub; capped by the free space of the hub's import chests of the same force (`cargo.import_capacity`), then debits the force and delivers into those chests at once (anything that did not fit is sold back and logged) — the orbital capsule (#20) will add delay and throughput |
| Sell | needs a powered hub; sells plain stacks of the item from the player's main inventory (`cargo.sell_stacks`, no price floor) |
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
| Attachment | the nearest registered hub of the same force within `cargo.HUB_RANGE` (10 tiles), resolved on build, for nearby modules when a hub is built, for a removed hub's modules, for every module on configuration change and force merge ([ADR-0005](adr/0005-modules-attach-to-a-hub-in-range.md)). When its hub has no power or belongs to another force, a module switches to the nearest powered hub of its force in range, if any |
| Export | every `cargo.EXPORT_INTERVAL` (6) ticks, the next `cargo.EXPORT_BATCH` (2) export chests — 20 chests a second — sell their plain stacks while each unit still fetches at least `min_price_ratio` (default 0.5) × its base value. Plain: normal quality, no extra data (equipment grid, inventory, blueprint, tags), full health, unused tools and ammunition. The sale is made first; the stack only shrinks for what was paid |
| Import | `cargo.deliver(hub_unit_number, name, count)` inserts purchased items into that hub's import chests and returns how many fit; `cargo.import_capacity(hub_unit_number, name)` says how many would fit |
| Budget | 0.09 ms per batch of 2 chests holding 4 item kinds each, measured on 2.1.24 with 164 chests in range (≈ 0.015 ms per tick on average); the in-game test logs it, since LuaProfiler cannot be compared from Lua |
| Throughput | each chest is visited every `n / 20` seconds for `n` export chests: with 2000 chests, every 100 s — fewer, fuller chests sell faster than many small ones |

Quality items are not sold yet (#11). The export price floor is per chest; its interface comes with #19.

## Technologies

| Technology | Prerequisites | Cost | Unlocks |
|---|---|---|---|
| `gb-galactic-bazaar` (Galactic Bazaar) | Electronics, Steel processing | 75 × red science, 15 s each | trading hub, export chest, import chest |

Defined in `prototypes/technologies.lua`. The orbital capsule is added to it when it exists (#20). Research itself always happens in the player's labs.
