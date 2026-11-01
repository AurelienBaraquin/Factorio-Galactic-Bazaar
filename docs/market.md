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
| `market.buy(force_index, kind, name, quantity, quality_name, merge_ticks)` | debits the account and moves the market; `true, cost` or `false, reason` |
| `market.sell(force_index, kind, name, quantity, quality_name, merge_ticks, value_factor)` | credits the account and moves the market by `quantity`; `true, revenue` or `false, reason`. `value_factor` (default 1, refused outside 0 to 1) scales the revenue only: the freshness of spoiled goods ([ADR-0013](adr/0013-spoilable-goods-priced-by-freshness.md)) |
| `market.sellable(force_index, kind, name, min_price_ratio)` | units sellable while each still fetches at least `min_price_ratio` × base value |
| `market.preview(force_index, kind, name, side, quantity)` | what buying (`"buy"`) or selling (`"sell"`) would cost or bring now, without trading; or `nil, reason` |
| `market.plain_preview(force_index, kind, name, side, quantity)` | the same on the plain market: at the force's own displacement, without the shift of market events |
| `market.buyable(force_index, kind, name, quality_name)` | units buyable before the shortage bound (funds not checked) |
| `market.position(force_index, kind, name, quality_name)` | the live base value, displacement and market parameters of the key, or `nil` if not tradeable; the Market tab's item detail computes its figures from them ([terminal.md](terminal.md#item-detail)) |
| `market.rebase_all(old_values)` | after base values are rebuilt: brings every entry up to date with its old value, rebases it on the new one, drops entries of keys that lost their value |

`kind` is `"item"`, `"fluid"` or `"energy"` (`energy/electricity`, in megajoules, traded by the
power module). `merge_ticks` (optional) marks a recurring trade whose journal entries merge over that period
(power settlements). Every function takes an optional argument `quality_name` (default normal): an item of another
quality trades on its own market, keyed `item/<name>@<quality>` and priced from the quality value
([pricing.md](pricing.md), ADR-0008). Its `depth_credits` is multiplied by the quality's value
ratio, so it is as deep in units as the normal market. `market.rebase` takes the old and new
parameters, and `market.rebase_all(old_values, old_levels)` uses the quality levels of before the
rebuild.

A trade is atomic: when it is refused (`not-tradeable`, `invalid-quantity`,
`insufficient-liquidity`, `insufficient-funds`: the purchase would take the balance below the
overdraft limit, [data-model.md](data-model.md)) neither the account nor the market changes. Moving
the goods is the caller's job (the terminal). Read only the keys you display: a full catch-up
costs up to 0.05 ms per key.

## NPC simulation (`scripts/core/npc_market.lua`, `npc_market.DEFAULTS`)

