# Data model: the mod's `storage`

What the mod persists in its `storage` table (saved with the map, restored on load), who writes
each part, and the invariants the game does not enforce. Read it before changing the shape of
`storage`: a change of shape needs a migration in the same change.

## `storage.forces`

`storage.forces[force_index]` — the economy state of one force ([ADR-0001](adr/0001-economy-state-scoped-by-force.md)).
Keyed by `LuaForce.index` (a number), never by the `LuaForce` object.

| Field | Type | Meaning |
|---|---|---|
| `balance` | number | credits held by the force; never negative |
| `journal` | array | last `account.JOURNAL_SIZE` (100) transactions, oldest first: the caller's fields (`tick`, `kind`, …) plus `amount` and the resulting `balance`; a recurring transaction (`merge_ticks`, `first_tick`) is merged into a recent entry of the same kind and key, which then holds the totals, its last tick and the balance after it |
| `markets` | table | `[key] = {displacement, tick, rng, history}`: this force's market for each key read so far, `key` with `@<quality>` for an item quality other than normal ([market.md](market.md)); created on first read |

Account rules (`scripts/core/account.lua`): `account.apply(state, amount, entry)` is atomic — a
refused transaction (`invalid-amount`, `insufficient-funds`) changes nothing.

Invariants (kept by `scripts/forces.lua`, logic in `scripts/core/force_registry.lua`):

- there is exactly one state per existing force, **including the built-in `enemy` and
  `neutral` forces** (no special case; code that processes economies iterates the forces that
  own trading entities, not all states): created on `on_init` and `on_force_created`, and
  reconciled on `on_configuration_changed` as a self-heal for missed events (missing states
  created, states of vanished forces dropped);
- when forces merge (`on_forces_merging`), the source state is folded into the destination and
  removed: balances add up, journals are joined in tick order and trimmed, the destination keeps
  its own markets. A new field must
  define how two values combine, in `force_registry.merge`;
- `force_registry.ensure` fills in any field a state lacks, so a save from an older version is
  upgraded on `on_configuration_changed` without a separate migration;
- the source state is removed at `on_forces_merging`, while the source force still exists until
  the end of the tick: **readers must accept a missing state** (nil-check); only write paths call
  `force_registry.ensure`;
- nothing writes `storage` during `on_load`.

## `storage.base_values`

`storage.base_values["item/<name>"]` and `storage.base_values["fluid/<name>"]` — base value in
credits of every tradeable item and fluid ([ADR-0002](adr/0002-base-value-from-the-production-graph.md)).
Shared by all forces: it depends only on prototypes. Written by `scripts/pricing.lua`, read with
`pricing.base_value(kind, name)`.

Invariants:

- rebuilt from the prototypes, the multiplier and the overrides on `on_init`, on every
  `on_configuration_changed` (mods, versions, startup settings or prototypes changed) and after
  each remote override call, never edited elsewhere;
- every value is finite and at least 10⁻⁶, multiplier included; a key with no value (`nil`) is not
  tradeable;
- whenever it is rebuilt, every `markets` entry of every force is rebased on the new values
  (`market.rebase_all`), and entries of keys that lost their value are dropped.

## `storage.quality_levels`

`storage.quality_levels[quality_name] = level` — `normal` (0) and every non-hidden quality
([pricing.md](pricing.md), ADR-0008). Rebuilt by `scripts/pricing.lua` with the base values. A
market key `item/<name>@<quality>` is tradeable only while its quality is listed here.

## `storage.value_overrides`

`storage.value_overrides["item/<name>"|"fluid/<name>"] = {value = credits}` or `{factor = f}` — base
value overrides set by other mods through the remote interface ([pricing.md](pricing.md),
[ADR-0007](adr/0007-value-overrides-as-fixed-sources.md)). Written by `scripts/value_overrides.lua` only
after its checks: keys are tradeable when set, exactly one of `value` (10⁻⁴ to 10¹²) or `factor`
(10⁻⁶ to 10⁶). Malformed entries are dropped at the next rebuild. Kept when a key stops being
tradeable (ignored until it comes back).

