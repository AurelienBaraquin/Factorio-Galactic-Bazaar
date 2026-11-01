# ADR-0026 — Contract pay follows work and the market's spread, not the goods' value

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M8, issue #122: "the mod should be
  fun"); the shortage offers from the coordinator's proposal
- **Supersedes**: none. Amends [ADR-0017](0017-capacity-rental-with-installments.md) (how rent is
  priced), [ADR-0016](0016-bounded-reputation-with-effects.md) (which contracts move reputation) and
  the incoming contract terms of [ADR-0015](0015-one-contract-model.md)'s first use (#76)

## Context

The balancing pass of #122 plays typical progressions through the real core modules
([balance.md](../balance.md)). It found three rules that break the economy:

- A machine rental paid 30 % of its products' value. The machine only runs; the counterparty
  supplies everything, and the guarantee comes back. That made a risk-free 50 % of the guarantee an
  hour, growing with the recipe's value (2.2 million credits a term for a spidertron): four rental
  assemblers in mid-game earned 1.1 million an hour against 158 000 from exports, and a 100 000 loan
  at 10 % an hour funded it.
- Each fulfilled rental gave +1 reputation: four idle machines took a force from 10 to the maximum
  in 30 minutes, with nothing at stake. ADR-0024 had already ruled that passive income earns none.
- An incoming contract paid at most the value crafting adds (products minus ingredients). The
  valuation prices machine time at 0.1 credit a second, so most recipes add about 0.5 % of their
  products' value: a median reward of about 5 credits for 1 000 credits of products, a dead channel.

Separately, the coordinator asked whether market shortages could reward production through
contracts, without a reward that buying the goods could earn (events are pure risks, ADR-0025).

## Options considered

Rent: (1) keep a share of the products' value with a cap on rent over guarantee — still grows with
the recipe; (2) the value crafting adds, as incoming contracts — near zero; (3) **a rate per second
of crafting the rental promises**, whatever the recipe.

Reputation of rentals: (1) keep +1; (2) **none, like warehouse rentals and service contracts**.

Incoming reward: (1) keep the cap; (2) the labour share alone — buying the products and selling the
ingredients would then pay up to 30 % of a contract, a pump of 12 offers an hour; (3) **the value
crafting adds plus a share of what the market's spread takes from that round trip**, so the round
trip still loses at base prices.

Shortages: (1) a reward bonus while goods are short — half the events are announced 5 minutes
ahead, so a force could buy the goods before at the plain price and deliver them during the
shortage; (2) **more offers for goods in shortage**, on the usual terms.

## Decision

- **Rent** = `RENT_PER_SECOND` (0.5 credit) × seconds of crafting at speed 1 the rental promises
  (crafts × recipe time): 540 credits a 30-minute term for a rental assembler, about a mining
  drill's ore sold. The guarantee keeps following the goods' value.
- **Rentals are passive**: a new optional contract field `passive` (set on rental offers) gives no
  reputation on fulfilment; failing still costs 1, like `custody`.
- **Incoming reward** per craft = min(`LABOR_SHARE` × P, P − I + `SPREAD_SHARE` (0.5) × spread / 2
  × (P + I)), P and I the products' and ingredients' base values. Buying P and selling I on a
  balanced market loses at least P − I + spread / 2 × (P + I) plus the freight fee, so half the
  spread stays as the margin.
- **Shortage offers**: while a market event pushes a good's price up by `SHORTAGE_DEPTHS` (0.1
  depths) or more, an incoming offer names a recipe making such a good with chance
  `SHORTAGE_CHANCE` (0.5), on the usual terms.

## Consequences

- Positive: rentals and incoming contracts become a side channel of a few thousand credits an hour
  (a quarter of exports at most, checked by `spec/balance_spec.lua`); reputation comes only from
  delivering goods yourself, the maximum taking 100 minutes of contracts; crafting contracts pay
  about 5 % of their products (median of all vanilla candidates) instead of 0.5 %; shortages bring work, not free money.
- Trade-offs accepted: rentals of dear recipes ask a large guarantee for the same rent, so players
  decline them (the machine is offered again 5 minutes later); NPC drift can still make buying the
  products of an incoming contract pay a little (from about 0.8σ on each side), bounded by the offer
  rate; a shortage changes which offers come, not their price.
- Saves: contracts already offered or active keep the terms stored with them (their reward, and +1
  reputation for a rental without `passive`); only offers made after the update follow these rules.
  No migration.
