# ADR-0002 — Base value of items and fluids from the production graph

- **Status**: Accepted
- **Date**: 2026-10-29
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

Every item and fluid needs a base value in credits that the market (dynamic prices, spread, NPC
supply and demand) starts from. It must work for vanilla, Space Age and other mods without a
hand-written price list, so it is derived from the prototypes. The graph is not a tree: recipes
have several products and random amounts (uranium processing gives 0.7 % uranium-235), catalysts
(Kovarex), cycles (barrel fill and empty, recycling), and some raw materials only exist in one place
(asteroids, a heavy-oil sea). The result must be deterministic, finite and positive, and fast
enough to recompute on every configuration change.

## Options considered

1. **Hand-tuned price table** — full control, but breaks with any other mod and every game update.
2. **Cost-based least fixed point, cost split in proportion to the products' values** — no value
   leaks around cycles. Tried on the real graphs: the shares depend on the values being computed,
   so there are many fixed points (uranium-235 ended at any value below its Kovarex price) and the
   iteration did not converge on vanilla even after 5000 iterations; damping changed the Space Age
   result by up to 19 %.
3. **Cost-based least fixed point, cost split equally among a recipe's products** — the shares do
   not depend on values, so the problem is monotone: values only decrease, the iteration converges
   to one answer whatever the order. A rare product takes the same share of cost for far fewer
   units, so rarity shows. Its flaw — value leaking through a recipe that unpacks what another one
   packs — is handled by dropping those unpacking recipes.

## Decision

Option 3. The graph is built at runtime from `prototypes` in `on_init` and
`on_configuration_changed` (after every mod's data stage), by `scripts/core/recipe_graph.lua`:

- **Recipes**: amounts are expected amounts (`amount` or the mean of `amount_min`/`amount_max`,
  plus `extra_count_fraction`, times `independent_probability × (shared max − shared min)`);
  catalysts are netted out; cost = crafting time × `TIME_COST` (0.1 credit/s).
- **Excluded**, with the reason kept: `recycling` category, `parameter`, `hidden`, unreachable
  (neither enabled nor unlocked by a technology), `inverse` (exactly undoes another recipe, like
  emptying a barrel), `no-net-output`.
- **Sources**: each resource becomes a mining recipe costing mining time × `MINING_COST`
  (1 credit/s), with its required fluid counted per 10 operations as the game does; water is
  pumped at `TILE_FLUID_COST` (0.001 credit/unit).
- **Fallback sources**: trees, rocks, fish, plants, asteroid chunks and the other tile fluids. A
  second pass lets them price only what the main graph left without a value, so a source tied to
  one place never undercuts a general production chain.

`scripts/core/valuation.lua` then iterates: value of a key = min over recipes producing it of
(cost + input values) / number of products / expected amount, with a floor of 10⁻⁶. Keys still
without a value are not tradeable and are logged.

## Consequences

- Positive: works with any mod; deterministic; measured on 2.1.24 at 13 ms (vanilla) and 34 ms
  (Space Age) for graph and values, converging in 13 and 16 iterations; only steam (made by
  boilers) and the depleted uranium fuel cell (made by burning) stay unpriced.
- Trade-offs accepted: the equal split undervalues a common product when a rare co-product has a
  cheaper source (uranium-238 carries half of uranium processing although uranium-235 comes from
  Kovarex); boiler outputs and burnt results have no value; base values do not depend on the planet.
- Follow-up: overrides by other mods and settings (#10), quality multipliers (#11), planet-specific
  values when the fabless milestone adds planets (M5).
