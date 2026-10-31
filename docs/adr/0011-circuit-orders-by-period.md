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
emits nothing, players cannot open it, and signals pasted or blueprinted onto it are removed before
it is read) reads its red and green inputs every 10 s, the combinators of a force spread over ten
passes. Each positive normal-quality item signal buys that many units through the orbital capsule
(ADR-0006) of the nearest powered hub of its force in range (ADR-0005), in name order. **Nothing is
bought without a positive Budget signal** (`gb-budget`, a signal of its own): its value caps what
the force spends through all its order combinators in the period, never more than the balance, and
a zero or negative value pauses buying. An input that carries the Credits signal of price
combinators (ADR-0010) is refused whole: its item signals are prices, not orders. Amended by
[ADR-0020](0020-overdraft-and-debit-interest.md): the cap is the available funds (balance plus
overdraft), and an input carrying the Price feed marker that price combinators always emit is
refused too, since a balance of 0 emits no Credits signal. Untradeable,
negative and quality signals are ignored (fluid signals too until 2026-10-30: since #63 they buy
fluids into import manifolds). Recurring orders merge their journal entries per
item and minute.

## Consequences

- Positive: no order can repeat faster than every 10 s; spending per period is capped per force by
  an explicit signal, so a miswired network buys nothing; the capsule queue bound (20 per hub) stops
  runaway buying when the import chests fill up; a pass costs 0.09–0.13 ms with 50 combinators.
- Trade-offs accepted: an order waits up to 10 s; a signal left on keeps buying every period until
  its budget or the capsule queue stops it; goods in flight are not counted, so stock-keeping
  designs overshoot by what lands within 30 s; removing a hub sells its queued capsules back
  (ADR-0006); selling by circuit stays with export chests gated by
  inserters (price combinators give the information).
- Follow-up: electricity orders; fluids were added with the manifold module (#63).
