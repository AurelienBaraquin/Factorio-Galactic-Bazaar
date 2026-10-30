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
| `state` | `offered`, `active`, `fulfilled`, `failed`, `expired` or `declined` |
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

A required amount within 10⁻⁶ of complete counts as delivered (fluid amounts are fractional).
Settlement runs every `contracts.SETTLE_TICKS` (60), contract ids in order. A settled contract
leaves the open contracts for the force's history (the newest `HISTORY_SIZE`, 20).

## Storage

`storage.forces[i].contracts = {open = {[id] = contract}, history = {contract...}}`,
`storage.forces[i].reputation` (a score, 0 to start) and `storage.contract_next_id`, the next id —
see [data-model.md](data-model.md).
