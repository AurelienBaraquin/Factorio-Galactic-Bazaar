# ADR-0008 — A quality's value is the normal value times a factor per quality level

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

With a quality mod (Space Age), every item exists in several qualities, and a better one is rarer
and stronger. Issue #11 asks for one value per quality level when quality is active, and no change
without it. Recipes are the same for every quality, so the production graph (ADR-0002) cannot tell
qualities apart.

## Options considered

1. **Derive the cost from the quality mechanics** — expected crafts and recycling loops per level,
   from module quality chances and each quality's `next_probability`. Closest to the game, but it
   depends on the modules and loops a player builds, which the mod cannot know.
2. **One factor per step of the quality chain** (`next` links). Ignores that Space Age's legendary is
   level 5 although it is the fourth step, a gap the game itself uses for its bonuses.
3. **A factor per quality level**: `value = normal value × FACTOR_PER_LEVEL ^ level`, read from each
   quality prototype's `level`, so modded qualities are priced too.

## Decision

Option 3, with `FACTOR_PER_LEVEL = 3` to start (Space Age: uncommon ×3, rare ×9, epic ×27,
legendary ×243). Each quality other than normal trades on its own market, keyed `<key>@<quality>`;
normal keys stay as they were, so saves and fluids (which have no quality) are unchanged. Hidden
qualities are not tradeable. Quality stacks sell from export chests and the player's inventory at
their quality's price; purchases stay normal quality.

## Consequences

- Positive: no change without a quality mod; modded qualities work; one constant to tune.
- Trade-offs accepted: the factor does not follow how cheaply a given factory makes quality; base
  value overrides (ADR-0007) apply to the normal value and so to every quality; buying a chosen
  quality needs an interface (later).
- Follow-up: tune the factor with play-testing; quality purchases with the market window.
