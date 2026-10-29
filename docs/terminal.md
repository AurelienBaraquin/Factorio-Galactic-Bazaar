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

Its market interface comes with #19.

## Cargo module (`gb-export-chest`, `gb-import-chest`)

| | |
|---|---|
| Prototypes | `prototypes/cargo.lua`: two 48-slot containers derived from the steel chest, tinted orange (export) and green (import); icons add an up or down arrow |
| Recipe | 1 steel chest + 5 electronic circuits, 2 s; unlocked by the technology below |
| Attachment | the nearest registered hub of the same force within `cargo.HUB_RANGE` (10 tiles), resolved on build, again for nearby modules when a hub is built, and for a removed hub's modules ([ADR-0005](adr/0005-modules-attach-to-a-hub-in-range.md)) |
| Export | every `cargo.EXPORT_INTERVAL` (60) ticks, the next `cargo.EXPORT_BATCH` (20) export chests sell their normal-quality items, if their hub has power (`energy > 0`), while each unit still fetches at least `min_price_ratio` (default 0.5) × its base value. Items leave the chest only for an accepted sale |
| Import | `cargo.deliver(hub_unit_number, name, count)` inserts purchased items into that hub's import chests and returns how many fit; the orbital capsule (#20) will call it |
| Budget | 0.15 ms per export batch, measured with 500 export chests on 2.1.24 (about 0.0025 ms per tick on average) |

Quality items are not sold yet (#11). The export price floor is per chest; its interface comes with #19.

## Technologies

| Technology | Prerequisites | Cost | Unlocks |
|---|---|---|---|
| `gb-galactic-bazaar` (Galactic Bazaar) | Electronics, Steel processing | 75 × red science, 15 s each | trading hub, export chest, import chest |

Defined in `prototypes/technologies.lua`. The orbital capsule is added to it when it exists (#20). Research itself always happens in the player's labs.
