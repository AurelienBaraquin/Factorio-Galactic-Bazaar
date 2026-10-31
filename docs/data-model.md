# Data model: the mod's `storage`

What the mod persists in its `storage` table (saved with the map, restored on load), who writes
each part, and the invariants the game does not enforce. Read it before changing the shape of
`storage`: a change of shape needs a migration in the same change.

## `storage.forces`

`storage.forces[force_index]` — the economy state of one force ([ADR-0001](adr/0001-economy-state-scoped-by-force.md)).
Keyed by `LuaForce.index` (a number), never by the `LuaForce` object.

| Field | Type | Meaning |
|---|---|---|
| `balance` | number | credits held by the force; negative when it spends on overdraft, down to `-account.overdraft_limit(state)` by spending, and below that only through interest ([ADR-0020](adr/0020-overdraft-and-debit-interest.md)) |
| `overdraft_low` | number | the lowest balance since the last interest charge, which interest is charged on; set to the balance at each charge, added up on merge, given to older saves by `account.init` ([ADR-0020](adr/0020-overdraft-and-debit-interest.md)) |
| `overdraft_level` | number or nil | the force's overdraft research level, 0 to `#account.OVERDRAFT_LEVEL_LIMITS`: the highest `gb-overdraft-n` researched, which sets its limit with the force's reputation (nil, as in saves made before the levels until their configuration change, reads as 0); written by `scripts/finance.lua` on research events, force resets, init, configuration change and before each interest charge; on merge the destination keeps its own, which its research sets ([contracts.md](contracts.md#research)) |
| `solvency_low` | number | the lowest balance since the last insolvency check, which decides insolvency and recovery; set to the balance at each check (every 60 ticks), added up on merge, given to older saves by `account.init` ([ADR-0022](adr/0022-insolvency-and-bankruptcy.md)) |
| `journal` | array | last `account.JOURNAL_SIZE` (100) transactions, oldest first: the caller's fields (`tick`, `kind`, …) plus `amount` and the resulting `balance`; a recurring transaction (`merge_ticks`, `first_tick`) is merged into the journal's entry of the same kind and key started less than `merge_ticks` before, which then holds the totals, its last tick and the balance after it, and moves to the end, so the journal stays in tick order |
| `feed` | table or nil | `[key] = {tick, buy, sell, history}`: the prices this force last saw for each key read through `telecom.quote`, quoted again when older than its telecommunications period; `history` is the market entry's own table (live, not a copy); created on first read, cleared whenever base values are rebuilt |
| `contracts` | table | `{open = {[id] = contract}, history = {contract...}}`: the force's contract book, ids unique across all forces (`storage.contract_next_id`) ([contracts.md](contracts.md), ADR-0015) |
| `reservations` | list | `{planet, kind, name, slots, until_tick, contract}...`: the force's reservations of NPC planet slots and the contract each backs, ended ones dropped when a reservation is made, those of specialties gone from the catalog dropped on configuration change; carried over on merge ([planets.md](planets.md), ADR-0018) |
| `arrears` | number | credits a defaulted loan left owed, 0 to start (added on configuration change for saves made before loans): its unpaid installment and every one left; taken from the available funds every 60 ticks, down to the overdraft limit (what is left stays owed); while above 0 no loan is granted; added up on merge ([contracts.md](contracts.md), ADR-0021) |
| `insolvent_since` | tick or nil | the check at which the force became insolvent (balance beyond the overdraft limit during a period, or arrears above the available funds); nil once it recovers or goes bankrupt, `GRACE_TICKS` (10 min) after it; on merge the earliest of the two ([contracts.md](contracts.md), ADR-0022) |
| `recovering_since` | tick or nil | while insolvent, the first check of the current run of checks that found the margin held; the force recovers once it has held for an interest period; cleared by a check that misses it, on recovery, bankruptcy and merge (ADR-0022) |
| `credit_ban_until` | tick or nil | after a bankruptcy, the earliest tick credit returns: until then, and until `bankruptcy_debt` is 0, the overdraft limit is 0 and loans are refused; cleared by the first check at or after it with no bankruptcy debt left; on merge the latest of the two (ADR-0022) |
| `bankruptcies` | number | bankruptcies so far, 0 to start (added on configuration change for older saves); each doubles the next credit ban, up to 8 hours; on merge the larger of the two (ADR-0022) |
| `bankruptcy_debt` | number | what the force owed at its bankruptcies (negative balance, arrears, loan installments left) and has not repaid, 0 to start (added on configuration change for older saves); earns no interest; every 60 ticks it takes what it can of the positive balance; added up on merge (ADR-0022) |
| `reputation` | number | the force's reputation score, from −20 to 20 (brought within them on configuration change for saves before 0.1.17): +1 per fulfilled contract, −1 per failed one; on merge only the source's debt follows ([contracts.md](contracts.md), ADR-0016) |
| `markets` | table | `[key] = {displacement, tick, rng, history}`: this force's market for each key read so far, `key` with `@<quality>` for an item quality other than normal ([market.md](market.md)); created on first read |

Account rules (`scripts/core/account.lua`): `account.apply(state, amount, entry)` is atomic — a
refused transaction (`invalid-amount`, `insufficient-funds`) changes nothing. A debit is refused
only when it would take the balance below `-account.overdraft_limit(state)` (10 000 credits; 25 000
or 100 000 at overdraft research levels 1 and 2, their extra halved from reputation −5 down; 0
during a credit ban after a bankruptcy, ADR-0022); a
credit is always accepted. Code that checks funds before acting compares costs to
`account.available(state)` (balance plus limit), never to the balance alone. Every
`account.INTEREST_TICKS` (one minute), `force_registry.charge_interest` charges, in force index
order, each force whose balance went below zero since the last charge `INTEREST_RATE` (0.5 %) of
its lowest balance (`overdraft_low`), the debt counted up to the limit, journaled as
`overdraft-interest` (merged over 10 minutes; under 0.005 credit it is waived); interest may take
the balance below the limit, by at most 0.5 % of the limit a minute.

Invariants (kept by `scripts/forces.lua`, logic in `scripts/core/force_registry.lua`):

- there is exactly one state per existing force, **including the built-in `enemy` and
  `neutral` forces** (no special case; code that processes economies iterates the forces that
  own trading entities, not all states): created on `on_init` and `on_force_created`, and
  reconciled on `on_configuration_changed` as a self-heal for missed events (missing states
  created, states of vanished forces dropped);
- when forces merge (`on_forces_merging`), the source state is folded into the destination and
  removed: balances and arrears add up, journals are joined in tick order and trimmed, the
  destination keeps its own markets and overdraft level (set by its research) and the stricter insolvency of the two (earliest insolvency,
  latest credit ban, most bankruptcies), and bankruptcy debts add up. A new field must
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

`{hubs = {[hub unit_number] = {launches = {[tier] = tick}, next_launch, capsules = {{force_index, kind, name, count, unit_cost, arrival, tier, contract}...}}}}`
— the delivery queue of each hub (`kind` "item" or "fluid"; nil in capsules queued before 0.1.9 means "item"; `tier` is the tier it ships by, absent before 0.1.10; `contract` is the id of the contract whose goods it carries (incoming ingredients, or goods shipped from an NPC planet, whose `arrival` includes the transit delay), nil for purchases; `unit_cost` is 0 for goods the force did not pay for, and for a concession's ore the charge per arriving unit, so that it is sold back like a purchase) ([terminal.md](terminal.md), ADR-0006). Written by
`scripts/freight.lua`. Invariants: `capsules` is in ordering order (tiers land on their own schedules: every landed shipment is unloaded, none holds back another); `launches[tier]` is that tier's next free launch tick (`next_launch`, from before 0.1.10, is the capsule's) and holds at most
`max_capsules` entries per tier; `force_index` is the force that paid and `unit_cost` the market price it
paid per unit; `count` is what is still to unload. A
queue is dropped once empty and past its `next_launch`; the queue of a removed hub is sold back (contract capsules are dropped instead); on
`on_configuration_changed`, capsules of items that no longer exist are refunded and dropped, and
the queues of hubs that no longer exist are sold back.

## `storage.power`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub = hub unit_number|nil}}}` —
every power substation ([terminal.md](terminal.md), ADR-0009). Written by `scripts/power.lua` on
build events, hub build and removal, force merge and `on_object_destroyed`; invalid entries are
dropped and every substation re-attached on `on_configuration_changed`. `hub` is a hint, re-checked
at each settlement.

## `storage.price_signals`

`{modules = {[unit_number] = {entity, side = "buy"|"sell", hub, order_index, written,
written_balance, force_index}}, order = {unit_number...}, cursor, snapshots = {[force_index] =
{tick, version, buy, sell}}, builders = {[force_index] = {tick, index, items, fluids, buy, sell}}}` —
the price signal combinators, their visiting order, each force's last complete snapshot of price
filters and the snapshot being built with the key lists it started from ([terminal.md](terminal.md),
ADR-0010). Written by `scripts/price_signals.lua`. Invariants: `order` lists exactly the modules,
once each, and `modules[order[i]].order_index == i`; `written` is the snapshot version and
`written_balance` the balance last written into the combinator. Snapshots and builders are dropped
on `on_configuration_changed`, and a merged force's on `on_forces_merged`.

## `storage.circuit_orders`

`{modules = {[unit_number] = {entity, hub}}, spent = {[force_index] = {period, credits}}}` — every
order combinator, and what each force has spent through them in the current 10 s period
([terminal.md](terminal.md), ADR-0011). Written by `scripts/circuit_orders.lua` on build events, hub build and removal, force
merge and `on_object_destroyed`; invalid entries are dropped and the others re-attached on
`on_configuration_changed`.

## `storage.manifold`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub, export_index}}, imports =
{[hub unit_number] = {[unit_number] = true}}, exports = {unit_number...}, cursor}` — every fluid
manifold, the import manifolds attached to each hub and the round-robin order of export manifolds
([terminal.md](terminal.md)). Written by `scripts/manifold.lua` on build events, hub build and
removal, force merge and `on_object_destroyed`; invalid entries are dropped, the indexes rebuilt and
the others re-attached on `on_configuration_changed`.

## `storage.docking_bays`

`{modules = {[unit_number] = {entity, hub, fuel_mj}}, by_hub = {[hub unit_number] = {[unit_number] =
true}}}` — every docking bay, the fuel it has burnt beyond what shipments needed, and the bays
attached to each hub ([terminal.md](terminal.md)). Written by `scripts/docking_bay.lua`
on build events, hub build and removal, force merge, orders and `on_object_destroyed`; invalid
entries are dropped and the others re-attached on `on_configuration_changed`.

## `storage.teleporters`

`{modules = {[unit_number] = {entity, hub}}, by_hub = {[hub unit_number] = {[unit_number] = true}}}`
— every teleporter and the teleporters attached to each hub ([terminal.md](terminal.md)). Written by
`scripts/teleporter.lua` (through `hubs.attach_indexed`) on build events, hub build and removal,
force merge and `on_object_destroyed`; invalid entries are dropped and the index rebuilt on
`on_configuration_changed`.

## `storage.catapults`

`{modules = {[unit_number] = {entity, capacitor, hub, next_shot, order_index}}, order =
{unit_number...}, cursor}` — every catapult, its hidden capacitor and the tick it may shoot again,
in visiting order ([terminal.md](terminal.md)). Written by `scripts/catapult.lua` on build events,
hub build and removal, force merge, shots and `on_object_destroyed` (which also removes the
capacitor). Invariants: `order` lists exactly the modules and `modules[order[i]].order_index == i`;
invalid entries are dropped and missing capacitors replaced on `on_configuration_changed`.

## `storage.incoming_contracts`

`{chests = {[unit_number] = {entity, hub}}, rng = {[force_index] = state}}` — every contract chest
and the hub it is attached to, and each force's random state for drawing offers
([contracts.md](contracts.md)). Written by `scripts/incoming_contracts.lua` on build events, hub
build and removal, force merge, `on_object_destroyed` and offer ticks. Invalid chests are dropped
on `on_configuration_changed`. A force's random state starts from its index.

## `storage.rentals`

`{machines = {[unit_number] = {entity, hub, contract, recipe, crafts, provided}}}` — every rental
assembler, the hub it is attached to and, while offered or rented, the contract id, its recipe, the
crafts promised and the units of each ingredient put in it so far ([contracts.md](contracts.md)).
Written by `scripts/rental.lua` on build events, hub build and removal, force merge,
`on_object_destroyed`, offer and service ticks. Invariants: a machine has a recipe only while its
contract is active (up to one service pass after it ends); `provided[name]` never exceeds what the contract provides. Invalid machines are
dropped on `on_configuration_changed`. Offers draw from `storage.incoming_contracts.rng`.

## `storage.contracts_gui`

`storage.contracts_gui[player_index] = {hub, elements}` — the contracts window of a player who has
it open: the hub it was opened from and references to its GUI elements (8 fixed rows). Interface
state only. Written by `scripts/contracts_gui.lua`; removed when the window closes, the player
leaves, changes force or is removed, and every window is closed on `on_configuration_changed`.

## `storage.planets`

`{{name, distance, real, specialties = {{kind, name, slots}...}}...}` — the NPC planet catalog
(abstract planets, then the real planets of the loaded game, `real` true) limited to the loaded
game, shared by all forces ([planets.md](planets.md)). Written by
`scripts/planets.lua` on `on_init` and `on_configuration_changed` only.

## `storage.concessions`

`storage.concessions[contract_id] = {force_index, hub, planet, item, units}` — every mining
concession or outsourcing booking whose contract may still be open, the item it ships and how many
units a period ([planets.md](planets.md)); leases saved by 0.1.21 (`resource`, `slots`) are
converted on configuration change. Written by
`scripts/concessions.lua` on lease, force merge and sweep (every 60 ticks a lease whose contract is
no longer active is removed and its slot released) and on configuration change.

## `storage.planet_rng`

`storage.planet_rng[force_index]` — each force's random state for transit losses
([planets.md](planets.md)), advanced at every draw, starting from its index. Written by
`scripts/planets.lua`; the merged force's entry is dropped on `on_forces_merged`.

## `storage.planets_gui`

`storage.planets_gui[player_index] = {elements}` — the planets window of a player who has it open,
with its rows (`{planet, kind, name, total, slots}`, `slots` the label element). Interface state
only. Written by `scripts/planets_gui.lua`; removed when the window closes, the player leaves,
changes force or is removed, and every window is closed on `on_configuration_changed`.

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
