# Data model: the mod's `storage`

What the mod persists in its `storage` table (saved with the map, restored on load), who writes
each part, and the invariants the game does not enforce. Read it before changing the shape of
`storage`: a change of shape needs a migration in the same change.

## `storage.forces`

`storage.forces[force_index]` — the economy state of one force ([ADR-0001](adr/0001-economy-state-scoped-by-force.md)).
Keyed by `LuaForce.index` (a number), never by the `LuaForce` object.

| Field | Type | Meaning |
|---|---|---|
| *(none yet)* | | each state is an empty table until the first economy field is added |

Invariants (kept by `scripts/forces.lua`, logic in `scripts/core/force_registry.lua`):

- there is exactly one state per existing force, **including the built-in `enemy` and
  `neutral` forces** (no special case; code that processes economies iterates the forces that
  own trading entities, not all states): created on `on_init` and `on_force_created`, and
  reconciled on `on_configuration_changed` as a self-heal for missed events (missing states
  created, states of vanished forces dropped);
- when forces merge (`on_forces_merging`), the source state is folded into the destination and
  removed. A new field must define how two values combine, in `force_registry.merge`;
- the source state is removed at `on_forces_merging`, while the source force still exists until
  the end of the tick: **readers must accept a missing state** (nil-check); only write paths call
  `force_registry.ensure`;
- nothing writes `storage` during `on_load`.

Personal data: none. Backups: `storage` lives inside the save file.
