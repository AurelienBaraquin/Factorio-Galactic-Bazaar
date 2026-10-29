# ADR-0005 — Terminal modules attach to a trading hub within range

- **Status**: Accepted
- **Date**: 2026-10-29
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

The terminal is a central trading hub extended by modules (cargo, fluids, power, data…) unlocked by
research. Issue #17 asks how a module is attached to a hub. The mechanism must be obvious to the
player, work with blueprints and robots, cost little to compute, and leave the circuit network free
for trading orders (M2).

## Options considered

1. **Adjacency** — a module must touch the hub. Very visual, but it constrains layouts (a 2×2 hub
   has few free sides), breaks with rotations and different module sizes, and makes throughput
   designs around the hub cramped.
2. **Explicit link by wire** — the player connects each module with a circuit or dedicated wire.
   Flexible, but one more step per module, easy to forget, and it competes with circuit wires used
   for orders.
3. **Range, like a beacon or roboport** — a module works when a hub of the same force stands within
   a fixed distance on the same surface; the nearest hub wins.

## Decision

Option 3. A module belongs to the nearest powered `gb-hub` of its force on its surface whose
centre is within `HUB_RANGE` tiles of the module's centre (start value: 10). The link is resolved
when the module is built and re-resolved when hubs are built or removed, then kept in storage; a
module without a hub in range is idle and says so in its tooltip or interface.

## Consequences

- Positive: no extra player action; works with blueprints and robots; one `find_entities_filtered`
  per build event; circuit wires stay free for orders.
- Trade-offs accepted: the range is invisible until the interface shows it (a range overlay is a
  follow-up); two hubs close together split modules by distance only.
- Follow-up: implemented with the first module, the cargo module (#18).
