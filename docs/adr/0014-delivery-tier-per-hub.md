# ADR-0014 — A hub delivers by the best logistics tier its buildings provide

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M3)
- **Supersedes**: none (extends ADR-0006)

## Context

ADR-0006 introduced delivery by logistics tier with one tier, the orbital capsule, as constants.
M3 adds a cargo shuttle with a docking bay (#65) and a teleporter (#66); issue #64 asks that tier
parameters be carried by the tier and that a hub choose the tier it has, the window showing it.

## Options considered

1. **One queue per tier per hub** — capsules, shuttles and teleporters in parallel. More throughput
   per hub, but several bounds to explain and a purchase split across tiers.
2. **The player picks the tier per order** — flexible, but an interface choice on every purchase
   and on every order combinator.
3. **The hub ships by its best available tier** — one queue per hub, each shipment scheduled with
   the tier the hub has when it is ordered.

## Decision

Option 3. Tiers are a table of parameters with a rank (`scripts/core/freight.lua`: capsule,
shuttle, teleporter). Modules that provide a tier register a provider with
`freight.register_tier_provider(fn)`: given a hub, it returns the tier its building gives that hub
now (attached, fuelled or powered), or nil. A hub ships by the highest-ranked tier any provider
returns, the orbital capsule otherwise. An order is scheduled, priced (fee) and bounded (queue) with
the tier at order time, and each shipment records its tier; shipments already queued keep their
schedule when the tier changes. The market window shows the tier and its queue bound.

## Consequences

- Positive: one queue and one bound per hub; a new tier is a parameter set plus a provider; order
  combinators and the window follow the hub's tier without change.
- Trade-offs accepted: a hub cannot use two tiers at once; dropping to a tier with a smaller queue
  bound (teleporter 10) refuses new orders until the queue drains.
- Follow-up: the shuttle's fuel per rotation (#65) and the teleporter's power (#66) are what their
  providers check.
