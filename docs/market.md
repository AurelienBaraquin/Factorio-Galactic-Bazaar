# Market: prices and trades

How a tradeable key's buy and sell prices are computed from its base value and its market state.
The reasoning is in [ADR-0003](adr/0003-market-price-model.md); base values in [pricing.md](pricing.md).
Code: `scripts/core/market.lua` (pure, not yet wired into the game).

## State

One number per key: the displacement `s` in units. Positive after players sold (surplus, lower
prices), negative after they bought (shortage, higher prices); 0 is the balanced market.

## Functions

| Function | Returns |
|---|---|
| `market.mid_price(V, s, params)` | `V e^(-s/L)`, with depth `L = depth_credits / V` units |
| `market.buy_price` / `market.sell_price` | price of the next unit, mid price × (1 ± spread/2) |
| `market.quote_buy(V, s, q, params)` | total cost of `q` units and the new `s`, or `nil, reason` |
| `market.quote_sell(V, s, q, params)` | total revenue of `q` units and the new `s`, or `nil, reason` |
| `market.max_buy` / `market.max_sell` | most units tradeable before the bound `|s| = max_depths × L` |
| `market.decay(s, ticks, params)` | `s` after `ticks` of reversion towards 0 |

Reasons: `invalid-quantity` (not a positive number), `insufficient-liquidity` (beyond the bound).

## Parameters (`market.DEFAULTS`)

| Name | Default | Meaning |
|---|---|---|
| `spread` | 0.1 | buy price is 5 % above the mid price, sell price 5 % below |
| `depth_credits` | 20 000 | credits of trade that move a price by a factor e |
| `half_life_ticks` | 36 000 | time for a displacement to halve (10 minutes) |
| `max_depths` | 10 | bound on `|s|` in depths: prices stay within `V e^±10` |
