# ADR-0015 — One contract model for every exchange that spans time

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M4)
- **Supersedes**: none

## Context

The brief and CLAUDE.md left open whether every exchange is one unified contract (inputs, outputs,
duration, counterparty, guarantees). M4 brings incoming contracts (#76), reputation (#77) and the
rental of machine capacity (#78); M5 (outsourced production) and M6 (credit) will need terms over
time too. Spot trades on the market (ADR-0003) are immediate and need none of this.

## Options considered

1. **One model per feature** — each feature its own record and lifecycle. Simple at first, but the
   deadline, deposit, penalty and reputation logic is written again for each.
2. **One contract model for exchanges that span time** — goods one way, goods the other, a deadline,
   money terms, one lifecycle, one book per force; spot trades stay outside.
3. **Everything is a contract, spot trades included** — uniform, but a spot trade would carry a
   lifecycle it never uses, and the market's hot path would pay for it.

## Decision

Option 2. A contract (`scripts/core/contracts.lua`) names a counterparty, the goods it `provides`
to the force and the goods the force `requires` back (items or fluids with counts and, for items, a
quality; each required key once), a `reward`, a `deposit` and a `penalty` in credits (each at most
10¹²), how long the force has once it accepts (`duration_ticks`) and how long the offer stands
(`accept_ticks`); goods lists are copied. Its states are offered, active, then fulfilled, failed,
expired or declined. On acceptance the force puts up a **guarantee of deposit plus penalty**, so a
failure always costs what it names (a force cannot dodge a penalty by spending its balance first);
when every required unit is delivered before the deadline it gets the guarantee back with the
reward and gains reputation; when the deadline passes first it loses the guarantee and reputation.
Deliveries after the deadline are refused. An offer nobody accepts expires; the force can decline
one. The pure engine returns outcomes; the runtime (`scripts/contracts.lua`) applies them through
the force's account (ADR-0001) and settles open contracts every second. Contract ids are unique
across all forces, so a reference to a contract (a shipment, a machine) survives a force merge, in
which the merged force's open contracts carry on in the destination's book and the reputations add
up. Moving the goods belongs to the feature that offers the contract.

## Consequences

- Positive: incoming contracts, capacity rental, outsourcing and credit share one lifecycle, one
  money path and one reputation rule; the engine is pure and fully unit-tested.
- Trade-offs accepted: contract terms are fixed at offer time; partial fulfilment earns nothing; a
  force must hold deposit plus penalty to accept; goods are items and fluids only, with no schedule
  (capacity rental, outsourcing and loans will extend the model by ADR).
- Follow-up: offers and goods movement (#76), reputation effects (#77), capacity rental (#78).
