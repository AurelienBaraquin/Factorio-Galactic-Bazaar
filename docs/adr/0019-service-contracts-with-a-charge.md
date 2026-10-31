# ADR-0019 — Service contracts: the force pays a charge every period

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M5)
- **Supersedes**: none (extends [ADR-0015](0015-one-contract-model.md) and [ADR-0017](0017-capacity-rental-with-installments.md))

## Context

A mining concession (#85) is an exchange over time: a planet ships ore every period and the force
pays for it, every period. The contract model of ADR-0015 only pays the force (a reward, in
installments since ADR-0017) for goods it hands over; it has no way for the force to pay a
counterparty over time, and requires goods back.

## Options considered

1. **A concession outside the contract model** — its own lease record and billing; simple, but a
   second lifecycle beside contracts, against the brief's "one contract model".
2. **A charge in the contract model** — a contract may name a `charge` the force pays every
   installment period; it then requires no goods and is fulfilled when its term ends.
3. **Pay the whole term upfront** — no periods, but the force carries the whole cost of a term it
   may not complete, and nothing ties payment to deliveries.

## Decision

Option 2. A contract spec may carry `charge` (credits, positive, with `installment_ticks`); its
`requires` may then be empty. While active, every installment period the engine asks for the charge
(`contracts.installment` returns it as negative credits). The adapter takes it through the force's
account only after the service of that kind (registered by the feature, `register_service`, with a
side-effect-free `can_serve`) has delivered the period; a period that cannot be delivered is skipped
before the balance is checked, and one not delivered is not charged. Periods follow their schedule
from acceptance, the last one at the deadline, whatever tick settlement runs at; the contract is
fulfilled only once its last period was charged. A force whose balance cannot cover a charge
defaults: the contract fails, its guarantee is kept, reputation −1 (since
[ADR-0020](0020-overdraft-and-debit-interest.md), the available funds, balance plus overdraft, must
cover it). At the end of its term
it is fulfilled: the guarantee comes back, reputation unchanged (paying rent is no feat). Abandoning
it defaults it.

## Consequences

- Positive: concessions (and later paid services) share the contract lifecycle, the window and the
  money path; a force pays only for periods actually shipped.
- Trade-offs accepted: a service contract earns no reputation; a default is decided at the first
  charge the balance cannot cover, without grace.
- Follow-up: foundries and assemblers (#86) may charge per period the same way.
