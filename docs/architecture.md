# Architecture

How the code is organised and how its parts fit together. The *why* of each choice is in
[`adr/`](adr/); this page describes **what exists now**.

This document is kept true by whoever changes the structure, in the same change. Every path it
cites must exist (checked by `tools/check-docs.mjs`). Sections are added when the thing they
describe exists, not before.

## 1. Layout

The repository root is the mod folder: Factorio reads `info.json`, the stage files and
`locale/` directly from it. No gameplay code exists yet.

```
info.json       mod manifest: name, version, factorio_version 2.1, dependencies (Space Age optional)
settings.lua    settings stage: the startup setting of the global value multiplier
data.lua        prototype stage entry point: requires one file per prototype family
prototypes/     prototype definitions (trading hub, cargo chests, technologies, custom inputs)
control.lua     runtime stage entry point: registers every event handler
locale/         in-game text, one folder per language (en, fr)
scripts/        runtime adapters between the game API and the pure logic
scripts/core/   pure Lua logic, no game API (checked by luacheck, unit-tested)
changelog.txt   release notes in the strict format the game parses
spec/           busted unit tests of scripts/core/
tests/          FactorioTest in-game tests of scripts/
package.json    development tooling only (FactorioTest CLI)
tools/          repository tooling: Lua toolchain setup, packaging and deploy, documentation check
docs/           brief, architecture, ADRs and the documentation index
.assistant/     decisions log and lessons for AI agents
.github/        issue and pull request templates, CI workflows
.githooks/      git hooks (commit message rules, documentation check)
.claude/        Claude Code project settings, hooks, Factorio modding skills and agents
```

Only the first nine entries ship in the mod: `.gitattributes` marks everything else
`export-ignore`, and `tools/build.py` uses that list for both the zip and play-test deploys.

## 2. Conventions in place

- Economy state is keyed by force in `storage` ([ADR-0001](adr/0001-economy-state-scoped-by-force.md));
  shape and invariants in [data-model.md](data-model.md).
- Two layers: `scripts/core/` is pure Lua that takes and returns plain tables (unit-tested with
  busted, game API forbidden by luacheck); `scripts/` adapts it to the game (reads the API,
  calls core, writes `storage`).
- `control.lua` is the only file that registers event handlers, because Factorio keeps one
  handler per event per mod; modules expose handler functions and `control.lua` composes them.

## 3. Flows

- **Init and configuration change**: `control.lua` calls `forces.init` (one state per force, with
  its account), `value_overrides.rebuild` (base values from the prototypes, the multiplier and the
  overrides, then every market rebased on them, [pricing.md](pricing.md)),
  `hubs.init` (drops hubs that no longer exist), `cargo.init` (drops chests that no longer
  exist, re-attaches the others) and `freight.init` (settles the queues of hubs that no longer
  exist).
- **Building events**: `control.lua` routes every way an entity can appear (filtered to the mod's
  buildings) to `hubs.on_built`, `power.on_built` for a substation, `price_signals.on_built` for a price combinator, `circuit_orders.on_built` for an order combinator, `manifold.on_built` for a fluid manifold, `docking_bay.on_built` for a docking bay, `teleporter.on_built` for a teleporter, `catapult.on_built` for a catapult, `incoming.on_built` for a contract chest, `rental.on_built` for a rental assembler, or `cargo.on_built` for a chest; a new hub also re-attaches nearby
  modules. `on_object_destroyed` forgets a hub (its modules look for another) or a chest
  ([terminal.md](terminal.md)).
- **Export**: `script.on_nth_tick(cargo.EXPORT_INTERVAL)` sells the next batch of export chests.
- **Price signals**: every `price_signals.PASS_TICKS`, the snapshots being built advance by a chunk
  of quotes and the next combinator is rewritten if its force's snapshot changed
  ([terminal.md](terminal.md)).
- **Circuit orders**: every `circuit_orders.ORDER_TICKS`, each order combinator reads its inputs
  and places capsule orders within its budget ([terminal.md](terminal.md)).
- **Fluids**: every `manifold.SELL_TICKS`, export manifolds sell their fluid; bought fluids land in
  import manifolds by capsule ([terminal.md](terminal.md)).
- **Catapults**: every `catapult.PASS_TICKS`, the next catapult shoots if ready ([terminal.md](terminal.md)).
- **Contracts**: every `contracts.SETTLE_TICKS`, each force's open contracts whose time has come
  are settled through its account ([contracts.md](contracts.md)).
- **Overdraft interest**: every `forces.INTEREST_TICKS` (one minute), `forces.on_interest_tick`
  charges interest to every force whose balance is negative; purchases, guarantees and charges are
  checked against the available funds, balance plus overdraft limit
  ([data-model.md](data-model.md), [ADR-0020](adr/0020-overdraft-and-debit-interest.md)).
