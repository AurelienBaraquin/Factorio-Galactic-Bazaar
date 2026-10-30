# ADR-0010 — Prices reach the circuit network through script-written constant combinators

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M2)
- **Supersedes**: none

## Context

Issue #23 asks for prices and the balance on the circuit network, with a 32-bit scaling decided in
an ADR and documented for the player. Circuit values are int32. Probes on 2.1.24: writing a
constant combinator's whole `filters` list of 380 signals costs about 0.5 ms, while `set_slot`
costs about 70 µs per slot (31 ms for 380); quoting every price of a force costs 1.1–1.9 ms.

## Options considered

1. **One combinator with a mode switch** — needs an interface; buy and sell prices of the same
   item cannot share one signal anyway.
2. **Two combinators, buy prices and sell prices**, each emitting every tradeable item and fluid
   plus the balance on a virtual signal of the mod.
3. **Hub outputs** — wiring the hub itself; it is an energy interface with no circuit connection.

## Decision

Option 2. Prices are emitted in **milli-credits** (credits × 1000), so goods as cheap as water
(0.001 credit) read 1 and items up to 2.1 million credits fit; the balance is emitted in **whole
credits**; values are rounded and clamped to int32 (`scripts/core/signals.lua`). Normal quality
only; electricity has no signal. A force's prices are snapshot every 10 s, quoted 40 per pass
(every 6 ticks) from the key lists captured at the start, so that no tick pays for all of them; a
snapshot's version changes only when a price changed. A combinator has two script-owned sections:
the prices, rewritten with a full `filters` write when the version changed (at most one such write
per pass, up to ten combinators visited per pass), and the balance, one slot set live at each visit.
Combinators are not operable by players, foreign sections are replaced, and they stay silent without
a powered hub of their force in range (ADR-0005).

## Consequences

- Positive: any circuit design can read every price and the balance; the cost is bounded per pass
  (at most 0.5 ms for a rewrite, 0.3 ms on average during a rebuild, measured on 2.1.24).
- Trade-offs accepted: prices are up to 10 s old plus 0.1 s per combinator to rewrite; prices above
  2.1 million credits are capped; the balance is capped at 2.1 billion credits; reading every price
  keeps every market entry of a force with a combinator up to date in storage.
- Follow-up: the telecommunications research (#25) sets the freshness; quality prices if needed.
