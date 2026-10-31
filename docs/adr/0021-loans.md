# ADR-0021 — Loans: an advance repaid by charges, priced and capped by reputation

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M6)
- **Supersedes**: none (extends [ADR-0015](0015-one-contract-model.md) and [ADR-0019](0019-service-contracts-with-a-charge.md); funds checked as [ADR-0020](0020-overdraft-and-debit-interest.md) says)

## Context

#96 asks that a force borrow a chosen amount, paid at once and repaid by installments of principal
and interest over a term; that the rate fall as reputation rises and a cap bound the debt; that a loan
be a contract of the one model (ADR-0015, ADR-0019) and that an unpaid installment default it. Two
ways out of a loan must not let a force keep the money for free: a default, and abandoning it from
the contracts window. The overdraft (#95, [ADR-0020](0020-overdraft-and-debit-interest.md)) lets a
balance go below zero down to a limit, and every check of a cost uses the available funds (balance
plus overdraft); bankruptcy (#97) is a separate issue, not part of this decision.

## Options considered

1. **How the money moves** — a loan outside the contract model (its own record and schedule), or a
   contract with an `advance` paid at acceptance and a `charge` per period that repays it: the
   service contract of ADR-0019, whose charge needs no service.
2. **What a default leaves** — the principal not repaid is forgiven (a force could borrow, spend and
   default for −1 reputation, again and again); a guarantee covering it (held at acceptance, it would
   require the money the force is borrowing); the remaining principal debited at once (beyond the
   overdraft limit, a force would be pushed into a debt only bankruptcy can settle); or what was not
   repaid stays owed as **arrears**, taken from the balance as credits come in, and counted in the
   debt.
3. **Abandoning a loan** — forbidden (a force wanting out could only default), a default (forgiven
   principal again), or an early repayment: of the principal left (a force could borrow and repay
   within a period, paying no interest), or of **every installment left**, interest included.
4. **Amounts and terms** — any amount typed by the player, or a few fixed principal tiers with one
   term, which the window can show with their terms.

## Decision

A loan is a contract of kind `loan` whose new optional field **`advance`** (credits, needs a
`charge`) is paid to the force at acceptance (`contract-advance`); its guarantee is zero. Its charge
is principal × (1 + rate) / 12, taken every 5 minutes over a **60-minute** term on the schedule of
ADR-0019, without any service. A force borrows one of three **tiers, 5 000, 20 000 and 100 000
credits**, from the contracts window; the contract is offered and accepted at once, or nothing
changes.

- **Rate**, over the term, fixed at borrowing: 10 % − 0.25 % × reputation, so 5 % at 20 and 15 % at
  −20.
- **Debt cap**: 50 000 × the reputation's contract scale (ADR-0016): 25 000 from −5 down, 50 000 at
  0, 150 000 at 20. The debt is the principal active loans still have to repay (principal × whole
  installments left / 12) plus arrears; a loan that would take it above the cap is refused. It
  counts loans only, not the overdraft in use: the overdraft has its own limit and interest. Loans
  count among the contracts window's rows (`contracts.MAX_LISTED`).
- **Funds**: borrowing needs no guarantee, but acceptance checks the available funds like any
  contract's: a force whose balance is beyond its overdraft limit (available funds below zero) is
  refused (`insufficient-funds`), and the Borrow buttons say so.
- **Installments**: one the available funds can pay is paid, even if it takes the balance into
  the overdraft (which then pays its debit interest), like any service charge.
- **Default**: an installment the available funds cannot cover fails the loan (ADR-0019: −1
  reputation), and that installment plus every one left, interest included, become the force's
  **arrears** (`storage.forces[i].arrears`). Every second, arrears are taken from what a positive
  balance holds (`loan-arrears`), never from the overdraft, so collecting them never creates debit
  interest; no loan is granted while any are owed.
- **Void**: a loan has no goods and is never voided (on a configuration change), which would cancel
  its debt.
- **Abandon**: a loan is repaid, not abandoned. The contracts window's button repays every
  installment left at once (`contract-repaid`, the contract then fulfilled), or is refused, changing
  nothing, when the available funds cannot cover it.
- **Reputation**: repaying earns none (it could be bought with interest); a default costs 1.
- **Force merge**: open loans carry over with the contract book; arrears add up.

## Consequences

- Positive: loans share the contract lifecycle, settlement, window and journal; neither a default
  nor an abandon lets a force keep the principal; borrowing is bounded by reputation.
- Trade-offs accepted: the force pays the same total whether it repays early or late; arrears earn
  no further interest and nothing but a positive balance collects them, so a force with no income keeps
  owing them until bankruptcy (#97) decides otherwise; fixed tiers and one term; forces created
  for the purpose (a console or another mod) each get a reputation-0 cap and rate before a merge.
- Follow-up: overdraft (#95): done, ADR-0020; bankruptcy (#97) will decide what happens to arrears
  a force cannot pay.