- **Financial engineering research**: `finance.on_research_changed` (research finished or
  reversed) and `finance.on_force_event` (force reset, technology effects reset) record a force's
  overdraft research level in its state, which `account.overdraft_limit` reads with the force's
  reputation; `finance.init` does it for every force on init, configuration change and at the start
  of each interest tick ([contracts.md](contracts.md#research)).
- **Incoming contracts**: every `incoming.OFFER_TICKS`, forces that researched contracts get an
  offer; every `incoming.COLLECT_TICKS`, contract chests hand over what active contracts need ([contracts.md](contracts.md)).
- **Planets**: on init and configuration change, `planets.init` limits the NPC planet catalog to the
  loaded game ([planets.md](planets.md)).
- **Loans**: the Contracts tab's credit line borrows a tier (`loans.borrow`: a loan contract
  offered and accepted at once, its principal paid); its installments run in the contract
  settlement with no service; every `loans.COLLECT_TICKS`, arrears a defaulted loan left are taken
  from each force's available funds, down to its overdraft limit ([contracts.md](contracts.md)).
- **Insolvency**: every `insolvency.CHECK_TICKS`, right after the arrears collection,
  `insolvency.on_check_tick` checks every force in index order; it becomes insolvent, recovers,
  goes bankrupt (contracts ended, everything owed plus a surcharge frozen into a bankruptcy debt,
  reputation to −20, credit refused until the ban has passed and that debt is repaid) or gets its
  credit back, and is told so; while a bankruptcy debt is owed, `account.apply` sends every credit
  to it first; `contracts.can_accept` and the loans refuse an insolvent
  force ([contracts.md](contracts.md), [ADR-0022](adr/0022-insolvency-and-bankruptcy.md)).
- **Concessions and outsourcing**: their periods run in the contract settlement (the service
  registered for each kind checks it can ship, ships the ore or the products, then the charge is
  taken); every `concessions.SWEEP_TICKS`, ended leases release their slot ([planets.md](planets.md)).
- **Machine rental**: every `rental.OFFER_TICKS`, idle rental assemblers are offered; every
  `rental.SERVICE_TICKS`, rented ones are served and released ones cleared; a settings paste onto
  one is undone at once ([contracts.md](contracts.md)).
- **Notifications**: features tell players what happened through `notifications.notify` (offers,
  contract settlement, loan defaults, deliveries landed, insolvency); it throttles per force, kind and
  group, then shows each connected player whose category setting is on an alert and, for most kinds,
  a chat line ([notifications.md](notifications.md)).
- **Power**: every `power.SETTLE_TICKS`, each force's export substations are sold and its import
  substations refilled through the market ([terminal.md](terminal.md)).
- **Delivery**: a purchase is paid and queued in capsules (`freight.order`); every
  `freight.UNLOAD_INTERVAL` ticks landed capsules are unloaded into import chests; a removed hub's
  queue is sold back ([terminal.md](terminal.md)).
- **Galactic Bazaar window** ([window.md](window.md), [ADR-0023](adr/0023-central-window.md)): the
  tab modules (`overview_gui`, `market_gui`, `logistics_gui`, `contracts_gui`, `planets_gui`) register with
  `scripts/bazaar_gui.lua` when `control.lua` requires them (the Market tab builds the selected
  item's detail with `scripts/item_detail_gui.lua`, its figures computed by
  `scripts/core/item_detail.lua`); the `gb-toggle-bazaar` input and the mod
  button open or close it, the `gb-open-hub` input opens it on the Market tab bound to the clicked
  hub; every GUI input event (`bazaar_gui.GUI_EVENTS`: click, text, confirmed, element, checkbox,
  selection, value) dispatches on the `gb_action` tag of this mod's elements to the window or the
  tab owning that action, `on_gui_selected_tab_changed` builds and
  shows a tab; `on_gui_closed` and the player events (left, changed force, removed) close it; a
  destroyed hub is unbound; every `bazaar_gui.SLOT_TICKS` the shown tab of the windows whose slot
  comes up is refreshed; the research events, `on_player_created`, the force resets and, as a
  self-heal, every `forces.INTEREST_TICKS`, show or hide the mod button.
- **Building status**: every `entity_status.PASS_TICKS`, the next buildings of the mod are given a
  custom status and, while stopped (no hub, no power), a rendered alert; the buildings are listed as
  they are built and destroyed, and a building is also refreshed when built
  ([terminal.md](terminal.md#building-status)). The export, catapult, settlement and order passes
  record what their last visit did for it.
- **Periodic handlers**: Factorio keeps one handler per tick interval, so `control.lua` groups
  handlers by interval (`every(ticks, handler)`) and registers one composed handler per interval —
  the export and the window refresh both run every 6 ticks.
- **Force events**: creation and merging update `storage.forces` ([data-model.md](data-model.md))
  and move queued capsules to the destination force; after a merge, every cargo chest is
  re-attached.
- **Remote interface**: `control.lua` registers `galactic-bazaar` (`value_overrides.REMOTE`); an
  override call checks its input, stores it, rebuilds the base values and rebases the markets
  ([pricing.md](pricing.md)).
- **Market feed**: the Market tab's list and the price combinators read prices through
  `telecom.quote` or on the force's telecommunications period, so what a force sees is at most that
  old; trades always use live prices ([terminal.md](terminal.md), ADR-0012).
- **Market**: `scripts/market.lua` quotes and executes trades for a force, advancing each key's
  NPC market lazily when read ([market.md](market.md)); export chests sell through it.

## 4. Decisions

See [`adr/`](adr/) for the recorded decisions and `../.assistant/decisions-log.md` for smaller
ones.