Each key's market is advanced when read, by one step per `step_ticks` (3600, one minute) elapsed:
decay, then a random drift of at most `volatility` (0.05) depths, then a price sample kept in a
history of `history_size` (30). Each entry has its own random sequence
(`scripts/core/random.lua`), so prices do not depend on read order; each drift roll is also salted
with a figure drawn every minute from what nobody knows in advance, so that the drift cannot be
computed from the key and the force ([below](#market-events-scriptscoremarket_eventslua-scriptsmarket_eventslua)).

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
| `market.shifted_buy_price` / `market.shifted_sell_price(V, s, shift, params)` | the next unit's price under a market event's `shift`: `buy_price(s + min(shift, 0))` and `sell_price(s + max(shift, 0))`, never better for the trader than the plain price ([below](#market-events-scriptscoremarket_eventslua-scriptsmarket_eventslua)) |
| `market.quote_shifted_buy` / `market.quote_shifted_sell(V, s, shift, q, params)` | total of `q` units under a shift and the shifted displacement after, or `nil, reason` (the bound applies to `s + shift`) |
| `market.max_shifted_sell_at_or_above(V, s, shift, min_price, params)` | most units sellable under a shift while each fetches at least `min_price` |
| `market.rebase(s, V_old, V_new, params)` | `s × V_old / V_new`, bounded: the price stays the same multiple of the base value when the base value changes (multiplier, overrides, mods) |

Reasons: `invalid-quantity` (not a positive number), `insufficient-liquidity` (beyond the bound).

### Parameters (`market.DEFAULTS`)

| Name | Default | Meaning |
|---|---|---|
| `spread` | 0.1 | buy price is 5 % above the mid price, sell price 5 % below |
| `depth_credits` | 20 000 | credits of trade that move a price by a factor e |
| `half_life_ticks` | 36 000 | time for a displacement to halve (10 minutes) |
| `max_depths` | 10 | bound on `|s|` in depths: prices stay within `V e^±10` |

## Market events (`scripts/core/market_events.lua`, `scripts/market_events.lua`)

Shortages, surpluses and crises of the whole galaxy (#120, [ADR-0025](adr/0025-market-events-as-a-shared-displacement-shift.md)).
Every force sees the same events, each on its own market.

**Shift.** An event shifts the displacement of its goods by `shift` market depths (negative: prices
rise), like a flow of NPC trades. Its course is a chain of segments: from tick `t0` with shift `x0`,
the shift is `G + (x0 - G) 2^(-(t - t0)/h)`, `G` the event's goal (in its own direction) and `h` the
market's half-life. At the first pass at or after its start the event gets its first goal (an
announced one may instead be called off). At every later pass while it is active it ends early with
chance `end_chance`, or the goal takes a random step of at most `goal_step` × magnitude, kept between
0 and the kind's `ceiling` × magnitude, and a new segment starts from the shift reached: the shift is
continuous and keeps its sign (`spec/core/market_events_spec.lua` checks both at every pass). From its
end (at most `end_tick`, earlier when it ends early) the shift halves every `h`. The NPC history
samples include the shift (for ticks before the current segment, read linearly between knots of the
path kept every `trail_ticks`). The shift of an item reaches every quality of it.

**Prices under a shift** (`scripts/core/market.lua`, shifted prices). The mid price, the bounds and
the liquidity (`buyable`, so a shortage leaves less to buy; `max_sell`) use
`clamp(entry.displacement + shift)` within the `max_depths` bound. A shift only ever makes a price
worse for the trader: the buy price is the plain buy price at `s + min(shift, 0)` and the sell price
the plain sell price at `s + max(shift, 0)`, `s` being the force's own displacement. A shortage thus
raises what buyers pay and leaves sellers the plain sell price; a surplus lowers what sellers get and
leaves buyers the plain buy price. Prices are continuous in the shift (equal to the plain ones at 0).
A large order is priced like a plain one at that displacement, the bound applying to the shifted
displacement (`quote_shifted_buy`, `quote_shifted_sell`; `max_shifted_sell_at_or_above` for export
chests). A trade moves the entry's own displacement by what it traded, kept within the bound (at
the bound, the part of the shift beyond it does not erase it). `market.position` returns the part of
the shift left within the bound, for the item detail.

**What an event can and cannot give.** At every moment every buy price under an event is at least
the plain buy price, and every sell price at most the plain sell price, at the same own displacement.
So any sequence of trades does at most as well with an event as the same trades at the same moments
on the plain market — whatever the event's course and whatever a player knows of it (exact prices at
any tick, the Events tab, the notices, even the goal). The plain market keeps its own behaviour
(ADR-0003): its spread on every round trip, and the return of a force's own displacement to balance,
which pays a round trip only once the displacement is larger than the spread (from about 0.1 depth;
+10.5 % from 0.2 depths held 3 hours, measured below, the same with or without an event). That return
only recovers part of the price impact the force paid to build its displacement: the whole cycle
never beats selling less in the first place, and no round trip from a balanced market pays
(`spec/balance_spec.lua`, [balance.md](balance.md)), so the balancing pass of #122 kept it.
`spec/core/market_events_spec.lua` checks the dominance at every sample of seeded courses whose own
displacement starts at 0, ±0.05, ±0.1 or ±0.2 depths, decays and takes NPC drift, at magnitudes
0.25, 1 and 3, against a clairvoyant trader (best round trip in hindsight, either side) and six
strategies; without an own displacement no strategy gains. Averages at magnitude 1 over 300 courses
each, return after the spread; where one figure is given the event and plain returns are equal to
0.03 %, and "a / b" gives s0 positive / negative. Magnitudes 0.25 and 3 give the same figures within
0.4 %, but the other-side row: −17.0 % and −59.8 % with the event.

| Strategy | s0 = 0 | ±0.05 | ±0.1 | ±0.2 |
|---|---|---|---|---|
| In at the notice on the event's side, out at its end | −9.6 % | −9.5 % / −9.6 % | −9.3 % / −9.5 % | −8.6 % / −9.1 % |
| The same on the other side (event / plain, m = 1) | −34.6 % / −9.5 % | | | |
| On the gap to the exact goal (≥ 0.2 depths), out when closed | −9.6 % | −9.5 % / −9.6 % | −9.3 % / −9.6 % | −8.8 % / −9.3 % |
| Against the fade, out 3 h after the end | −9.5 % | −9.5 % / −9.6 % | −9.4 % / −9.5 % | −9.0 % / −9.3 % |
| In at the start, out at the best price in hindsight | −9.5 % | −7.5 % | −5.5 % | −1.1 % |
| Own reversion: in at the notice on the side it favours, out 3 h after the end | — | −4.8 % / −4.9 % | +0.04 % / −0.05 % | +10.6 % / +10.5 % |
| Clairvoyant best, event / plain | +22.8 % / +29.6 % | | | +34.3 % / +38.3 % (s0 = +0.2) |

The clairvoyant figures show what a player who knew the NPC drift in advance could make on the plain
market; that drift is now salted (below), so nobody can.

**NPC drift salt.** Each entry's random sequence is seeded from its key and force, which anyone can
compute. Every minute the events pass also draws a salt from the mixed random state
(`market_events.draw_salt`, a ring of 32 minutes in `storage.market_events.salts`); an NPC step at
tick `t` adds the salt of the minute before `t` to its drift roll, modulo 1 (`npc_market.catch_up`'s
`salt_at`). The roll stays uniform, a step's result is fixed once its salt is drawn (so prices still
do not depend on read order, nor on catching up at once or in pieces), and the drift cannot be
computed in advance. A save without salts yet (older ones, the first minute) steps without one.

**Draws.** One state for the galaxy, `storage.market_events` ([data-model.md](data-model.md#storagemarket_events)).
Its Park-Miller random state is seeded from the map seed, and at each draw and each pass with an
active event it is reseeded with the forces' balances and journal sizes plus the tick, then advanced
three steps so that close values give unrelated draws (`market_events.mix`): figures every peer
shares but nobody knows in advance, so the map seed does not give the calendar. Whether a forecast is
called off and an event's first goal are drawn at its start, so the saved state does not hold them
before. Every `pass_ticks` (600) a pass (`market_events.on_pass_tick`) draws an event once the
scheduled tick is reached, moves the active ones, tells the phase changes to the forces that
researched Galactic Bazaar ([notifications.md](notifications.md)) and forgets old events. The
candidates (tradeable items and fluids, with their families) are cached in the state, built on init,
configuration change and every base value rebuild (`market_events.on_values_rebuilt`), and not read
at all when events are off or `max_open` are open. Parameters (`market_events.DEFAULTS`):

| Name | Default | Meaning |
|---|---|---|
| `interval_ticks` | 108 000 (30 min) | mean time between draws at frequency 1; each interval is 0.5 to 1.5 times it, divided by the frequency: 15 to 45 min at 1, 3:45 to 11:15 at 4 (at 0 nothing is drawn and the draw is checked again an interval later) |
| `kinds` | shortage 0.4, surplus 0.4, crisis 0.2 | weights; first goal and ceiling in depths × magnitude: shortage and surplus 0.4 to 1, ceiling 1.5 (mid price up to ×4.48, or ÷4.48 for a surplus), crisis 0.25 to 0.6, ceiling 0.9 (up to ×2.46) on each good |
| `goal_step`, `end_chance`, `pass_ticks` | 0.03, 1/180, 600 | at each pass, the goal moves by at most 0.03 depths × magnitude, or the event ends (chance 1/180, about every 30 min) |
| `crisis_min_keys`, `crisis_max_keys` | 3, 12 | a crisis takes a random subset of one family (an item subgroup, `LuaPrototypeBase.subgroup`; fluids form the family of their own subgroup) with at least 3 free goods |
| `min_duration_ticks`, `max_duration_ticks` | 36 000, 108 000 | an event lasts at most 10 to 30 min (drawn); with early ends, about 14 min on average |
| `announce_chance`, `warning_ticks` | 0.5, 18 000 | half the events are announced 5 min before they start, with the range of their effect |
| `cancel_chance` | 0.25 | share of announced events called off, drawn when they are due to start |
| `max_open` | 3 | events announced or active at once; a draw finding 3 draws nothing; goods with an event still kept (fading ones included) are never drawn |
| `retention_half_lives` | 10 | an event is forgotten 10 half-lives (100 min) after its end, its shift then below 2^-10 (0.1 %) of what it was at its end |
| `trail_size`, `trail_ticks` | 31, 3600 | knots of the path kept for the price history |

Settings (runtime-global, map settings): `gb-market-events-frequency` (0 to 4, default 1; 0 turns
events off) and `gb-market-events-magnitude` (0.25 to 3, default 1, scales the first goal, the step
and the ceiling, kept on the event). Both are read at each draw; a frequency change waits for the
draw already scheduled (up to 45 min at frequency 1, 3 hours at 0.25). Simulated over 2000 hours
(`market_events` core, 200 goods): about 0.5, 2.0, 4.0 and 7.2 events an hour at frequency 0.25, 1,
2 and 4 (called-off forecasts included; at 4, `max_open` blocks some draws), with on average 0.8,
3.4, 6.8 and 12.3 events kept in the state (at most 18). On a configuration change, goods that lost
their base value are dropped from the events, events left without goods are dropped, and so are
events of another shape (a development save of 0.1.36).

**Cost** (2.1.24, `tests/market_events.lua`, averages of 10, seven full runs, shifted prices
included): the pass with a draw, candidates cached, 0.10 to 0.13 ms in vanilla and 0.12 to 0.36 ms
with Space Age (it was 0.85 and 1.14 ms when every prototype was read at each draw); a due draw
blocked by `max_open` 0.011 to 0.018 ms; at frequency 0 0.005 to 0.008 ms. A price snapshot of 40
quotes costs 0.14 to 0.21 ms without events and 0.14 to 0.23 ms with 20 events on other goods (the
index by key, `storage.market_events.by_key`, finds none; the difference is within run-to-run
noise). The NPC drift salt: 40 full catch-ups of 30 steps cost 1.61 then 1.88 ms in vanilla and 1.87
then 2.06 ms with Space Age, unsalted then salted: about 0.2 µs more per NPC step. Budget: 0.5 ms on
a draw pass, 0.05 ms per pass otherwise.
