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

- there is exactly one state per existing force: created on `on_init`, on
  `on_force_created`, and reconciled on `on_configuration_changed` (missing states created,
  states of vanished forces dropped);
- when forces merge (`on_forces_merging`), the source state is folded into the destination and
  removed. A new field must define how two values combine, in `force_registry.merge`;
- nothing writes `storage` during `on_load`.

Personal data: none. Backups: `storage` lives inside the save file.
