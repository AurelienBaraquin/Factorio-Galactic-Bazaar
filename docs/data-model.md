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
| `journal` | array | last `account.JOURNAL_SIZE` (500, 100 up to 0.1.33) transactions, oldest first: the caller's fields (`tick`, `kind`, `key`, `quantity`, and `contract_kind` on contract entries, from 0.1.34) plus `amount`, the resulting `balance` and, from 0.1.34, the Statement tab's `category` (`statement.category`; older entries have none and are classified when read); a recurring transaction (`merge_ticks`, `first_tick`) is merged into the journal's entry of the same kind and key started less than `merge_ticks` before, which then holds the totals, its last tick and the balance after it, and moves to the end, so the journal stays in tick order. Retention: about 7 minutes of a base trading 40 goods automatically (one entry per good and minute) and buying twice a minute, far longer for a smaller one; the size was raised from 100 (under a minute and a half for that base) for the Statement tab, for about 50 KB of save per force when full. Cost of `account.apply` at 500 entries, measured under standalone Lua 5.2 (median of 5 runs over an hour of game time, one sale per good every second merged per minute plus a purchase every 2 s): with 40 goods 5.5 to 7.1 µs per call (5.1 at 100 entries); with 200 distinct goods 20 to 22 µs (10 to 12 at 100 entries), the extra being the search for the entry to merge into (it now reaches about 200 entries back, where a 100-entry journal had dropped it) and the shift of `table.remove` when an entry is dropped; 200 goods each sold every second is then about 4 ms per second of game time, 0.07 ms per tick on average (the in-game cost is several times that of standalone Lua, so measure in game before raising the size again) |
| `ledger` | table or nil | `{start_tick, total, minutes}`: what the Statement tab totals ([window.md](window.md#statement-tab)), kept apart from the journal so that totals cover every transaction whatever the journal still holds. `total` and each `minutes[m]` (`m` = tick ÷ 3600, rounded down: a minute of game time) are `{[category] = {income, spending, count}}`; `total` since `start_tick`, the minutes of the last `statement.LEDGER_MINUTES` (60) only, older ones dropped when a new minute begins. Written by `account.apply` through `statement.record` for every transaction, merged or not (`count` counts transactions, not journal entries), which adds 0.3 to 2.4 µs (about 1 µs) to each `account.apply` under standalone Lua 5.2 in the measurement above (with against without `statement.record`); created by the first transaction, so a save from 0.1.33 or older starts its ledger at its first transaction after the upgrade and needs no migration; folded together on merge (sums added, minute by minute, the earlier start kept) |
| `feed` | table or nil | `[key] = {tick, buy, sell, history}`: the prices this force last saw for each key read through `telecom.quote`, quoted again when older than its telecommunications period; `history` is the market entry's own table (live, not a copy); created on first read, cleared whenever base values are rebuilt |
| `contracts` | table | `{open = {[id] = contract}, history = {contract...}}`: the force's contract book, ids unique across all forces (`storage.contract_next_id`) ([contracts.md](contracts.md), ADR-0015) |
| `reservations` | list | `{planet, kind, name, slots, until_tick, contract}...`: the force's reservations of NPC planet slots and the contract each backs, ended ones dropped when a reservation is made, those of specialties gone from the catalog dropped on configuration change; carried over on merge ([planets.md](planets.md), ADR-0018) |
| `arrears` | number | credits a defaulted loan left owed, 0 to start (added on configuration change for saves made before loans): its unpaid installment and every one left; taken from the available funds every 60 ticks, down to the overdraft limit (what is left stays owed); while above 0 no loan is granted; added up on merge ([contracts.md](contracts.md), ADR-0021) |
| `insolvent_since` | tick or nil | the check at which the force became insolvent (balance beyond the overdraft limit during a period, or arrears above the available funds); nil once it recovers, or once it goes bankrupt at the first check `GRACE_TICKS` (10 min) or more after it whose period missed the recovery margin; on merge the earliest of the two ([contracts.md](contracts.md), ADR-0022) |
| `recovering_since` | tick or nil | while insolvent, the first check of the current run of checks that found the margin held; the force recovers once it has held for an interest period; cleared by a check that misses it, on recovery, bankruptcy and merge (ADR-0022) |
| `credit_ban_until` | tick or nil | after a bankruptcy, the earliest tick credit returns: until then, and until `bankruptcy_debt` is 0, the overdraft limit is 0 and loans are refused; cleared by the first check at or after it with no bankruptcy debt left; on merge the latest of the two (ADR-0022) |
| `bankruptcies` | number | bankruptcies so far, 0 to start (added on configuration change for older saves); each doubles the next credit ban, up to 8 hours; on merge the larger of the two (ADR-0022) |
| `bankruptcy_debt` | number | what the force owed at its bankruptcies (negative balance, arrears, loan installments left) plus a 25 % restructuring surcharge, not yet repaid, 0 to start (added on configuration change for older saves); earns no interest; every credit `account.apply` records goes to it first and every 60 ticks it takes a positive balance, never into the overdraft; added up on merge (ADR-0022) |
| `reputation` | number | the force's reputation score, from −20 to 20 (brought within them on configuration change for saves before 0.1.17): +1 per fulfilled contract, −1 per failed one; on merge only the source's debt follows ([contracts.md](contracts.md), ADR-0016) |
| `markets` | table | `[key] = {displacement, tick, rng, history}`: this force's market for each key read so far, `key` with `@<quality>` for an item quality other than normal ([market.md](market.md)); created on first read |

Account rules (`scripts/core/account.lua`): `account.apply(state, amount, entry)` is atomic — a
refused transaction (`invalid-amount`, `insufficient-funds`) changes nothing. A debit is refused
only when it would take the balance below `-account.overdraft_limit(state)` (10 000 credits; 25 000
or 100 000 at overdraft research levels 1 and 2, their extra halved from reputation −5 down; 0
during a credit ban after a bankruptcy, ADR-0022); a
credit is always accepted, and while the force owes a bankruptcy debt it goes to that debt first, as
far as the balance is positive (`account.repay_debt`, journaled as `bankruptcy-debt`). Code that checks funds before acting compares costs to
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
  removed: balances and arrears add up, journals are joined in tick order and trimmed, ledgers
  are folded together, the
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

## `storage.value_sources`

`storage.value_sources[key] = {recipe, cost, share, amount, inputs = {{key, amount, value}...}, tier}`
— for every key of `storage.base_values` whose value an offer of the production graph set, that
offer, before the multiplier ([pricing.md](pricing.md#value-sources)): the recipe name (or
`mine/`, `pump/`, `launch/`, `burn/` source), its cost in credits, its number of outputs, the
expected amount of the key per run, each input with its amount and the value it had, and the tier
that priced the key. Shared by all forces, read by the Market tab's item detail through
`pricing.value_source(key)`.

Invariants:

- rebuilt with `storage.base_values`, by `scripts/pricing.lua` only, never edited elsewhere; bounded
  by the number of keys with a value (216 in vanilla, 318 with Space Age, 2.1.24);
- no entry for a value fixed by an override; a key scaled by a factor has its first-pass source;
- a save whose base values were last built before 0.1.32 has none until its configuration change:
  readers accept a missing table (the item detail then says the breakdown is not available yet).

## `storage.hubs`

`storage.hubs[unit_number] = {entity = LuaEntity}` — every trading hub that exists
([terminal.md](terminal.md)). Written by `scripts/hubs.lua` on build events and
`on_object_destroyed`; invalid entries are dropped on `on_configuration_changed`. Read entities
with `hubs.get(unit_number)`, which checks `valid`.

## `storage.cargo`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub = hub unit_number|nil,
min_price_ratio, export_index, held}}, exports = {unit_number...}, cursor, imports = {[hub unit_number] =
{[unit_number] = true}}}` — every cargo chest, the round-robin order of export chests and the
import chests attached to each hub ([terminal.md](terminal.md)). Written by `scripts/cargo.lua`.
Invariants: `exports` lists exactly the export modules and `modules[exports[i]].export_index == i`
(removal swaps the last entry in); `imports` lists exactly the import modules by their `hub`,
kept in step by attachment and removal and rebuilt on `on_configuration_changed`; `hub` is a hint, re-checked before every use — a module only
works through a valid, powered hub of its own force; invalid entries are dropped and every module
re-attached on `on_configuration_changed`. `held` (export chests, absent before their first sale
attempt) says whether the last visit kept goods without selling any; it only feeds the chest's status.

## `storage.freight`

`{hubs = {[hub unit_number] = {launches = {[tier] = tick}, next_launch, capsules = {{force_index, kind, name, count, unit_cost, arrival, tier, contract, planet, loss}...}}}}`
— the delivery queue of each hub (`kind` "item" or "fluid"; nil in capsules queued before 0.1.9 means "item"; `tier` is the tier it ships by, absent before 0.1.10; `contract` is the id of the contract whose goods it carries (incoming ingredients, or goods shipped from an NPC planet, whose `arrival` includes the transit delay), nil for purchases; `unit_cost` is 0 for goods the force did not pay for, and for a concession's ore the charge per arriving unit, so that it is sold back like a purchase; `planet` and `loss`, on goods shipped from an NPC planet since 0.1.33, are the planet's name and the share of the good lost in transit, shown by the Logistics tab, absent from older capsules and from others) ([terminal.md](terminal.md), ADR-0006). Written by
`scripts/freight.lua`. Invariants: `capsules` is in ordering order (tiers land on their own schedules: every landed shipment is unloaded, none holds back another); `launches[tier]` is that tier's next free launch tick (`next_launch`, from before 0.1.10, is the capsule's) and holds at most
`max_capsules` entries per tier; `force_index` is the force that paid and `unit_cost` the market price it
paid per unit; `count` is what is still to unload. A
queue is dropped once empty and past its `next_launch`; the queue of a removed hub is sold back (contract capsules are dropped instead); on
`on_configuration_changed`, capsules of items that no longer exist are refunded and dropped, and
the queues of hubs that no longer exist are sold back.

## `storage.power`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub = hub unit_number|nil}}, last =
{[force_index] = {tick, export, import, export_held, import_short}}}` — every power substation, and
each force's last settlement with the MJ it sold and bought, whether export energy stayed unsold and
whether import energy lacked was not bought, for the substations' status ([terminal.md](terminal.md),
ADR-0009). Written by `scripts/power.lua` on build events, hub build and removal, force merge,
settlements and `on_object_destroyed`; invalid entries are dropped and every substation re-attached
on `on_configuration_changed`; `last` is created by whichever of init, settlement, force merge or
status read comes first in a save that lacks it (`power.settlements`), and a merged force's entry
goes on `on_forces_merged`. `hub` is a hint, re-checked at each settlement.

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

