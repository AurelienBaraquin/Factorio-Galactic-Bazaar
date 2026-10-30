# Brief

What this project is meant to be: the owner's statement of intent, and the source of truth for
*what* to build. `CLAUDE.md` says how to work, `architecture.md` says how it is built, this says
what for.

Keep it short. Changing the scope, the priorities or the success criteria is a decision: update
this file and record the change with the `adr-new` skill (a decisions-log line is enough for a
small one). Never edit it silently.

## Purpose

Galactic Bazaar is a Factorio mod that turns the game into a galactic industrial economy. Every
flow, state and volume of the game — items, fluids, energy, storage, machine capacity,
logistics — has a tradable counterpart on a simulated market, in both directions: the player can
be supplier or client of any of them. Difficulty moves from physical constraints (belts, ore
patches, space) to economic ones (liquidity, capacity, risk, logistics bandwidth, reputation).
The goal is not to make the game easier, but to move where the challenge lies.

## Users

Experienced Factorio players looking for a new kind of challenge, from vanilla to large overhaul
mods. They must be able to trade from a terminal, automate trading with the circuit network, and
grow from a local broker to a company that outsources production across the galaxy.

## Scope

In scope:

- Prices derived automatically from the recipe graph (vanilla, Space Age and other mods), with an
  interface for other mods to set or override values.
- A dynamic market that reacts to supply and demand: buy/sell spread, price impact of large
  orders, reversion towards a base value.
- A modular terminal: a central hub extended by modules unlocked through research.
- Bidirectional trade of items, fluids, energy, storage and machine capacity.
- Logistics tiers that bound throughput and latency, from orbital capsule to teleporter; the
  teleporter stays bounded.
- Circuit network integration: price signals in, orders out.
- Incoming contracts (NPCs ship inputs, the player delivers outputs) and outsourced production on
  NPC planets with finite capacity.
- Every exchange that spans time — incoming contracts, capacity rental, outsourcing, credit — is one
  contract model: goods each way, a deadline and money terms ([ADR-0015](adr/0015-one-contract-model.md)).
- Reputation, credit and bankruptcy.
- Abstract NPC planets, plus dynamic integration of the real Space Age planets when present.
- Research always runs in the player's own labs; science packs can be bought.

Out of scope (until 1.0):

- Central bank, variable interest rates, inflation, stock depreciation.
- Short selling, hostile takeovers, cartels, antitrust.
- Mercenaries, asset seizure, terminal hacking.
- Penalties on third-party freight stored by the player.
- Insider information or any "guaranteed" arbitrage.

## Priorities

1. Pricing engine and spot market.
2. Terminal, item and energy trade.
3. Logistics tiers and circuit integration.
4. Contracts and reputation.
5. Outsourced production (fabless).
6. Finance: credit, interest, bankruptcy.

## Success criteria

- Milestone M1 is playable: in a new game, vanilla or Space Age, the player buys and sells items
  through the terminal at dynamic prices, with no measurable UPS impact on a medium-sized base.

## Constraints

- Factorio 2.1. Space Age is optional, never required.
- The owner plays without Space Age: Space Age support is validated by automated tests on the
  headless server, not by manual play-testing.
- Solo first; all economy state is scoped by force ([ADR-0001](adr/0001-economy-state-scoped-by-force.md)).
- In-game text ships English and French locales.
- Circuit signals are 32-bit integers (about 2.1 × 10⁹): large amounts must be scaled.
- Lua numbers are doubles: integers are exact up to 2⁵³ (about 9 × 10¹⁵).
- Periodic work is batched across ticks to protect UPS.
- All graphics are produced by AI agents, never by hand. Until 1.0 they are composed from the base
  game's sprites and icons; Space Age graphics are never referenced, since Space Age is optional.

## Open questions

- Success criteria for 1.0, beyond M1 — owner.
