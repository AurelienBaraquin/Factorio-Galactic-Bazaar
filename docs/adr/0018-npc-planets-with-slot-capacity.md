# ADR-0018 — NPC planets with a finite capacity in slots, reserved per force

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M5)
- **Supersedes**: none

## Context

M5 (outsourced production) needs places outside the map where a force can extract resources
(concessions, #85) and craft (foundries and assemblers, #86), with a finite capacity, a distance
for transit (#84), and, with Space Age, the real planets (#87). The brief asks for abstract NPC
planets first. Capacity must be finite and the economy is scoped by force (ADR-0001).

## Options considered

1. **Capacity as a flow that regenerates** (units per minute refilling a pool) — smooth, but a
   reservation for a time span has no clear meaning, and every read needs a lazy catch-up.
2. **Capacity in slots, reserved for a time span** — each specialty of a planet has a number of
   slots (a slot is one mining drill or one machine of crafting speed 1, abstracted); a reservation
   holds slots until its end tick, then they are free again. Simple, readable ("3 of 4 free").
3. **Capacity shared by all forces** — closer to a real galaxy, but one force could starve another,
   against ADR-0001's isolation; per-force capacity keeps every force's game its own.

## Decision

Option 2, per force. A catalog of NPC planets (`scripts/core/planets.lua`), the same for every
force, names each planet, its distance (in transit units, used by #84) and its specialties: a
resource it extracts (`resource`, an item) or a crafting category it serves (`crafting`), each with
a number of slots. The adapter keeps only the specialties whose item or category exists in the
loaded game. Each force's reservations live in its state (`storage.forces[i].reservations`); a
reservation names a planet, a specialty, a number of slots, an end tick and the contract it backs,
and is refused when the specialty has fewer free slots; the contract frees it early when it ends
first. Expired reservations are dropped when a reservation is made. On configuration change, the
reservations of a specialty no longer in the catalog are dropped and handed to the services that
back them, which withdraw those contracts like contracts whose goods vanished. Services that reserve
slots (#85, #86) are contracts of the model of ADR-0015; this ADR only fixes where capacity lives.
On a force merge the source's reservations carry over with its contracts.

## Consequences

- Positive: capacity is finite, readable and isolated per force; the model is pure and unit-tested;
  Space Age planets (#87) can join the same catalog.
- Trade-offs accepted: forces do not compete for NPC capacity; after a merge the destination may
  hold more slots than a specialty has until the source's reservations end.
- Follow-up: transit (#84), concessions (#85), foundries and assemblers (#86), Space Age planets
  (#87), research (#88).
