# Prototype snippets (verified against Factorio 2.1.24 prototype API)

All property names below were checked in `prototype-api.json` 2.1.24 and/or copied from the shapes
used in `wube/factorio-data` (base). Always prefer **deepcopy of a base prototype** for entities with
graphics: it keeps sprites, wire connection points, sounds and LED offsets valid.

```lua
-- prototypes/terminal.lua  (required from data.lua)
local PREFIX = "gb-"
```

## Item

`ItemPrototype`: only `stack_size` (+ `name`, `type`) is required. Useful: `icon`/`icons`/`icon_size`
(default 64), `subgroup`, `order`, `place_result`, `weight`, `flags`, `auto_recycle` (default true —
set `false` for currency/token items so the recycler mod does not generate a self-recycling recipe),
`default_import_location` (Space Age, default `"nauvis"`).

```lua
data:extend({
  {
    type = "item",
    name = "gb-terminal",
    icon = "__base__/graphics/icons/steel-chest.png",   -- placeholder until own art exists
    subgroup = "storage",
    order = "z[gb]-a[terminal]",
    place_result = "gb-terminal",
    stack_size = 10,
  },
})
```

## Recipe (2.1 shape)

```lua
data:extend({
  {
    type = "recipe",
    name = "gb-terminal",
    enabled = false,                     -- unlocked by technology
    energy_required = 5,                 -- seconds, default 0.5
    categories = {"crafting"},           -- 2.1: array; `category` was REMOVED (2.0 used category = "crafting")
    ingredients = {
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "electronic-circuit", amount = 10},
    },
    results = {{type = "item", name = "gb-terminal", amount = 1}},
  },
})
```

Product fields worth knowing for pricing: `amount` or `amount_min`/`amount_max`,
`independent_probability` (2.1 name; **2.0 called it `probability`**), `shared_probability = {min, max}`
(2.1, one roll shared by several products), `extra_count_fraction`, `ignored_by_productivity`,
`ignored_by_stats`. 2.1 also adds `recycle_to_ingredients_of`, `raise_on_crafted`, `can_set_quality`,
and quality ranges on ingredients/products (`quality_min`, `quality_max`, `quality_change`).

## Technology

```lua
data:extend({
  {
    type = "technology",
    name = "gb-bazaar",
    icon = "__base__/graphics/technology/circuit-network.png",
    icon_size = 256,
    prerequisites = {"circuit-network"},
    effects = {
      {type = "unlock-recipe", recipe = "gb-terminal"},
      -- Shows a script-driven effect (e.g. logistics tier 1) in the tech GUI; does nothing by itself.
      {type = "nothing", effect_description = {"gb-modifier.logistics-tier", "1"}},
    },
    unit = {
      count = 100,
      ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
      time = 15,
    },
  },
})
```

- `unit` needs `ingredients` and `time` plus exactly one of `count` / `count_formula` (infinite techs:
  `max_level = "infinite"`, `count_formula = "2^(L-1)*1000"`).
- Instead of `unit`, a trigger tech: `research_trigger = {type = "craft-item", item = "iron-plate", count = 50}`.
  Trigger types (2.1): `mine-entity`, `craft-item`, `craft-fluid`, `send-item-to-orbit`,
  `capture-spawner`, `build-entity`, `create-space-platform`, `scripted`.
- `scripted` trigger: `research_trigger = {type = "scripted", trigger_description = {"gb-tech.first-trade"}}`,
  completed at runtime with `force.script_trigger_research("gb-first-trade")`.
- Science packs from Space Age (`metallurgic-science-pack`, ...) only under `if mods["space-age"]`.
- Detect our own tech at runtime via `on_research_finished` (`event.research.name`) and
  `force.technologies["gb-bazaar"].researched` — re-derive tiers in `on_configuration_changed`, since
  "the game resets recipes and technologies any time mods, prototypes, or startup settings change".

## Container (hub storage)

```lua
local hub = table.deepcopy(data.raw["container"]["steel-chest"])
hub.name = "gb-terminal"
hub.minable = {mining_time = 0.5, result = "gb-terminal"}
hub.inventory_size = 48                 -- REQUIRED on ContainerPrototype
-- inventory_type: "normal" | "with_bar" (default) | "with_filters_and_bar" | "with_custom_stack_size" | "with_weight_limit"
hub.inventory_type = "with_filters_and_bar"
-- 2.1: ContainerPrototype.picture is a Sprite4Way (was Sprite in 2.0); deepcopy keeps it valid.
data:extend({hub})
```

For a multi-tile hub, set `collision_box`/`selection_box` (e.g. `{{-1.4,-1.4},{1.4,1.4}}` /
`{{-1.5,-1.5},{1.5,1.5}}` for 3x3) and provide matching graphics.

