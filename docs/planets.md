# NPC planets

Places outside the map where a force will extract resources and have goods crafted (M5,
[ADR-0018](adr/0018-npc-planets-with-slot-capacity.md)). The pure model is
`scripts/core/planets.lua`; the runtime side is `scripts/planets.lua`, the window
`scripts/planets_gui.lua`. Services that use planets (transit, concessions, foundries) come with
#84–#86.

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

Each force reserves slots of a specialty until an end tick (`planets.reserve(force, planet, kind,
name, slots, until_tick)`); they are free again from that tick. A reservation is refused when the
specialty has fewer free slots (`no-capacity`), the planet or specialty is unknown
(`unknown-planet`, `unknown-specialty`), the slots are not a positive whole number
(`invalid-slots`) or the end is not a finite tick after now (`invalid-duration`). Ended reservations
are dropped when a reservation is made. Capacity is per force: one force's reservations never take
another's slots. On a force merge, the source's reservations carry over (they back its contracts),
so the destination may hold more slots than a specialty has until they end.

## Window

A **Planets** button in the market window opens a read-only window: each planet's specialties, its
distance and the slots free for the player's force out of the total, refreshed every second
(`planets_gui.REFRESH_TICKS`). It closes with its button, when the player leaves, changes force or
is removed, and on configuration change.
