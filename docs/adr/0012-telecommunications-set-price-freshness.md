# ADR-0012 — Telecommunications research sets how fresh the prices a force sees are

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M2)
- **Supersedes**: none

## Context

Issue #25 asks for a telecommunications branch whose level sets the freshness of the prices shown
and emitted, level 2 unlocking history and trends. Prices were shown live in the market window and
emitted every 10 s by price combinators (ADR-0010).

## Options considered

1. **Delay trades too** — orders execute at the stale price. Realistic latency, but a player could
   buy at a stale low price after the market moved: free money.
2. **Delay what is seen, execute live** — the window's list and the price combinators show prices
   at most one period old; a trade's preview and execution use the live price.
3. **Hide prices below a level** — blunt, and the market window would be useless early.

## Decision

Option 2. A force sees prices through a feed (`storage.forces[i].feed`) quoted again only when older
than its period: 30 s without research, 10 s with `gb-telecommunications-1`, 2 s with
`gb-telecommunications-2`. The price combinators take their snapshot on the same period. Level 2
also shows the trend column of the market window and a history line (a sparkline of the last 30 NPC
steps) for the selected item. The trade preview in the window and every execution use live prices,
so the feed never creates or loses money.

## Consequences

- Positive: research has a clear economic value (react faster); no arbitrage between seen and real
  prices; the feed caps how often the window and combinators quote the market.
- Trade-offs accepted: early on, the list can differ from the preview by up to 30 s of market
  movement; at level 2, price combinators rebuild their snapshot every 2 s after the previous build
  ends and rewrite one combinator per pass, so with many combinators the last ones lag about 0.1 s
  each (0.04–0.05 ms per tick with 30 combinators); the feed is cleared when base values change.
- Follow-up: higher levels (contracts, M4) may add forecast or other planets' prices.
