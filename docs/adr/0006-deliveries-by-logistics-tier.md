# ADR-0006 — Purchases are delivered by a logistics tier, with delay, bounded throughput and fees

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

Until now a purchase was stored in the hub's import chests in the same tick. The brief makes
logistics a constraint of its own: tiers, from the orbital capsule to the teleporter, bound the
throughput and the latency of trade. Issue #20 asks for the first tier: purchases arrive after a
delay, with a bounded throughput and a freight fee, from a delivery queue kept in `storage`. It
also asks whether Space Age cargo pods could be reused.

## Options considered

1. **A physical capsule item** crafted by the player and consumed per delivery. Gives logistics a
   material cost, but adds a production chain before the first trade and an inventory to the hub,
   and every later tier would need its own consumable.
2. **Space Age cargo pods** for the visual landing. Only exists with Space Age, which is optional
   and which the brief forbids depending on for graphics; the delivery logic would still be ours.
3. **An abstract tier**: a table of parameters (delay, capsule capacity, launch interval, fee, queue
   bound) applied to a per-hub queue of capsules. Later tiers are other parameter sets unlocked by
   research.

## Decision

Option 3. A purchase is paid at once (market cost plus a freight fee, both journaled) and split into
capsules of at most `capacity_stacks` stacks. Each hub launches one capsule every
`launch_interval_ticks`; a capsule lands `delay_ticks` after its launch and is unloaded into the
hub's import chests (since #63, fluids into its import manifolds). What does not fit stays in the
landed capsule and is retried without holding back the other landed capsules (amended 2026-10-30,
#63: a fluid whose manifold holds another fluid must not block the items behind it), so nothing is
lost while the chests are full. A hub holds at most `max_capsules` capsules in its queue. When a hub
disappears, the cargo still in its queue is sold back to the market for the force that paid; what
the market refuses is refunded at the price paid, as is cargo of an item that no longer exists. The
orbital capsule is the tier unlocked with the hub. The scheduling is pure (`scripts/core/freight.lua`);
the queue lives in `storage.freight`, keyed by hub (it is logistics, not economy state: the payer
force is recorded per capsule, ADR-0001).

## Consequences

- Positive: latency and throughput become a real constraint without a new production chain; later
  tiers only add a parameter set; the cost is one pass over the hubs with a queue per second, each
  delivery visiting only the import chests of its hub.
- Trade-offs accepted: no visual landing yet (graphics follow the visual identity, #48); a buyer
  pays the fee even when the chests are full, and waits.
- Follow-up: a physical consumable or a landing animation can be added on top of the same queue;
  cargo pods are not reused.
