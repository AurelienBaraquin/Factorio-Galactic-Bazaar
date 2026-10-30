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
`freight.register_tier_provider` at file scope (amended 2026-10-30 with #65): a provider names its
tier and answers, with no side effect (it is asked on every preview and refresh), whether a hub has
it now (`available`) and whether it can carry N shipments (`can_supply`, e.g. fuel); `supply`
consumes what the shipments of a paid order need; `delivers` (amended with #66) lets a provider with
a building at a hub hold its tier's shipments already queued (a teleporter without power; once the
hub has no teleporter at all they land, being paid for), while a provider without it never holds
them (a shuttle's fuel was paid with the order). A hub ships by the
highest-ranked available tier,
the orbital capsule otherwise; an order a tier cannot supply, or whose queue is full, falls back to
the next one, and the window plans and shows the tier for the quantity typed. An order is scheduled, priced (fee) and bounded with the tier at order time, and
each shipment records its tier. Each tier has its own launch schedule and its own queue bound in the
hub's single queue, and unloading takes every landed shipment, so a fast tier never waits behind a
slow one and a better tier never locks a hub out. The market window shows the tier and its queue;
a purchase from it is refused (`tier-changed`) if the tier changed since it was shown.

## Consequences

- Positive: one queue and one bound per hub; a new tier is a parameter set plus a provider; order
  combinators and the window follow the hub's tier without change.
- Trade-offs accepted: a hub uses one tier for new orders at a time; shipments queued on a slower
  tier keep their schedule after an upgrade.
- Follow-up: the catapult (#67) is an export path, not a delivery tier.
