# NPC planets

Places outside the map where a force will extract resources and have goods crafted (M5,
[ADR-0018](adr/0018-npc-planets-with-slot-capacity.md)). The pure model is
`scripts/core/planets.lua`; the runtime side is `scripts/planets.lua`, the Planets tab
`scripts/planets_gui.lua`, transit `scripts/core/transit.lua`, mining concessions and outsourced
production `scripts/concessions.lua`.

## Research

The outsourcing branch (#88, `prototypes/technologies.lua`, [terminal.md](terminal.md)):

| Technology | After | Cost | Unlocks |
|---|---|---|---|
| `gb-planetary-concessions` | `gb-contracts` | 200 × red, green | the Planets tab of the Galactic Bazaar window and mining concessions |
| `gb-outsourcing` | `gb-planetary-concessions`, chemical science | 300 × red, green, blue | booking crafting slots (the Book buttons stay disabled before, with a tooltip saying so) |

Their effects are script-side (`concessions.CONCESSION_TECHNOLOGY`, `OUTSOURCING_TECHNOLOGY`):
`lease` and `book` refuse with `not-researched` without them. Transit and reservations need no
research of their own.

## Catalog

The abstract planets are the same for every force (`planets.CATALOG`); real planets follow. A slot is one mining drill or one machine of crafting
speed 1, abstracted; distance is in transit units.

| Planet | Distance | Specialties (slots) |
|---|---|---|
| `ferrum-prime` | 1 | iron ore (4), copper ore (2), smelting (4) |
| `carbo` | 2 | coal (4), stone (3), smelting (2) |
| `fabrica-nova` | 2 | assembly `crafting` (4), advanced assembly `advanced-crafting` (2) |
| `uranos-deep` | 4 | uranium ore (2), chemistry (2) |

## Real planets

Every planet of the loaded game other than Nauvis — with Space Age, Vulcanus, Fulgora, Gleba and
Aquilo; with another mod, its planets — joins the catalog after the abstract ones (#87), named by the
game's own locale:

| | |
|---|---|
| Resources | the items mined from the resource entities its map generation places (fluids such as geysers or brine left out), `REAL_RESOURCE_SLOTS` (3) slots each |
| Crafting | its signature category: of the visible recipes whose surface conditions it meets and Nauvis does not, the category most of them belong to (ties to the first name), `REAL_CRAFTING_SLOTS` (2) slots. On configuration change a planet keeps the category it had while it still has such a recipe, so that another mod's recipes cannot flip it and void bookings on it |
| Bookings | a real planet crafts only the recipes whose surface conditions it meets (`wrong-planet` otherwise); an abstract planet crafts any recipe of its categories |
| Distance | its distance from Nauvis on the star map (polar coordinates `distance`, `orientation`), `DISTANCE_PER_UNIT` (10) per transit unit, at least 1 |

With Space Age 2.1.24 this gives:

| Planet | Distance | Specialties |
|---|---|---|
| Vulcanus | 2 | calcite, coal, tungsten ore (3 each), metallurgy (2) |
| Fulgora | 2 | scrap (3), electromagnetics (2) |
| Gleba | 2 | stone (3), organic (2) |
| Aquilo | 3 | cryogenics (2) |

Without Space Age nothing changes: the catalog holds the abstract planets only. A modded planet
named like an abstract planet is left out (the abstract one would shadow it). Without a `nauvis`
prototype (an overhaul), distances are measured from the centre of the star map and every
planet-only recipe counts. Real planets, their items and categories are named by their prototypes'
own localised names.

## Catalog filtering

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
count in the hub's capsule queue bound while in flight, longer than a purchase's. Each records the
planet and the share its good lost (`planet`, `loss`), which the Logistics tab shows
([terminal.md](terminal.md#logistics-tab)).

| Planet | Extra delay | Max loss |
|---|---|---|
| `ferrum-prime` | 1 min | 2 % |
| `carbo`, `fabrica-nova` | 2 min | 4 % |
| `uranos-deep` | 4 min | 8 % |

## Mining concessions

A force leases one slot of a resource a planet extracts (#85), from the Planets tab, at the hub
it was opened from (`concessions.lease(force, hub, planet, resource)`). The lease is a service
contract of kind `concession` ([contracts.md](contracts.md), [ADR-0019](adr/0019-service-contracts-with-a-charge.md)),
priced by `scripts/core/contract_offers.lua`:

| | |
|---|---|
| Term | `CONCESSION_TICKS` (30 min); the slot stays reserved for it ([ADR-0018](adr/0018-npc-planets-with-slot-capacity.md)) |
| Shipments | every `CONCESSION_PERIOD_TICKS` (5 min) on the lease's schedule — six periods, the last at the end of the term — `UNITS_PER_SLOT_MINUTE` (30) units a minute of the period, 150 per slot, shipped by transit to the lease's hub |
| Charge | the units shipped × their base value × `CONCESSION_PRICE` (1), fixed at the lease: between the market's sell and buy prices while the market is near its base value (a force that stores the ore can still sell it higher when the market drifts up); taken only for a period shipped: a period whose hub or import chest is gone is skipped before the funds are checked, one whose shipment is refused (a full queue) is not charged |
| Guarantee | one period's charge, held from the lease; back at the end of the term |
| Refusals | `not-researched`, `unknown-specialty`, `no-capacity`, `not-tradeable` (no base value), `no-import-chest`, `too-many-contracts` (the Contracts tab already lists `contracts.MAX_LISTED`, 8), `insufficient-funds`, `insolvent` (the force is insolvent, [contracts.md](contracts.md)); a lease is made whole or not at all |
| Hub removed | ore in flight was paid for: it is sold back for the force like a purchase (each capsule carries the price paid per arriving unit) |
| End | a charge the available funds (balance plus overdraft) cannot cover, or an abandon from the Contracts tab, defaults the lease (guarantee kept, reputation −1); every `SWEEP_TICKS` (60), leases whose contract ended release their slot. On configuration change, a lease whose specialty is gone is voided (guarantee back), one whose ore is gone withdrawn like any listed contract |

Leases live in `storage.concessions`; on a force merge they follow their contracts.

## Outsourced production

A force books one slot of a crafting category a planet serves (smelting, assembly, chemistry…) for
one of its own recipes (#86), from the Planets tab: pick the recipe on the row, then **Book**
(`concessions.book(force, hub, planet, category, recipe)`). It is a lease like a concession, of kind
`outsourcing`, on the same term, period, guarantee and refusals, with these differences:

| | |
|---|---|
| Recipe | one of the force's enabled, visible recipes, of that category, with one sure item product in a whole amount and a base value (`no-recipe`, `recipe-locked`, `wrong-category`, `not-craftable` otherwise) |
| Ingredients | the planet buys them itself: the force never ships nor pays for them, only for the products |
| Shipments | every period, the whole crafts one slot makes at crafting speed 1 in 5 minutes (`outsourcing_units`), times the product amount; a recipe taking longer than a period is refused (`too-slow`) |
| Charge | the products shipped × their base value × `OUTSOURCING_PRICE` (1.05): the market's buy price when balanced, without the freight fee — above a concession's, because a force can pick any valued product by the hundred and would otherwise resell it whenever the market drifts up |
| Terms shown | the Book button's tooltip gives the rule; the message printed on booking gives the units per period, the charge per shipment and the guarantee held |

A booking keeps its products and amount from the day it was made, even if a mod later changes the
recipe.

## Planets tab

The Planets tab of the Galactic Bazaar window ([window.md](window.md)), enabled once
`gb-planetary-concessions` is researched (before, it is disabled with a tooltip naming the
research): each planet's specialties, its distance, its transit terms (extra delay in seconds, max
loss), the slots free for the player's force out of the total and, for a resource, a **Lease**
button (its tooltip gives the terms; disabled without a free slot) or, for a crafting category, a
recipe picker and a **Book** button, refreshed every second while shown. It can be read anywhere; a
lease or booking goes to the window's hub, which must be the player's force's and within reach when
the button is pressed. A planet or category without a locale key shows its internal name. Each
column header and its cells have a tooltip with its rule (the distance's delay and loss per transit
unit and the loss cap, from `scripts/core/transit.lua`; slots per force), [window.md](window.md#explanations).
