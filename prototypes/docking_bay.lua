-- The docking bay (#65): a chest for chemical fuel that gives its trading hub the cargo shuttle
-- delivery tier while it holds enough fuel. Derived from the steel chest, with rendered graphics: a
-- crate with the logistics band and a landing pad (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local entity = table.deepcopy(data.raw["container"]["steel-chest"])
entity.name = "gb-docking-bay"
entity.icons = graphics.icons("gb-docking-bay")
entity.icon = nil
entity.minable = { mining_time = 0.5, result = "gb-docking-bay" }
entity.inventory_size = 10
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
entity.picture = graphics.sprite("gb-docking-bay")
entity.water_reflection = nil

data:extend({
  entity,
  {
    type = "item",
    name = "gb-docking-bay",
    icons = entity.icons,
    subgroup = "galactic-bazaar",
    order = "b[delivery]-a[docking-bay]",
    place_result = "gb-docking-bay",
    stack_size = 10,
  },
  {
    type = "recipe",
    name = "gb-docking-bay",
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "steel-plate", amount = 50 },
      { type = "item", name = "advanced-circuit", amount = 20 },
      { type = "item", name = "electric-engine-unit", amount = 10 },
    },
    results = { { type = "item", name = "gb-docking-bay", amount = 1 } },
  },
})
