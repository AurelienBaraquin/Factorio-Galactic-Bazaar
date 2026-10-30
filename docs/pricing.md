# Pricing: base values

How every item and fluid gets its base value in credits, the starting point of market prices. The
reasoning and the alternatives rejected are in [ADR-0002](adr/0002-base-value-from-the-production-graph.md);
this page describes what the code does now.

## Pipeline

| Step | Code | Runs |
|---|---|---|
| Copy the prototypes into plain tables (recipes, mined sources, tile fluids, rocket launches, tradeable keys) | `scripts/recipe_graph.lua` | `on_init`, `on_configuration_changed` |
| Build the production graph: expected amounts, catalyst netting, exclusions, main / fallback / natural tiers | `scripts/core/recipe_graph.lua` | same |
| Compute values: propagation with an ancestor guard, tier by tier, from the fixed values of the overrides | `scripts/core/valuation.lua` | same |
| Apply overrides and the global multiplier | `scripts/core/overrides.lua`, `scripts/pricing.lua` | same, and after every remote override call |
| Store and read values | `scripts/pricing.lua` (`storage.base_values`, `pricing.base_value(kind, name)`) | same |

Keys are `item/<name>` and `fluid/<name>`. Tradeable keys are every item and fluid that is not
hidden, not a parameter and not `spawnable` (blueprints, planners, remotes, wires). One of them
without a value is not tradeable; the list is written to `factorio-current.log`.

Tiers: the **main** graph (crafting recipes, resource mining, water, rocket launches), then the
**fallback** (planet-bound processes such as scrap recycling, other tile fluids), then **natural**
sources (trees, rocks, fish, plants, asteroid chunks). Each later tier only prices keys the earlier
ones left without a value.

## Parameters

| Constant | Value | Meaning |
|---|---|---|
| `recipe_graph.TIME_COST` | 0.1 | credits per second of crafting time (recipe energy) |
| `recipe_graph.MINING_COST` | 1 | credits per second of mining time, for resources and natural sources |
| `recipe_graph.TILE_FLUID_COST` | 0.001 | credits per unit of pumped tile fluid |
| `recipe_graph.PRIMARY_TILE_FLUIDS` | `water` | tile fluids pumped in the main graph; the others are fallback sources |
| `valuation.MIN_VALUE` | 10⁻⁶ | floor of any value |

They are constants. Mods and players adjust values through the multiplier and the overrides below.

## Global multiplier

The startup setting `gb-value-multiplier` (`settings.lua`, default 1, from 0.01 to 100) scales
every base value, and so every price. Values fixed by an override stay exactly as set.

## Overrides by other mods

Another mod changes base values through the remote interface `galactic-bazaar`
([ADR-0007](adr/0007-value-overrides-as-fixed-sources.md)). An override is a fixed source of the
valuation: no recipe changes it, and every product made from the key follows. Overrides persist
in `storage.value_overrides` and are reapplied whenever base values are rebuilt.

| Call | Effect |
|---|---|
| `remote.call("galactic-bazaar", "set_value", kind, name, credits)` | fixes the value of `kind`/`name` (`"item"` or `"fluid"`) to `credits`, exactly, multiplier ignored |
| `remote.call("galactic-bazaar", "scale_value", kind, name, factor)` | multiplies the value the graph gives the key by `factor` (then the multiplier applies) |
| `remote.call("galactic-bazaar", "clear_value", kind, name)` | removes the override of the key |
| `remote.call("galactic-bazaar", "get_value", kind, name)` | the current base value in credits, or `nil` when the key has none |

Each call raises an error when `kind`/`name` is not a tradeable item or fluid (unknown, hidden, a
parameter or a cursor-only tool) or when `credits`/`factor` is not a positive finite number;
nothing changes then. Each change recomputes every base value: 17 ms in vanilla, 47 ms with Space
Age (2.1.24), so call it from `on_init` or `on_configuration_changed`, not every tick. An override
of a key that stops being tradeable (its mod removed) is kept but ignored, and logged.

```lua
-- In another mod's control.lua; that mod declares an optional dependency on galactic-bazaar.
script.on_init(function()
  if remote.interfaces["galactic-bazaar"] then
    remote.call("galactic-bazaar", "set_value", "item", "my-rare-ore", 50)
  end
end)
```

## Reference values (Factorio 2.1.24)

| Key | Vanilla | Space Age |
|---|---|---|
| `item/iron-ore` | 1 | 1 |
| `item/iron-plate` | 1.32 | 1.24 |
| `item/electronic-circuit` | 3.43 | 2.26 |
| `item/processing-unit` | 95.3 | 64.2 |
| `fluid/crude-oil` | 0.1 | 0.1 |
| `item/uranium-238` / `item/uranium-235` | 11.3 / 40.0 | 11.2 / 39.5 |
| `fluid/heavy-oil` | 0.141 | 0.057 (coal liquefaction) |
| `item/holmium-ore` | — | 4.33 (scrap recycling) |

Space Age makes many products cheaper because it adds faster recipes (foundry casting, coal
liquefaction with its steam). Unpriced: `fluid/steam` (vanilla) and `fluid/fusion-plasma` (Space
Age), made by machines rather than recipes; `item/depleted-uranium-fuel-cell` (made by burning);
`item/pistol` (no reachable recipe).
