-- The contract chest (#76): products put in it are handed over to the force's open incoming
-- contracts. Derived from the steel chest, with rendered graphics: a crate with the finance band, a
-- document slot and a seal (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local entity = table.deepcopy(data.raw["container"]["steel-chest"])
entity.name = "gb-contract-chest"
entity.icons = graphics.icons("gb-contract-chest")
entity.icon = nil
entity.minable = { mining_time = 0.2, result = "gb-contract-chest" }
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
entity.picture = graphics.sprite("gb-contract-chest")
entity.water_reflection = nil
entity.drawing_box_vertical_extension = graphics.vertical_extension("gb-contract-chest")

data:extend({
  entity,
  {
    type = "item",
    name = "gb-contract-chest",
    icons = entity.icons,
    subgroup = "galactic-bazaar",
    order = "a[cargo]-d[contract]",
    place_result = "gb-contract-chest",
    stack_size = 50,
  },
  {
    type = "recipe",
    name = "gb-contract-chest",
    enabled = false,
    energy_required = 2,
    ingredients = {
      { type = "item", name = "steel-chest", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 5 },
    },
    results = { { type = "item", name = "gb-contract-chest", amount = 1 } },
  },
})
