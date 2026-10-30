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
to the force and the goods the force `requires` back (items or fluids with counts), a `reward`, a
`deposit` and a `penalty` in credits, how long the force has once it accepts (`duration_ticks`) and
how long the offer stands (`accept_ticks`). Its states are offered, active, then fulfilled, failed or
expired. The force pays the deposit on acceptance; when every required unit is delivered in time it
gets the reward and the deposit back and gains reputation; when the deadline passes first it loses
the deposit, pays the penalty (at most its balance, until debt exists with M6) and loses
reputation; an offer nobody accepts expires. The pure engine returns outcomes; the runtime
(`scripts/contracts.lua`) applies them through the force's account (ADR-0001) and settles open
contracts every second. Contracts live in each force's book; on a force merge, the merged force's
open contracts carry on in the destination's book and the reputations add up. Moving the goods
belongs to the feature that offers the contract.

## Consequences

- Positive: incoming contracts, capacity rental, outsourcing and credit share one lifecycle, one
  money path and one reputation rule; the engine is pure and fully unit-tested.
- Trade-offs accepted: contract terms are fixed at offer time; partial fulfilment earns nothing; a
  penalty larger than the balance is cut to it until debt exists.
- Follow-up: offers and goods movement (#76), reputation effects (#77), capacity rental (#78).
