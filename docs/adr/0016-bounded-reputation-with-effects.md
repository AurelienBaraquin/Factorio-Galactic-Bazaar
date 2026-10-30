# ADR-0016 — Bounded reputation per force, with freight and contract-size effects

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M4)
- **Supersedes**: the reputation merge rule of ADR-0015 (reputations added up)

## Context

ADR-0015 gave each force a reputation score, +1 per fulfilled contract and −1 per failed one,
unbounded and summed on force merge. #77 asks for effects (lower freight fees, access to larger
contracts) and for the score in the market window. The engine review noted that an unbounded score
makes any effect unbounded, and that summing on merge lets a throwaway force build a score and hand
it to another.

## Options considered

1. **One score per force or per counterparty** — per counterparty would let offers favour partners,
   but counterparties are cosmetic names today; one score per force keeps the rule and the window
   simple.
2. **Bounds and decay** — bounds make every effect bounded; decay over time would push players to
   keep taking contracts, but adds a periodic pass and makes the score hard to read. Bounds only.
3. **Merge rule** — sum (exploitable), keep the destination's (a bad score could be shed by merging
   into a fresh force), the minimum (merging a fresh force would wipe a good score), or the
   destination's less the source's debt.

## Decision

One score per force (`storage.forces[i].reputation`), kept within **[−20, 20]**
(`scripts/core/reputation.lua`). Effects, linear in the score:

- **Freight fees** × (1 − 0.025 × score): half price at 20, one and a half times at −20.
- **Contract size**: incoming offers aim at a product value of 1 000 × (1 + 0.1 × score) credits,
  at least half of it (×3 at 20); the reward scales with the batch.

On a force merge the destination keeps its own score **less the source's debt** (only a negative
score follows). No decay. The market window shows the score, its effects in the tooltip.

## Consequences

- Positive: every effect is bounded; a score can be neither farmed in a throwaway force nor shed by
  merging; the rule is pure and unit-tested.
- Trade-offs accepted: no decay, so a high score once earned stays until failures lower it; one
  score for all counterparties.
- Follow-up: capacity rental (#78) may read the same score.
