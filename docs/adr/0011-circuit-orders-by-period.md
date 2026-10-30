# ADR-0011 — Circuit orders are level-read once per period, within a budget

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M2)
- **Supersedes**: none

## Context

Issue #24 asks for an entity that receives signals and places orders, with safeguards: caps, and no
order repeated every tick by mistake, plus a documented example. Circuit signals are levels that
persist from tick to tick; an entity that acted on every tick would buy sixty times a second.

## Options considered

1. **Edge-triggered**: order when a signal appears or rises. Exact, but every design must pulse its
   signal, and a missed edge (hub unpowered at that tick) loses the order.
2. **Level-read per period**: read the input once every period and buy what it asks for, each
   time. A steady signal is a steady flow, which suits "keep this chest stocked" designs.
3. **Target stock**: the signal is a stock to reach, the mod counts goods in the import chests and
   capsules. Convenient, but it hides what is bought and duplicates what circuits already do.

## Decision

Option 2. An order combinator (a copy of the constant combinator that the script only reads: it
emits nothing and players cannot open it) reads its red and green inputs every 10 s. Each positive
normal-quality item signal buys that many units through the orbital capsule (ADR-0006) of the
nearest powered hub of its force in range (ADR-0005), in name order, each order only if it fits in
the period's budget: the value of the Credits signal on its input when present, otherwise a tenth of
the balance, never more than the balance. Untradeable, negative, fluid and quality signals are
ignored. Recurring orders merge their journal entries per item and minute.

## Consequences

- Positive: no order can repeat faster than every 10 s; spending per period is capped by default
  and adjustable by circuit; the capsule queue bound (20 per hub) stops runaway buying when the
  import chests fill up.
- Trade-offs accepted: an order waits up to 10 s; a signal left on keeps buying every period until
  its budget or the capsule queue stops it; selling by circuit stays with export chests gated by
  inserters (price combinators give the information).
- Follow-up: fluids and electricity once their modules exist.