`{modules = {[unit_number] = {entity, hub, last}}, spent = {[force_index] = {period, credits}}}` —
every order combinator, and what each force has spent through them in the current 10 s period
([terminal.md](terminal.md), ADR-0011). `last` is the combinator's last reading, `{result, placed,
budget_left, reason, allowance}` (absent before it), which only feeds its status. Written by `scripts/circuit_orders.lua` on build events, hub build and removal, force
merge and `on_object_destroyed`; invalid entries are dropped and the others re-attached on
`on_configuration_changed`.

## `storage.manifold`

`{modules = {[unit_number] = {entity, kind = "export"|"import", hub, export_index, held}}, imports =
{[hub unit_number] = {[unit_number] = true}}, exports = {unit_number...}, cursor}` — every fluid
manifold, the import manifolds attached to each hub and the round-robin order of export manifolds
([terminal.md](terminal.md)). Written by `scripts/manifold.lua` on build events, hub build and
removal, force merge and `on_object_destroyed`; invalid entries are dropped, the indexes rebuilt and
the others re-attached on `on_configuration_changed`. `held` (export manifolds) says whether the last
visit kept fluid without selling any; it only feeds the manifold's status.

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

`{modules = {[unit_number] = {entity, capacitor, hub, next_shot, order_index, held}}, order =
{unit_number...}, cursor}` — every catapult, its hidden capacitor and the tick it may shoot again,
in visiting order; `held` (absent before its first shot attempt) says whether its last shot that
could fire sold nothing, for its status ([terminal.md](terminal.md)). Written by `scripts/catapult.lua` on build events,
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

## `storage.entity_status`

`{units = {unit_number...}, kinds = {kind name...}, index = {[unit_number] = position}, cursor,
counts = {[hub unit_number] = modules}, pending = {[hub unit_number] = modules}, members =
{[hub unit_number] = {[unit_number] = true}}, joining = {[hub unit_number] = {[unit_number] = true}},
facts = {[field] =
{[hub unit_number or force_index] = value}}, shown = {[unit_number] = {diode, label, alert} | false},
alerts = {[unit_number] = {alert, force_index, sprite, text}}}` — every building of the mod in
refresh order, the next one to refresh, each hub's modules of its force counted over the last cycle
and the current one, the modules attached to each hub (of its force) found by the last cycle (`members`) and the
current one (`joining`: by the passes, construction and listing), which the Logistics tab reads,
each entry re-checked on read, the costly reads of the current cycle (`tiers`, `fueled`, `needs`, `periods`),
the status written on each building (`false`: the game's own) and the alerts drawn on them (`sprite`
and `text` are render object ids) ([terminal.md](terminal.md#building-status)). Written by
`scripts/entity_status.lua` on its passes, build events and `on_object_destroyed`. Display state
only. Invariants: `units` and `kinds` are parallel arrays and `index[units[i]] == i` (removal swaps
the last entry in); `facts` and `pending` are emptied when a cycle ends, and `joining` becomes `members`; a listing (init,
configuration change) fills `joining` from the registries; a save from 0.1.32 or older, until its
configuration change, starts both empty. Every handler creates it
when a save lacks it; `on_configuration_changed` lists every building again, empties `shown` (every
status is written again) and drops the alerts of buildings no longer listed.

## `storage.bazaar_gui`

`storage.bazaar_gui[player_index] = {hub, tab, views, elements}` — the Galactic Bazaar window of a
player who has it open ([window.md](window.md)): the unit number of the hub it trades through (nil
while no hub of the force is within reach), the tab shown, each tab's state once it has been shown
(`views[name]`, owned by the tab: its `elements` and, for the Market tab, `{filter, matches, page,
selected, tier, tier_hub}`, `tier_hub` the hub the preview's tier was computed for, and in
`elements.info` the item detail's elements with the marks of what it shows, `{key, value, known,
buy, level}`, so that a refresh rewrites only what changed, [terminal.md](terminal.md#item-detail); for the
Logistics tab, `{hub, focus, hubs_page, shipments_page, modules_page, drawn, visible, modules}`: the
hub selected, the module the camera shows, each list's page, what each row last showed, how many
rows of each list are shown, and the selected hub's modules as last listed with their entities,
[terminal.md](terminal.md#logistics-tab); for the Statement tab, `{filter, period, page, shown}`,
`shown` the plain values its elements show, so that only changed ones are written) and references to the window's own elements (`{window, pane, tabs = {[name] =
{tab, content, index}}}`). Interface state only: no economy value lives here (ADR-0001). Written by
`scripts/bazaar_gui.lua` and the tabs (`scripts/overview_gui.lua`, `scripts/market_gui.lua` with
`scripts/item_detail_gui.lua`, `scripts/logistics_gui.lua`,
`scripts/contracts_gui.lua`, `scripts/planets_gui.lua`, `scripts/statement_gui.lua`); an entry exists only while the window is
open, is removed when the player leaves, changes force or is removed, and every window is closed
on `on_configuration_changed`, which also removes the tables of the separate windows saves made
before it had (`storage.players`, `storage.contracts_gui`, `storage.planets_gui`, up to 0.1.30) and
those windows. Events that run before that configuration change create the table if it is missing
([window.md](window.md#state)).

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

## `storage.notifications`

`storage.notifications[force_index] = {[kind .. "/" .. group] = {tick, period, pending}}` — each
force's throttle log: when an event of each kind and group was last told, that kind's period, and the
count of throttled events not yet told (`pending`, nil when none) ([notifications.md](notifications.md)).
Written by `scripts/notifications.lua` at each notification (entries whose period has passed and with
nothing pending are dropped then); created on `on_init`, `on_configuration_changed` and, for a save
that lacks it, at the first notification; a force's log on its first notification; the merged force's
log is folded into the destination's and dropped on `on_forces_merged`. Output state only: nothing
else reads it.

## `storage.tradeable_fluids`

Sorted names of the fluids that have a base value, rebuilt with them by `scripts/pricing.lua`; read
by the price signal combinators.

## `storage.tradeable_items`

Sorted names of every item with a base value — the Market tab's list. Rebuilt with
`storage.base_values` by `scripts/pricing.lua`, never edited elsewhere.

Personal data: none. Backups: `storage` lives inside the save file.
