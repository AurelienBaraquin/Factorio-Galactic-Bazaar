# Contracts

Exchanges that span time — a counterparty provides goods, the force hands goods back before a
deadline — share one model and lifecycle ([ADR-0015](adr/0015-one-contract-model.md)). The pure
engine is `scripts/core/contracts.lua`; the runtime side is `scripts/contracts.lua`. Market spot
trades are not contracts ([market.md](market.md)).

## Model

| Field | Meaning |
|---|---|
| `kind`, `counterparty` | what kind of contract (incoming, capacity…) and who it is with |
| `provides` | goods the counterparty delivers to the force: `{kind = "item"\|"fluid", name, count}` |
| `requires` | goods the force must hand over (at least one) |
| `reward`, `deposit`, `penalty` | credits: paid on fulfilment; held on acceptance; owed on failure |
| `duration_ticks`, `accept_ticks` | time to fulfil once accepted; time the offer stands |
| `state` | `offered`, `active`, `fulfilled`, `failed` or `expired` |
| `delivered` | units handed over so far, per `kind/name` key |
| `offered_tick`, `accept_by`, `accepted_tick`, `due_tick`, `settled_tick`, `id` | lifecycle ticks and the id in the force's book |

## Lifecycle

| From | Event | To | Money (through the force's account) | Reputation |
|---|---|---|---|---|
| — | `contracts.offer(force, spec)` | offered | — | — |
| offered | `contracts.accept(force, id)` (refused without the deposit) | active | − deposit (`contract-deposit`) | — |
| active | `contracts.deliver(force, id, key, count)` | active | — | — |
| active | every required unit delivered, at the next settlement | fulfilled | + reward + deposit (`contract-fulfilled`) | +1 |
| active | deadline passed, at the next settlement, or `contracts.abandon` | failed | − penalty, at most the balance (`contract-failed`) | −1 |
| offered | offer window passed | expired | — | — |

Settlement runs every `contracts.SETTLE_TICKS` (60), contract ids in order. A settled contract
leaves the open contracts for the force's history (the newest `HISTORY_SIZE`, 20).

## Storage

`storage.forces[i].contracts = {next_id, open = {[id] = contract}, history = {contract...}}` and
`storage.forces[i].reputation` (a score, 0 to start) — see [data-model.md](data-model.md).
