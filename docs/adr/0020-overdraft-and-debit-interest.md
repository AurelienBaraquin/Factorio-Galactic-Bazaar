# ADR-0020 — Overdraft: spending below zero, with debit interest

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M6)
- **Supersedes**: none (amends the account rule of [ADR-0001](0001-economy-state-scoped-by-force.md)'s state: the balance was never negative)

## Context

Finance (milestone M6, #95) starts with credit: a force should be able to spend a little more than
it holds, at a cost, before loans (#96), research that raises the limit (#98) and bankruptcy (#97).
Until now the account refused any debit that took the balance below zero, and every feature that
checks funds before acting (freight orders, contract guarantees, concession deposits, service
charges, power imports, order combinator budgets) compared its cost to the balance itself, each in
its own words.

## Options considered

1. **A loan of a fixed amount on demand** — explicit, but it is #96's job and it does not let a
   purchase go through when the force is a few credits short.
2. **An overdraft limit on the account** — the account allows debits down to `-limit`; every check
   compares costs to one figure, the available funds (balance plus limit); a negative balance pays
   interest on a fixed period. Simple, automatic, and the hook later issues need.
3. **Interest accrued continuously in every transaction** — exact, but every debit and credit
   would have to know the time since the last one, and the journal would fill with fractions.

## Decision

Option 2. `scripts/core/account.lua` owns it:

- `account.overdraft_limit(state)` — `BASE_OVERDRAFT_LIMIT` (10 000 credits) for every force; a
  function of the force state so research (#98) can raise it without touching callers.
- `account.available(state)` — balance plus limit. Every check of a purchase, guarantee, deposit
  or charge uses it, never the balance alone; loans (#96) and later features call it too.
- `account.apply` refuses a debit that would take the balance below `-limit`
  (`insufficient-funds`); a credit is always accepted, even on a balance beyond the limit.
- `account.charge_interest(state, tick)` — on a negative balance, `INTEREST_RATE` (0.5 %) of the
  debt, journaled as `overdraft-interest` (key `account/overdraft`, entries merged over
  `INTEREST_MERGE_TICKS`, 10 minutes); nothing at or above zero. It bypasses the limit: interest
  may push the balance below `-limit`, which is bankruptcy's territory (#97); until then such a
  force simply cannot spend until it earns its way back.
- Every `INTEREST_TICKS` (3600, one minute), `force_registry.charge_interest` charges every force,
  in force index order, from a handler `control.lua` registers unconditionally.

The rate is high on purpose (about 35 % per hour compounded): an overdraft is short-term slack,
loans are the way to borrow for long. Nothing new is stored: the limit and the interest are derived
from the balance, so saves from 0.1.24 load without a migration.

## Consequences

- Positive: one place decides what a force can spend; purchases a few credits short go through;
  the limit is the hook for #98, the available funds the one for #96 and #97.
- Trade-offs accepted: interest is charged per whole minute on the balance at that tick, so a force
  that dips below zero between two ticks pays nothing; a force beyond the limit has no further
  consequence until bankruptcy exists. The `gb-credits` signal and the window show a negative
  balance.
- Follow-up: #96 (loans), #97 (bankruptcy, what happens beyond `-limit`), #98 (research raising the
  limit).
