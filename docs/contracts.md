# Contracts

Exchanges that span time — a counterparty provides goods, the force hands goods back before a
deadline — share one model and lifecycle ([ADR-0015](adr/0015-one-contract-model.md)). The pure
engine is `scripts/core/contracts.lua`; the runtime side is `scripts/contracts.lua`. Market spot
trades are not contracts ([market.md](market.md)).

## Model

| Field | Meaning |
|---|---|
| `kind`, `counterparty` | what kind of contract (incoming, capacity…) and who it is with |
| `provides` | goods the counterparty delivers to the force: `{kind = "item"\|"fluid", name, quality, count}` (copied; count positive and finite) |
| `requires` | goods the force must hand over (at least one, each `kind/name@quality` key once) |
| `reward`, `deposit`, `penalty` | credits, each from 0 to 10¹²: paid on fulfilment; the guarantee held on acceptance is deposit plus penalty |
| `duration_ticks`, `accept_ticks` | time to fulfil once accepted; time the offer stands (both positive and finite) |
| `state` | `offered`, `active`, `fulfilled`, `failed`, `expired`, `declined` or `voided` |
| `delivered` | units handed over so far, per `kind/name` key |
| `offered_tick`, `accept_by`, `accepted_tick`, `due_tick`, `completed_tick`, `settled_tick`, `id` | lifecycle ticks, and the id, unique across all forces |

## Lifecycle

| From | Event | To | Money (through the force's account) | Reputation |
|---|---|---|---|---|
| — | `contracts.offer(force, spec)` | offered | — | — |
| offered | `contracts.accept(force, id)` (refused without the guarantee) | active | − deposit − penalty (`contract-guarantee`) | — |
| offered | `contracts.decline(force, id)` | declined | — | — |
| active | `contracts.deliver(force, id, key, count)`, until the deadline | active | — | — |
| active | every required unit delivered, at the next settlement (or on abandon) | fulfilled | + reward + deposit + penalty (`contract-fulfilled`) | +1 |
| active | deadline passed, at the next settlement, or `contracts.abandon` before completion | failed | nothing back: the guarantee is kept (`contract-failed`, amount 0) | −1 |
| offered | offer window passed | expired | — | — |
| active | `contracts.void(force, id)`: its goods no longer exist (a mod was removed) | voided | + deposit + penalty (`contract-voided`) | — |

A required amount within 10⁻⁶ of complete counts as delivered (fluid amounts are fractional).
Settlement runs every `contracts.SETTLE_TICKS` (60), contract ids in order. A settled contract
leaves the open contracts for the force's history (the newest `HISTORY_SIZE`, 20).

## Reputation

Each force has one score (`scripts/core/reputation.lua`, [ADR-0016](adr/0016-bounded-reputation-with-effects.md)),
moved by contract outcomes and kept within [`MIN`, `MAX`] = [−20, 20].

| Effect | Rule |
|---|---|
| Freight fees | every purchase's fee × `fee_factor` = 1 − `FEE_STEP` (0.025) × score: ×0.5 at 20, ×1.5 at −20 (`freight.preview`, `freight.order`) |
| Contract size | incoming offers aim at `TARGET_VALUE` × `contract_scale` = max(`MIN_SIZE` (0.5), 1 + `SIZE_STEP` (0.1) × score): ×3 at 20, ×0.5 from −5 down; the reward follows the batch |
| Force merge | the destination keeps its score less the source's debt (`reputation.merge`) |

The market window shows the score, with its effects in the tooltip ([terminal.md](terminal.md)).

## Incoming contracts

Counterparties offer each force to craft for them (#76): they provide a batch of a recipe's
ingredients, the force hands back its products. Code: `scripts/incoming_contracts.lua` (runtime),
`scripts/core/contract_offers.lua` (pricing, pure), `scripts/contracts_gui.lua` (window).

| | |
|---|---|
| Unlock | the `gb-contracts` technology, which also unlocks the contract chest ([terminal.md](terminal.md)) |
| Offers | every `incoming.OFFER_TICKS` (5 min), each force that researched it, owns a hub, has fewer than `MAX_OFFERS` (3) open offers and fewer than `MAX_CONTRACTS` (8) incoming contracts offered or active (the rows of the contracts window) gets one; the recipe and counterparty are drawn from the force's own deterministic random state |
| Recipes | enabled, not hidden, made in an assembling machine (`crafting` or `advanced-crafting`), item ingredients only and one sure item product in a whole amount (no range, probability or extra fraction), every good with a base value, products worth more than ingredients; sorted by name before the draw |
| Batch | enough crafts for the products to be worth `TARGET_VALUE` (1 000) credits × the force's contract scale (see Reputation), from 1 to `MAX_BATCH` (1 000) |
| Terms | reward = the value crafting adds (products' minus ingredients' base value), at most `LABOR_SHARE` (0.3) × products' value, so buying the products and selling the ingredients does not pay at base prices; deposit = `DEPOSIT_SHARE` (0.2) and penalty = `PENALTY_SHARE` (1) × ingredients' base value; at acceptance the penalty rises to what the ingredients would sell for on the force's market then, if more, so the guarantee always exceeds what the force receives; time = recipe time × batch × `TIME_FACTOR` (4) + `MARGIN_TICKS` (5 min); the offer stands `ACCEPT_TICKS` (5 min) |
| Acceptance | from the contracts window, at the hub it was opened from (within reach): every check of `contracts.can_accept` (still offered, not past its end, the guarantee in the balance) runs first; then the ingredients are shipped, free, by orbital capsule to that hub (`freight.ship`, all or nothing: refused without an import chest, or when the capsule queue would overflow), and only then is the guarantee taken |
| Delivery | every `COLLECT_TICKS` (60), each contract chest attached to a hub hands over the normal-quality items its force's active incoming contracts still need, oldest contract first; what no contract needs stays in the chest |

Deviation: ingredients always travel by orbital capsule (the counterparty's ship), whatever tier
the hub has. Capsules of a contract carry its id and a unit cost of 0: when the hub is removed they
are dropped, not sold back, since the force never paid for them. On configuration change, incoming
contracts whose goods no longer exist are withdrawn: offers declined, active contracts voided with
their guarantee back; their capsules are dropped without refund.

## Storage

`storage.forces[i].contracts = {open = {[id] = contract}, history = {contract...}}`,
`storage.forces[i].reputation` (a score, 0 to start, within [−20, 20]) and `storage.contract_next_id`, the next id —
see [data-model.md](data-model.md); `storage.incoming_contracts` holds the contract chests and each
force's random state, `storage.contracts_gui` the open contracts windows.
