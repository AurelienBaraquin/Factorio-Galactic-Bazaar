# ADR-0017 — Capacity rental: a dedicated machine, and contracts paid in installments

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M4)
- **Supersedes**: none (extends [ADR-0015](0015-one-contract-model.md))

## Context

#78 asks that a counterparty rent a machine for a time and pay by the hour, that the machine work
for it (ingredients provided, products taken) and not for the force meanwhile, with a penalty when
the promised capacity is not held. The contract model of ADR-0015 knows goods and one payment on
fulfilment, no schedule.

## Options considered

1. **Which machine** — any assembler the player marks (a selection tool, then guards against every
   way a player can use a machine: GUI, paste, inserters, recipe changes), or a dedicated building
   that is only ever a rental machine: closed to the player, its recipe set by the script.
2. **How capacity is promised** — a measured rate per period (crafts counted per period, a penalty
   per short period: a schedule of penalties the model lacks), or a quantity of products by the end
   of the rental, set at a share of the machine's nominal speed.
3. **How rent is paid** — on fulfilment only (the existing model), or in installments for what the
   machine made so far.

## Decision

A dedicated **rental assembler** (assembling machine 2 derivative, no module slots, beacons limited
to speed, consumption and pollution), closed to the player; idle, it has no recipe. Capacity is
promised as **products by the end** of a 30-minute rental, at 80 % of the machine's nominal speed:
a machine kept powered and running fulfils it, one that is not fails it and the force loses the
guarantee. The contract model gains an optional **`installment_ticks`**: while active, every period
pays the share of the reward earned by the units delivered so far (`contract-installment`); the rest
comes on fulfilment; paid installments stay paid on failure. The script provides ingredients a few
crafts at a time and takes the products as they come; the guarantee exceeds the value of what the
force could take from the machine.

## Consequences

- Positive: the machine cannot be used by the force while rented, without guarding a general
  assembler; rent arrives during the rental; the contract model stays one model.
- Trade-offs accepted: a single machine per contract (no groups); a machine is rented only as the
  dedicated building; the promised capacity is checked at the end, not per period.
- Follow-up: groups of machines, and recipes with fluids, by a later ADR if needed.
