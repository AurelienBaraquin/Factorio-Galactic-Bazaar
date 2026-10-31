# ADR-0022 — Insolvency and bankruptcy: a grace period, then a restructuring that freezes the debt

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M6)
- **Supersedes**: none. Amends [ADR-0020](0020-overdraft-and-debit-interest.md) (no overdraft during a credit ban; what happens beyond `-limit`) and [ADR-0021](0021-loans.md) (what happens to arrears a force cannot pay)

## Context

#97 asks what happens to a force that can no longer pay. Two debts can outgrow a force: overdraft
interest, which may push the balance beyond `-limit` (ADR-0020), and loan arrears beyond the
overdraft, which wait for income (ADR-0021). Until now neither had an end: a force beyond its limit
could simply not spend, and its arrears stayed owed for ever. The brief lists bankruptcy in scope.
Constraints: state keyed by force (ADR-0001), deterministic periodic checks, no exploit that lets a
force keep borrowed money for free, and research (#98, in parallel) will make the overdraft limit
depend on the force, so every rule reads `account.overdraft_limit(state)` and
`account.available(state)`, never a constant.

## Options considered

1. **When a force is insolvent** — a check of the balance at a periodic tick only (a force could
   be solvent for that one tick and restart the clock), or a **low-water rule**: the lowest balance
   since the previous check, kept by every transaction like `overdraft_low`.
2. **When it recovers** — as soon as its available funds are back at zero (a force hovering at the
   limit would be declared insolvent and solvent again every minute, as interest pushes it over), or
   once its available funds stayed above a **margin** for a whole interest period.
3. **What bankruptcy does to the debt** — writes it off (a first version did: borrow, spend and go
   bankrupt kept the loan money, an exploit caught in review), seizes the force's assets (out of scope
   until 1.0, brief), or **restructures** it: everything owed is frozen into one debt that earns no
   interest and is repaid from income, at the cost of every open contract, the reputation and credit
   until it is repaid.
4. **Credit after bankruptcy** — loans only refused (the overdraft could be drawn again at once),
   or **loans and the overdraft** refused for a ban that grows with each bankruptcy and lasts until
   the frozen debt is repaid.
5. **Force merge** — the destination keeps its own state (merging into a fresh force would restart
   the clock or shed a ban), or **the stricter of the two**.

## Decision

`scripts/core/insolvency.lua` (pure) and `scripts/insolvency.lua` (notifications) own it. Every
`CHECK_TICKS` (60), right after the loans' arrears collection, `insolvency.check_all` checks every
force in force index order:

- **Insolvency** starts at the check where the lowest balance since the previous check
  (`solvency_low`, kept by `account.apply` and interest) was beyond the overdraft limit, or the
  arrears exceed the available funds (collection has then taken all it could). It is stored as
  `insolvent_since` (a tick). The force is told, with the balance to reach and the time left.
  Each check reads the limit in force at that check (`account.overdraft_limit(state)`), so a limit
  that drops under an existing debt (a credit ban, or research and reputation once #98 makes the
  limit vary) starts the grace period like any other cause: a force is never bankrupted at once.
- **Recovery**: once every check over `RECOVERY_TICKS` (an interest period, one minute) found the
  period's lowest balance leaving at least `RECOVERY_SHARE` (5 %) of the limit available, with no
  arrears owed (`recovering_since` records the first of them; a check that misses the margin clears
  it). A sale timed just before a check is not a recovery; neither is a force back at exactly the
  limit, nor one that interest takes back under the margin within the minute. The force is told
  only when it becomes insolvent and when it recovers, never at each dip.
- **While insolvent**: no contract is accepted (`contracts.can_accept` refuses `insolvent`: incoming
  contracts, rentals, concessions, outsourcing, loans; a lease is refused before its offer is filed)
  and no loan is granted. Selling, export chests, power exports and contract deliveries go on, so
  the force can earn its way back. Purchases are not refused as such: the funds check refuses them
  while the balance is beyond the limit, but a force insolvent through arrears, or with funds again
  while it recovers, may still buy.
- **Bankruptcy**, at the first check `GRACE_TICKS` (10 minutes) or more after insolvency began
  whose period missed the margin: every open contract ends — offers are declined, active ones fail
  with their guarantees kept (each journaled as a 0-credit `contract-failed`). **Nothing is written
  off**: the negative balance, the arrears and each active loan's installments left
  (`contracts.payoff`) move into `bankruptcy_debt`; the balance is set to 0 and arrears to 0, the
  move journaled as one `bankruptcy-restructured` entry (its amount brings the balance to 0, its
  `debt` field the total moved). The debt is frozen — no interest — and at every check it takes the
  whole positive balance it can, never into the overdraft (`bankruptcy-debt` entries, merged per
  minute), so sales, exports and contract rewards repay it. Reputation falls to the minimum (−20).
  Credit is refused (`credit_ban_until`) until **both** `BAN_TICKS` (60 minutes, doubled with each
  bankruptcy up to 8 hours, `bankruptcies` counts them) have passed **and** `bankruptcy_debt` is 0.
  Meanwhile `account.overdraft_limit` is 0 (no overdraft, no interest), whatever the force's overdraft
  research, and loans are refused (`credit-ban`); contracts that need no credit can still be taken.
  The force is told what ended and what it owes, and again when credit returns. Credit returns with
  the reputation the bankruptcy left (−20, unless contracts raised it), which halves a researched
  overdraft's extra over the base (#98); the balance is 0 then (the debt took every positive
  credit), so the smaller limit starts no new insolvency.
- **What a bankruptcy leaves**: leases release their planet slots through the concessions sweep,
  rented machines are released by the rental service (both already react to a contract that is no
  longer active); goods already paid — capsules in flight, planet shipments in transit, an incoming
  contract's ingredients — still land, since they were settled when ordered.
- **Force merge**: the destination keeps the earliest `insolvent_since` (its recovery starts
  afresh), the latest `credit_ban_until` and the most `bankruptcies`; bankruptcy debts and lowest
  balances add up. A healthy force can thus inherit another's ban and debt.
- The market window shows the state and the time left (insolvency), or the ban's time left and the
  debt still to repay (credit ban); the Borrow buttons say why they are disabled.

## Consequences

- Positive: no debt is ever cancelled, so borrowing or overdrawing and then going bankrupt gains
  nothing: there is no walk-away. Bankruptcy is a restructuring: it stops interest from growing a
  debt the force cannot serve, at the price of every open contract, a reputation of −20 (fees ×1.5,
  smaller contracts) and no credit until the debt is repaid. Dodging bankruptcy needs real income
  held for a minute; repeated bankruptcies cost more each time.
- Trade-offs accepted: a frozen debt earns no interest, so a bankrupt force repays less than it
  would have with interest running; it repays only from income, so a force with none stays without
  credit indefinitely; to escape bankruptcy, a force must reach the margin for a whole check period
  before the grace ends; after a bankruptcy a force has no credit at all, so a contract needing a
  guarantee needs a positive balance, which the debt takes first.
- New per-force fields: `solvency_low`, `insolvent_since`, `recovering_since`, `credit_ban_until`,
  `bankruptcies`, `bankruptcy_debt`, given to older saves by `force_registry.ensure` on
  configuration change where they have a starting value.
- Follow-up: #98 (research raising the limit) changes `account.overdraft_limit`; the ban must keep
  returning 0 there.