## `storage.hubs`

`storage.hubs[unit_number] = {entity = LuaEntity}` — every trading hub that exists
([terminal.md](terminal.md)). Written by `scripts/hubs.lua` on build events and
`on_object_destroyed`; invalid entries are dropped on `on_configuration_changed`. Read entities
with `hubs.get(unit_number)`, which checks `valid`.

## `storage.cargo`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub = hub unit_number|nil,
min_price_ratio, export_index}}, exports = {unit_number...}, cursor, imports = {[hub unit_number] =
{[unit_number] = true}}}` — every cargo chest, the round-robin order of export chests and the
import chests attached to each hub ([terminal.md](terminal.md)). Written by `scripts/cargo.lua`.
Invariants: `exports` lists exactly the export modules and `modules[exports[i]].export_index == i`
(removal swaps the last entry in); `imports` lists exactly the import modules by their `hub`,
kept in step by attachment and removal and rebuilt on `on_configuration_changed`; `hub` is a hint, re-checked before every use — a module only
works through a valid, powered hub of its own force; invalid entries are dropped and every module
re-attached on `on_configuration_changed`.

## `storage.freight`

`{hubs = {[hub unit_number] = {next_launch, capsules = {{force_index, name, count, unit_cost, arrival}...}}}}`
— the delivery queue of each hub ([terminal.md](terminal.md), ADR-0006). Written by
`scripts/freight.lua`. Invariants: `capsules` is in landing order and holds at most
`max_capsules` entries; `force_index` is the force that paid and `unit_cost` the market price it
paid per unit; `count` is what is still to unload. A
queue is dropped once empty and past its `next_launch`; the queue of a removed hub is sold back; on
`on_configuration_changed`, capsules of items that no longer exist are refunded and dropped, and
the queues of hubs that no longer exist are sold back.

## `storage.power`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub = hub unit_number|nil}}}` —
every power substation ([terminal.md](terminal.md), ADR-0009). Written by `scripts/power.lua` on
build events, hub build and removal, force merge and `on_object_destroyed`; invalid entries are
dropped and every substation re-attached on `on_configuration_changed`. `hub` is a hint, re-checked
at each settlement.

## `storage.price_signals`

`{modules = {[unit_number] = {entity, side = "buy"|"sell", hub, order_index, written, force_index}},
order = {unit_number...}, cursor, snapshots = {[force_index] = {tick, version, buy, sell}},
builders = {[force_index] = {tick, index, buy, sell}}}` — the price signal combinators, their
visiting order, each force's last complete snapshot of filters and the snapshot being built
([terminal.md](terminal.md), ADR-0010). Written by `scripts/price_signals.lua`. Invariants: `order`
lists exactly the modules and `modules[order[i]].order_index == i`; `written` is the snapshot
version last written into the combinator. Snapshots and builders are dropped on
`on_configuration_changed`.

## `storage.players`

`storage.players[player_index] = {hub, filter, matches, page, selected, elements}` — the market
window of a player who has it open ([terminal.md](terminal.md)): the hub it trades through, the
search text and its cached results, the page, the selected item and references to its GUI elements
(including the 15 fixed rows). Interface state only: no economy
value lives here (ADR-0001). Written by `scripts/market_gui.lua`; an entry exists only while the
window is open, is removed when the player leaves, changes force or is removed, and every window
is closed on `on_configuration_changed`.

## `storage.tradeable_fluids`

Sorted names of the fluids that have a base value, rebuilt with them by `scripts/pricing.lua`; read
by the price signal combinators.

## `storage.tradeable_items`

Sorted names of every item with a base value — the market window's list. Rebuilt with
`storage.base_values` by `scripts/pricing.lua`, never edited elsewhere.

Personal data: none. Backups: `storage` lives inside the save file.
