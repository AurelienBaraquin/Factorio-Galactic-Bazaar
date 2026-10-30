# ADR-0009 — Power is traded by two tertiary substations, settled by buffer, priced from fuel

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M2)
- **Supersedes**: none

## Context

Issue #22 asks for a substation based on `electric-energy-interface` that imports or exports
electricity, credited or debited on the energy really exchanged, with a market price for energy
and a throughput capped by research level. Probes on 2.1.24 showed that an EEI's runtime
`input_flow_limit` and `output_flow_limit` read back when written but do not change the flow, while
a runtime `electric_buffer_size` does cap what the buffer holds.

## Options considered

1. **One substation with a mode switch** — needs an interface and a way to keep the network's
   priorities right in both modes.
2. **Two substations with fixed priorities**, like the cargo chests: an export one that charges
   from the network and an import one that discharges into it.
3. **Primary or secondary priorities** — an export substation at `secondary-input` would compete
   with machines for power, and an import one at `secondary-output` would share the load with steam
   engines whether or not the network needs it.

## Decision

Option 2 with the `tertiary` priority (the accumulator's): the export substation only charges
from the network's surplus and the import substation only discharges on shortage, so a player sells
what they do not use and buys what they lack. Every `SETTLE_TICKS` (5 s), each force's export
buffers are sold in one trade and its import buffers refilled in one trade, through a powered hub of
the force within range (ADR-0005); without one, a substation does not trade. The throughput cap is
the buffer size, set to the level's power × 5 s at each settlement (10 MW, then 40 MW with the
second technology); the prototype flow limits are the highest level's.

Electricity is the market key `energy/electricity`, traded in megajoules. Its base value comes from
the production graph: each chemical fuel gets a "burn" recipe giving its fuel value times the best
fuel-to-electricity efficiency the game offers (the most efficient visible chemical burner making
steam or heat times the most efficient steam generator: 1 in vanilla, 2.5 with Space Age's heating
tower), so buying fuel to sell its electricity never beats the market. Nuclear and other fuel
categories are left out (they need far more infrastructure than their fuel cost says), as are fuels
with a burnt result.

A substation's energy is only what the network exchanges: its production and usage settings are
zeroed when built and at each settlement (a blueprint or another mod could set them), and a new or
cloned substation starts empty.

## Consequences

- Positive: no interface needed; the network decides when to trade; one market trade per force and
  direction per settlement, journaled as one entry per direction and minute; value overrides and the
  multiplier reach electricity through its fuels.
- Trade-offs accepted: energy prepaid into an import buffer is lost if the substation is mined; a
  network with no powered hub cannot buy its way out of a blackout (the hub needs power); remote
  value overrides do not take `energy` keys yet; the substations share the tertiary tier with the
  player's accumulators, so on a shortage they discharge alongside them (the force pays while its
  accumulators still hold charge) and on a surplus they take a share of the charge.
- Follow-up: more levels; per-substation statistics in the interface.
