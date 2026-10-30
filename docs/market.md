# Market: prices and trades

How a tradeable key's buy and sell prices are computed from its base value and its market state,
how they move on their own, and how a force trades. The reasoning is in
[ADR-0003](adr/0003-market-price-model.md) (price model) and
[ADR-0004](adr/0004-lazy-npc-market-simulation.md) (NPC simulation); base values in
[pricing.md](pricing.md).

## Runtime API (`scripts/market.lua`)

| Function | Does |
|---|---|
| `market.quote(force_index, kind, name)` | `{buy, sell, mid, history}` for `"item"`/`"fluid"` `name`, or `nil` if not tradeable |
| `market.buy(force_index, kind, name, quantity)` | debits the account and moves the market; `true, cost` or `false, reason` |
| `market.sell(force_index, kind, name, quantity)` | credits the account and moves the market; `true, revenue` or `false, reason` |
| `market.sellable(force_index, kind, name, min_price_ratio)` | units sellable while each still fetches at least `min_price_ratio` × base value |
| `market.preview(force_index, kind, name, side, quantity)` | what buying (`"buy"`) or selling (`"sell"`) would cost or bring now, without trading; or `nil, reason` |
| `market.rebase_all(old_values)` | after base values are rebuilt: brings every entry up to date with its old value, rebases it on the new one, drops entries of keys that lost their value |

Every function takes an optional last argument `quality_name` (default normal): an item of another
quality trades on its own market, keyed `item/<name>@<quality>` and priced from the quality value
([pricing.md](pricing.md), ADR-0008).

A trade is atomic: when it is refused (`not-tradeable`, `invalid-quantity`,
`insufficient-liquidity`, `insufficient-funds`) neither the account nor the market changes. Moving
the goods is the caller's job (the terminal). Read only the keys you display: a full catch-up
costs up to 0.05 ms per key.

## NPC simulation (`scripts/core/npc_market.lua`, `npc_market.DEFAULTS`)

Each key's market is advanced when read, by one step per `step_ticks` (3600, one minute) elapsed:
decay, then a random drift of at most `volatility` (0.05) depths, then a price sample kept in a
history of `history_size` (30). Each entry has its own random sequence
(`scripts/core/random.lua`), so prices do not depend on read order.

## Price model (`scripts/core/market.lua`)

### State

One number per key: the displacement `s` in units. Positive after players sold (surplus, lower
prices), negative after they bought (shortage, higher prices); 0 is the balanced market.

### Functions

| Function | Returns |
|---|---|
| `market.mid_price(V, s, params)` | `V e^(-s/L)`, with depth `L = depth_credits / V` units |
| `market.buy_price` / `market.sell_price` | price of the next unit, mid price × (1 ± spread/2) |
| `market.quote_buy(V, s, q, params)` | total cost of `q` units and the new `s`, or `nil, reason` |
| `market.quote_sell(V, s, q, params)` | total revenue of `q` units and the new `s`, or `nil, reason` |
| `market.max_buy` / `market.max_sell` | most units tradeable before the bound `|s| = max_depths × L` |
| `market.max_sell_at_or_above(V, s, min_price, params)` | most units sellable while the next unit's sell price stays ≥ `min_price` (closed form) |
| `market.decay(s, ticks, params)` | `s` after `ticks` of reversion towards 0 |
| `market.rebase(s, V_old, V_new, params)` | `s × V_old / V_new`, bounded: the price stays the same multiple of the base value when the base value changes (multiplier, overrides, mods) |

Reasons: `invalid-quantity` (not a positive number), `insufficient-liquidity` (beyond the bound).

### Parameters (`market.DEFAULTS`)

| Name | Default | Meaning |
|---|---|---|
| `spread` | 0.1 | buy price is 5 % above the mid price, sell price 5 % below |
| `depth_credits` | 20 000 | credits of trade that move a price by a factor e |
| `half_life_ticks` | 36 000 | time for a displacement to halve (10 minutes) |
| `max_depths` | 10 | bound on `|s|` in depths: prices stay within `V e^±10` |
