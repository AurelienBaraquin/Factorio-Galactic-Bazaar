# ADR-0004 — NPC market simulation: lazy catch-up instead of a tick loop

- **Status**: Accepted
- **Date**: 2026-10-29
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

Between player trades, each key's market must move on its own: displacements decay back towards
balance (ADR-0003), non-player traders add some noise, and a short price history is kept for the
interface. Issue #14 asked for an update spread in batches over several ticks with a measured UPS
budget, deterministic for multiplayer. A force can see 200 (vanilla) to 300+ (Space Age) keys.

## Options considered

1. **Batched tick loop** — every N ticks update a slice of all keys of all forces. Cost paid every
   tick by everyone, even for keys nobody trades or looks at; the RNG and cursor are global state
   whose order matters.
2. **Lazy catch-up on read** — a key's market is only advanced when it is read (a trade, a price
   shown), by as many whole steps as have elapsed. Decay has a closed form, so a long gap costs a
   bounded number of steps.

## Decision

Option 2, in `scripts/core/npc_market.lua`, used by `scripts/market.lua`. Each key of each force
has an entry `{displacement, tick, rng, history}` in `storage.forces[i].markets[key]`, created on
first read. Reading it runs every whole step (`step_ticks` = 3600, one minute) since `tick`: decay,
then a uniform drift of at most `volatility` (5 %) of the depth, then a history sample (30 kept).
A gap longer than 30 steps is decayed in one go first. Each entry has its own Park-Miller random
state (`scripts/core/random.lua`), seeded from the key and the force, so a key's prices depend
neither on when it is read nor on which other keys are read — catching up at once or in pieces
gives the same result. Reads happen inside events, which every peer runs identically.

Budget: a full catch-up costs at most 0.05 ms per key (measured on 2.1.24: 199 keys in 8.5 ms in
vanilla, 302 keys in 14 ms with Space Age); a normal read runs zero or one step. Callers must not
read the whole market in one tick: an interface reads only the rows it shows.

## Consequences

- Positive: zero cost per tick; deterministic; no global cursor or RNG.
- Trade-offs accepted: a market nobody reads keeps its last history until read; a sudden read of
  every key after a long absence is a one-off spike (bounded above).
- Follow-up: market events (shortages, crises) in M7 can be added as extra steps in the catch-up.
