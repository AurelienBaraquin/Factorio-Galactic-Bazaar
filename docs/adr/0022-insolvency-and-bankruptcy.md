# ADR-0022 — Insolvency and bankruptcy: a grace period, then debts written off at a price

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
   once its available funds stayed above a **margin** for a whole check period.
3. **What bankruptcy costs** — only a reputation hit (the debt would be a free gift), the force's
   assets seized (out of scope until 1.0, brief), or the debt written off against **every open
   contract, the reputation and credit for a while**.
4. **Credit after bankruptcy** — loans only refused (the overdraft could be drawn and written off
   again every 72 minutes), or **loans and the overdraft** refused for a ban that grows with each
   bankruptcy.
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
- **Recovery**: at a check where the lowest balance of the whole period left at least
  `RECOVERY_SHARE` (5 %) of the limit available and no arrears are owed. A sale timed just before a
  check is not a recovery; neither is a force back at exactly the limit.
- **While insolvent**: no contract is accepted (`contracts.can_accept` refuses `insolvent`: incoming
  contracts, rentals, concessions, outsourcing, loans) and no loan is granted. Selling, export
  chests, power exports and contract deliveries go on, so the force can earn its way back;
  purchases are already refused by the funds check.
- **Bankruptcy**, at the first check `GRACE_TICKS` (10 minutes) or more after insolvency began:
  every open contract ends — offers are declined, active ones fail with their guarantees kept and
  without arrears (a loan's remaining installments are written off with the rest); a negative balance
  is brought back to zero (`bankruptcy-write-off` journal entry) and arrears are cleared; a positive
  balance is kept; reputation falls to the minimum (−20); and credit is refused for a ban of
  `BAN_TICKS` (60 minutes), doubled with each bankruptcy up to 8 hours (`bankruptcies` counts
  them). During the ban `account.overdraft_limit` is 0 (so no overdraft and no interest) and loans
  are refused (`credit-ban`); contracts that need no credit can still be taken. The force is told
  what ended and for how long, and again when credit returns.
- **What a bankruptcy leaves**: leases release their planet slots through the concessions sweep,
  rented machines are released by the rental service (both already react to a contract that is no
  longer active); goods already paid — capsules in flight, planet shipments in transit, an incoming
  contract's ingredients — still land, since they were settled when ordered.
- **Force merge**: the destination keeps the earliest `insolvent_since`, the latest
  `credit_ban_until` and the most `bankruptcies`; lowest balances add up like balances.
- The market window shows the state and the time left (insolvency or credit ban); the Borrow
  buttons say why they are disabled.

## Consequences

- Positive: every debt now has an end; dodging bankruptcy needs real income for a whole period;
  the overdraft cannot be drawn and written off again during the ban, and repeated bankruptcies
  cost more each time.
- Trade-offs accepted: a force can still draw its overdraft and walk away from it once per grace
  plus ban (about 72 minutes the first time, more after), at the cost of every open contract and a
  reputation of −20 (fees ×1.5, smaller contracts); a force that recovers in the last second of its
  grace still goes bankrupt (the period's lowest point counts); after a bankruptcy a force has no
  credit at all, so a contract needing a guarantee needs a positive balance.
- New per-force fields: `solvency_low`, `insolvent_since`, `credit_ban_until`, `bankruptcies`,
  given to older saves by `force_registry.ensure` on configuration change.
- Follow-up: #98 (research raising the limit) changes `account.overdraft_limit`; the ban must keep
  returning 0 there.
