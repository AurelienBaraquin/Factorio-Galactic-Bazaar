# ADR-0020 — Overdraft: spending below zero, with debit interest

- **Status**: Accepted; amended 2026-10-31 by #98 (research levels of the limit, see "Amendment" below)
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M6)
- **Supersedes**: none. Amends [ADR-0001](0001-economy-state-scoped-by-force.md)'s account (the balance was never negative), [ADR-0010](0010-price-signals-from-script-written-combinators.md) (price combinators also emit a Price feed marker), [ADR-0011](0011-circuit-orders-by-period.md) ("never more than the balance") and [ADR-0019](0019-service-contracts-with-a-charge.md) ("a charge the balance cannot cover")

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
- `account.charge_interest(state, tick)` — `INTEREST_RATE` (0.5 %) of the deepest debt of the
  period: the lowest balance since the last charge (`overdraft_low`, kept by every transaction), so
  borrowing just after a charge and repaying before the next still pays. The debt is counted up to
  the limit, so a debt beyond it grows linearly (at most 50 credits a minute), not exponentially,
  and stays finite however long it is left. Journaled as `overdraft-interest` (key
  `account/overdraft`, entries merged over `INTEREST_MERGE_TICKS`, 10 minutes); nothing when the
  balance never went below zero, and a charge under `INTEREST_MIN` (0.005) is waived. It bypasses
  the limit: interest may push the balance below `-limit`, which is bankruptcy's territory (#97);
  until then such a force simply cannot spend until it earns its way back. On force merge the
  lowest balances add up.
- Every `INTEREST_TICKS` (3600, one minute), `force_registry.charge_interest` charges every force,
  in force index order, from a handler `control.lua` registers unconditionally.

The rate is high on purpose (about 35 % per hour compounded within the limit): an overdraft is
short-term slack, loans are the way to borrow for long. One field is stored per force,
`overdraft_low`; `force_registry.ensure` gives it to states saved by 0.1.24 on configuration change.

Price combinators (ADR-0010) emit the balance on `gb-credits`, and the order combinator (ADR-0011)
refuses an input carrying it. A balance of 0 emits nothing, and with the overdraft a force at 0 can
spend, so a price combinator wired by mistake into an order combinator would buy its prices as
orders. Price combinators therefore always emit a **Price feed** marker (`gb-price-feed`, 1), and the
order combinator refuses that too.

## Amendment (2026-10-31, #98)

The limit above is no longer a constant for every force. The financial engineering research raises
it: `gb-overdraft-1` to 25 000, `gb-overdraft-2` to 100 000 (`account.OVERDRAFT_LEVEL_LIMITS`), the
level a force researched being recorded in `state.overdraft_level` by `scripts/finance.lua` (on
research events, force resets, init, configuration change and before each interest charge). A
level's extra over the base is scaled by the reputation's contract scale, capped at 1:
`BASE + (level limit − BASE) × min(1, contract_scale(reputation))`, so a force at −5 or below gets
half the extra and a force at 0 or above the full extra, never more. The base 10 000 is never scaled,
so no existing save loses limit; a reputation drop or an un-researched level can lower the limit
and leave a balance beyond it, which then spends nothing until it comes back.

Consequently the interest cap is 0.5 % of the force's limit a minute (up to 500 credits at
100 000), not "at most 50 credits", and the overdraft is no longer only short-term slack of a fixed
size: it becomes a researched line of credit. It stays coherent with loans
([ADR-0021](0021-loans.md)): its rate (about 35 % per hour within the limit) remains far above a
loan's 5–15 % over an hour, so long borrowing still goes through loans, and its extra follows
reputation like the loans' debt cap, so research cannot buy a poor-reputation force more credit than
its counterparties would give.

## Consequences

- Positive: one place decides what a force can spend; purchases a few credits short go through;
  the limit is the hook for #98, the available funds the one for #96 and #97.
- Trade-offs accepted: interest is charged per whole minute on the period's lowest balance, so a
  brief dip pays a full minute; a force beyond the limit has no further consequence until bankruptcy
  exists. The `gb-credits` signal and the window show a negative balance.
- Follow-up: #96 (loans, [ADR-0021](0021-loans.md)), #97 (bankruptcy, what happens beyond `-limit`:
  done, [ADR-0022](0022-insolvency-and-bankruptcy.md), which also sets the limit to 0 during a credit
  ban), #98 (research raising the limit: done, `state.overdraft_level` read by `overdraft_limit`,
  [contracts.md](../contracts.md#research)).
