# ADR-0003 — Market price model: exponential impact, spread, reversion

- **Status**: Accepted
- **Date**: 2026-10-29
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

Each tradeable key has a base value (ADR-0002). The market must turn it into buy and sell prices
that react to the player's trades — selling 100 000 circuits must crash their price, buying a rare
part in bulk must make it expensive — and recover over time. Requirements from issue #13: the cost
of a large order is computed in one step, prices are bounded, and no immediate round trip
(buy then sell, or sell then buy back) can make money.

## Options considered

1. **Order book with simulated NPC orders** — realistic depth, but heavy state per key and per
   force, many entries to update every tick, and hard to keep deterministic and cheap.
2. **Linear impact** (`P = V (1 - s/L)`) — simple, but reaches zero or negative prices and needs
   ad-hoc clamping; impact is the same in credits at any price level.
3. **Exponential impact on one displacement number per key** — `P = V e^(-s/L)`: always positive,
   symmetric in ratio (one depth of surplus divides the price by e, one depth of shortage
   multiplies it by e), and its integral has a closed form.

## Decision

Option 3, in `scripts/core/market.lua`. The state of a key is its displacement `s` in units
(positive = the market holds a surplus bought from players). With depth `L = depth_credits / V`:

- mid price `P(s) = V e^(-s/L)`; the player buys at `P (1 + spread/2)` and sells at `P (1 - spread/2)`;
- buying `q` units costs `(1 + spread/2) P(s) L (e^(q/L) - 1)` and sets `s` to `s - q`; selling
  pays `(1 - spread/2) P(s) L (1 - e^(-q/L))` and sets `s` to `s + q` — exact, in one step, and
  splitting an order in two gives the same total;
- a buy followed by the opposite sale returns exactly `(1 - spread/2) / (1 + spread/2)` of the cost,
  so a round trip always loses the spread, whatever the size;
- `|s| <= max_depths × L`: an order beyond that is refused (`insufficient-liquidity`), which bounds
  every price between `V e^-max_depths` and `V e^max_depths`;
- `s` decays towards 0 with a half-life: `s × 0.5^(ticks / half_life_ticks)`.

Defaults (`market.DEFAULTS`): spread 0.1, depth 20 000 credits, half-life 36 000 ticks (10 min),
`max_depths` 10. They are parameters of every function, so settings can change them.

## Consequences

- Positive: one number per key and force; O(1) quotes; provably no round-trip arbitrage; prices
  never reach zero or infinity.
- Trade-offs accepted: the market has no memory of who traded at which price; the depth is the
  same for every key in credits (a rare item is not yet thinner than a common one beyond its value).
- Follow-up: NPC supply and demand noise on `s` and price history (#14); exposing the parameters as
  settings when the market is wired into the game.