## Electric energy interface (buy/sell electricity)

`ElectricEnergyInterfacePrototype`: required `energy_source` (an `ElectricEnergySource`:
`type = "electric"`, required `usage_priority`, optional `buffer_capacity`, `input_flow_limit`,
`output_flow_limit`, `drain`). Optional `energy_production`, `energy_usage` (Energy strings; internally
J/tick = W / 60), `gui_mode` (`"all"|"none"|"admins"`, default `"none"`), `picture`/`pictures`/`animation`.
`ElectricUsagePriority`: `primary-input`, `primary-output`, `secondary-input`, `secondary-output`,
`tertiary`, `solar`, `lamp`, `dynamic`.

```lua
-- A hidden power port placed by script next to the hub. Base game has the same pattern:
-- "hidden-electric-energy-interface" in base/prototypes/entity/entities.lua.
data:extend({
  {
    type = "electric-energy-interface",
    name = "gb-power-port",
    icon = "__base__/graphics/icons/accumulator.png",
    hidden = true,
    flags = {"not-blueprintable", "not-deconstructable", "not-on-map", "placeable-off-grid"},
    max_health = 150,
    collision_box = {{0, 0}, {0, 0}},
    selection_box = {{0, 0}, {0, 0}},
    selectable_in_game = false,
    energy_source = {
      type = "electric",
      usage_priority = "tertiary",        -- acts as buffer: sells surplus / buys deficit like an accumulator
      buffer_capacity = "10MJ",
      input_flow_limit = "10MW",
      output_flow_limit = "10MW",
    },
    energy_production = "0W",
    energy_usage = "0W",
    gui_mode = "none",
    picture = {filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1},
  },
})
```

Runtime control of an EEI (`power_production`, `power_usage`, `energy`, `electric_buffer_size`,
`electric_interface_mode`) is in the `factorio-runtime` skill.

## Constant combinator (circuit output port)

`ConstantCombinatorPrototype` requires `activity_led_light_offsets` and
`circuit_wire_connection_points` (4-way tuples) — deepcopy the base one.

```lua
local port = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
port.name = "gb-signal-port"
port.minable = {mining_time = 0.1, result = "gb-signal-port"}
data:extend({port})
```

Decider/arithmetic combinators work the same way (`data.raw["decider-combinator"]["decider-combinator"]`).
An assembling machine is `data.raw["assembling-machine"]["assembling-machine-1"]`; give it its own
`crafting_categories` and a dedicated `recipe-category` prototype if the mod needs a "trade" machine.

## Custom input (hotkey)

```lua
data:extend({
  {
    type = "custom-input",
    name = "gb-toggle-market",
    key_sequence = "CONTROL + SHIFT + M",   -- REQUIRED
    consuming = "none",                     -- default
    action = "lua",                         -- default: raises an event with the same name
    -- include_selected_prototype = true,   -- event gets the hovered prototype
  },
})
-- runtime: script.on_event("gb-toggle-market", function(e) ... end)
-- locale: [controls] gb-toggle-market=Toggle Galactic Bazaar
```

## Mod data (pass data-stage results to runtime)

```lua
data:extend({
  {
    type = "mod-data",
    name = "gb-base-prices",
    data_type = "galactic-bazaar.prices",
    data = { ["iron-plate"] = 1.0, ["copper-plate"] = 1.0 },   -- dictionary string -> AnyBasic
  },
})
-- runtime: prototypes.mod_data["gb-base-prices"].data["iron-plate"]  (LuaModData, read-only)
```

Use it for hand-tuned seed prices that other mods may override in their own `data-updates`.

## Settings prototypes (settings.lua)

```lua
data:extend({
  {type = "double-setting", name = "gb-price-multiplier", setting_type = "startup",
   default_value = 1.0, minimum_value = 0.01, maximum_value = 100, order = "a"},
  {type = "int-setting", name = "gb-update-interval", setting_type = "runtime-global",
   default_value = 60, minimum_value = 1, maximum_value = 3600, order = "b"},
  {type = "bool-setting", name = "gb-show-tooltips", setting_type = "runtime-per-user",
   default_value = true, order = "c"},
  {type = "string-setting", name = "gb-pricing-mode", setting_type = "startup",
   default_value = "recipe", allowed_values = {"recipe", "flat"}, order = "d"},
})
```

## Base assets

- Icons: `__base__/graphics/icons/<name>.png` (e.g. `steel-chest.png`, `constant-combinator.png`,
  `accumulator.png`, `solar-panel.png`), 64 px.
- Technology icons: `__base__/graphics/technology/<name>.png`, 256 px (`icon_size = 256`).
- Empty sprite: `__core__/graphics/empty.png` (1x1).
- Validate a sprite path at runtime with `helpers.is_valid_sprite_path("item/iron-plate")`.
