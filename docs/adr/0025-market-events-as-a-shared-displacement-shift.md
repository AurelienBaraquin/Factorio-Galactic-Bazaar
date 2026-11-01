# ADR-0025 — Market events: one galaxy-wide schedule, a displacement shift that only worsens prices

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M8, issue #120); the requirement
  that no public-information strategy gain from events, and the entropy mix, decided by the
  coordinator after the three independent reviews of PR #125; events as pure risks (option 6, no
  bonus for sellers in a shortage) chosen by the owner on 2026-11-01
- **Supersedes**: none

## Context

Issue #120 asks for one-off market events — shortages (a good's price rises and its supply drops),
surpluses, and crises over a family of goods — drawn deterministically and never from the tick,
with a bounded frequency and magnitude set by mod settings, announced in advance when plausible,
shown in an alert, the window and the item detail, without "guaranteed" arbitrage (out of scope in
the brief). They must act through the existing price model (ADR-0003) and the lazy NPC simulation
(ADR-0004).

Markets are kept per force (`storage.forces[i].markets`, ADR-0001), but base values are shared by
every force (`storage.base_values`). An event is a fact about the galaxy, not about one force's money.

Three reviews of PR #125 found sure trades in successive designs. A course fixed at the draw: buy at
the start of a shortage, sell at its end (+35 %). A course drawn as it goes but still readable: the
fade after the end is deterministic (+22 %), and the slope inside a pass gives the goal (up to +31 %).
Prices capped by the plain market's (no purchase below the plain sell price, no sale above the plain
buy price): a purchase in a surplus or a sale in a shortage then paid no spread, so the return of the
force's own displacement to balance became a zero-spread profit (+3 % to +20 %). The coordinator
required that no strategy using all public information (exact prices at any tick, the Events tab,
the notices) gain from events, proven by simulation.

## Options considered

1. **Scale the base value during the event** — jumps at start and end, rebasing twice; a sure trade
   around each jump.
2. **An NPC flow stored in each entry's displacement** — depends on read order and on events already
   forgotten, and its reversion is as predictable as the market's own.
3. **A shift at read time with prices as they are** — any predictable part of the course (fixed path,
   slope, fade) is a trade.
4. **A martingale course plus a spread widening on the reverting side** (first suggestion) — the
   return to zero is certain, so its value must be priced in; a widening of half the remaining shift
   still leaves a holder of goods half the effect.
5. **Prices capped by the plain market's** (the previous version), and its suggested refinement
   (caps taken at the displacement that cannot revert in the trader's favour) — any rule that lets
   one side of the book get better than its plain price gives some round trip a zero-spread exit:
   in a shortage, a long entered at the event's ask exits at an ask-level ceiling; before an
   announced shortage, a long entered at the plain ask exits at that ceiling.
6. **A shift that only makes prices worse**: the buy price is the plain buy price at
   `s + min(shift, 0)`, the sell price the plain sell price at `s + max(shift, 0)`.

And for scope: **per-force events** or **one galaxy-wide schedule** applied to every force's markets.

## Decision

Option 6, with one galaxy-wide schedule: `scripts/core/market_events.lua` (course, draws, salts),
`scripts/core/market.lua` (shifted prices), `scripts/market_events.lua` (state in
`storage.market_events`, a pass every 600 ticks) and `scripts/market.lua` (reads and trades).

- **Guarantee.** At every moment every buy price under an event is at least the plain buy price and
  every sell price at most the plain sell price, at the same own displacement. Any sequence of trades
  therefore does at most as well with an event as the same trades on the plain market, whatever the
  course and whatever is known of it; prices are continuous in the shift. The plain market keeps its
  own behaviour (ADR-0003): the spread, and the return of a force's own displacement to balance,
  which pays once that displacement exceeds the spread — the same with or without an event.
  `spec/core/market_spec.lua` checks the price functions; `spec/core/market_events_spec.lua` checks
  the dominance at every sample of seeded courses with own displacements of 0, ±0.05, ±0.1, ±0.2
  depths that decay and drift, at magnitudes 0.25, 1 and 3, against a clairvoyant trader and six
  strategies (figures in `docs/market.md`).
- **What an event does.** A shortage raises what buyers pay and cuts what can be bought (the bound
  applies to the shifted displacement); a surplus lowers what sellers get. The other side keeps its
  plain price: events are risks, with no bonus for anyone. A producer bonus in a shortage would be
  exactly the exit of a zero-spread round trip, so it cannot coexist with the guarantee. Offered the
  choice between this and loosening the guarantee to keep a bonus for sellers, the owner chose pure
  risks on 2026-11-01 ("Do what you recommend, the mod should be fun"): notices and the Events tab
  therefore read as threats to act on — make what is short, hold back what is in surplus.
- **Course.** Within a segment from tick `t0` and shift `x0`, the shift is
  `G + (x0 - G) 2^(-(t - t0)/h)`, a flow of NPC trades towards goal `G` with the market's half-life
  `h`. The first goal is drawn at the first pass at or after the start; at every later pass of an
  active event it ends early (chance 1/180) or its goal takes a bounded random step within
  [0, ceiling × magnitude], a new segment starting from the shift reached. Players see the range of
  an event's possible effect and the most it may still last. A good has one event at a time: it is
  not drawn again until its last event is forgotten.
- **Randomness.** One Park-Miller state, seeded from the map seed, reseeded at each draw, at each
  pass with an active event and at each minute's salt with the forces' balances and journal sizes
  plus the tick, then advanced three steps: identical on every peer, unknown before it happens, never
  the tick alone. Whether a forecast is called off and an event's first goal are drawn when it
  starts, and later steps at their own pass: neither the console nor a decoded save shows them before.
  The same state draws a salt every minute that every NPC drift roll of the next minute adds, modulo
  1, to its per-key sequence (ADR-0004's sequences were computable from the key and force alone);
  a step's result is still fixed once drawn and independent of read order.
- **Scope: one schedule for the galaxy.** Every force sees the same events, each on its own
  displacement; nothing needs merging. This is an explicit exception to ADR-0001 (economy state keyed
  by force, hard rule 5): `storage.market_events` holds no money, reputation, order or contract of
  any force. Like the base values it is the state of the galaxy the forces trade in; a per-force copy
  would let rival teams see different worlds and would need its own merge rules. ADR-0001 carries an
  amendment pointing here. Notices go only to forces that researched Galactic Bazaar.

## Consequences

- Positive: events cannot be exploited, provably and whatever is known of them; prices stay
  continuous; no per-entry state; deterministic and independent of read order; every existing path
  (spread, impact, liquidity, reversion, telecom feeds, circuit price signals, export chests) goes
  through the shifted prices; the NPC drift is no longer computable in advance.
- Trade-offs accepted: events only hurt — buyers in a shortage, sellers in a surplus — and help no
  one; the player's answer is to make what is short and hold back what is in surplus. Rival forces
  share events. The plain market's reversion of a large own displacement stays a profit, as before
  events (ADR-0003). The NPC price history reads past segments linearly between knots kept every
  minute; a minute without a salt (before the state existed) steps unsalted.
- Follow-up: balancing of frequencies and ranges (M8 balancing); whether the plain market's own
  reversion of large displacements needs a rule of its own (outside this ADR).
