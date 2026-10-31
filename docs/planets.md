# NPC planets

Places outside the map where a force will extract resources and have goods crafted (M5,
[ADR-0018](adr/0018-npc-planets-with-slot-capacity.md)). The pure model is
`scripts/core/planets.lua`; the runtime side is `scripts/planets.lua`, the window
`scripts/planets_gui.lua`, transit `scripts/core/transit.lua`, mining concessions
`scripts/concessions.lua`. Foundries and assemblers come with #86.

## Catalog

The same for every force (`planets.CATALOG`). A slot is one mining drill or one machine of crafting
speed 1, abstracted; distance is in transit units.

| Planet | Distance | Specialties (slots) |
|---|---|---|
| `ferrum-prime` | 1 | iron ore (4), copper ore (2), smelting (4) |
| `carbo` | 2 | coal (4), stone (3), smelting (2) |
| `fabrica-nova` | 2 | assembly `crafting` (4), advanced assembly `advanced-crafting` (2) |
| `uranos-deep` | 4 | uranium ore (2), chemistry (2) |

On `on_init` and `on_configuration_changed` the catalog is limited to the loaded game
(`planets.init`): a resource specialty is kept when its item exists, a crafting specialty when its
recipe category exists; a planet left without a specialty is dropped. The result is
`storage.planets`.

## Reservations

Each force reserves slots of a specialty until an end tick, for the contract they back
(`planets.reserve(force, planet, kind, name, slots, until_tick, contract_id)`); they are free again
from that tick, or earlier when the contract releases them (`planets.release(force, contract_id)`). A reservation is refused when the
specialty has fewer free slots (`no-capacity`), the planet or specialty is unknown
(`unknown-planet`, `unknown-specialty`), the slots are not a positive whole number
(`invalid-slots`) or the end is not a finite tick after now (`invalid-duration`). Ended reservations
are dropped when a reservation is made. On configuration change, reservations of a specialty no
longer in the catalog are dropped; `planets.init` returns them per force, for the services that
back them to withdraw their contracts. Capacity is per force: one force's reservations never take
another's slots. On a force merge, the source's reservations carry over (they back its contracts),
so the destination may hold more slots than a specialty has until they end.

## Transit

Goods a service ships from a planet to a hub (`planets.ship(force, hub, planet, goods, contract_id)`,
#84) go through freight (`freight.ship` with an origin, `scripts/freight.lua`): orbital capsules
with the capsule's schedule and queue bound, landing `transit.TICKS_PER_DISTANCE` (3 600 ticks, one
minute) per distance unit later. Each good loses a share on the way, drawn in (0, max loss) where max
loss = `LOSS_PER_DISTANCE` (2 %) × distance, at most `MAX_LOSS` (25 %); what arrives is rounded down
to whole units, and a good entirely lost is not shipped (a shipment of one unit is always lost). Each
good draws from the force's own state in `storage.planet_rng`, advanced at every draw, so every peer
computes the same loss and the moment a force ships changes nothing. Counts must be positive whole
numbers (`invalid-quantity`). `planets.transit_terms(planet)` gives the delay and the max loss — the
terms a service announces; the loss actually drawn is known only once shipped. Transit capsules
count in the hub's capsule queue bound while in flight, longer than a purchase's.

| Planet | Extra delay | Max loss |
|---|---|---|
| `ferrum-prime` | 1 min | 2 % |
| `carbo`, `fabrica-nova` | 2 min | 4 % |
| `uranos-deep` | 4 min | 8 % |

## Mining concessions

A force leases one slot of a resource a planet extracts (#85), from the planets window, at the hub
it was opened from (`concessions.lease(force, hub, planet, resource)`). The lease is a service
contract of kind `concession` ([contracts.md](contracts.md), [ADR-0019](adr/0019-service-contracts-with-a-charge.md)),
priced by `scripts/core/contract_offers.lua`:

| | |
|---|---|
| Term | `CONCESSION_TICKS` (30 min); the slot stays reserved for it ([ADR-0018](adr/0018-npc-planets-with-slot-capacity.md)) |
| Shipments | every `CONCESSION_PERIOD_TICKS` (5 min) on the lease's schedule — six periods, the last at the end of the term — `UNITS_PER_SLOT_MINUTE` (30) units a minute of the period, 150 per slot, shipped by transit to the lease's hub |
| Charge | the units shipped × their base value × `CONCESSION_PRICE` (1), fixed at the lease: between the market's sell and buy prices while the market is near its base value (a force that stores the ore can still sell it higher when the market drifts up); taken only for a period shipped: a period whose hub or import chest is gone is skipped before the balance is checked, one whose shipment is refused (a full queue) is not charged |
| Guarantee | one period's charge, held from the lease; back at the end of the term |
| Refusals | `unknown-specialty`, `no-capacity`, `not-tradeable` (no base value), `no-import-chest`, `too-many-contracts` (the contracts window already lists `contracts.MAX_LISTED`, 8), `insufficient-funds`; a lease is made whole or not at all |
| Hub removed | ore in flight was paid for: it is sold back for the force like a purchase (each capsule carries the price paid per arriving unit) |
| End | a charge the balance cannot cover, or an abandon from the contracts window, defaults the lease (guarantee kept, reputation −1); every `SWEEP_TICKS` (60), leases whose contract ended release their slot. On configuration change, a lease whose specialty is gone is voided (guarantee back), one whose ore is gone withdrawn like any listed contract |

Leases live in `storage.concessions`; on a force merge they follow their contracts.

## Window

A **Planets** button in the market window opens a read-only window: each planet's specialties, its
distance, its transit terms (extra delay in seconds, max loss), the slots free for the player's force out of the total and, for a resource, a **Lease** button (its tooltip gives
the terms; disabled without a free slot), refreshed every second
(`planets_gui.REFRESH_TICKS`). A lease re-checks that the window's hub is the player's force's and
within reach. Like the game's windows it becomes the player's opened window,
replacing the market window. It closes with its button, E or Esc, when the player leaves, changes
force or is removed, and on configuration change. A planet or category without a locale key shows
its internal name.
