-- The cargo module: an export chest whose content the market buys, and an import chest that
-- receives purchases. Both work when a trading hub of their force is in range (ADR-0005).
-- Rendered graphics (prototypes/graphics.lua): a crate with the trading band and an arrow on its lid.
local graphics = require("prototypes.graphics")

local function cargo_chest(name, order)
  local chest = table.deepcopy(data.raw["container"]["steel-chest"])
  chest.name = name
  chest.minable = { mining_time = 0.2, result = name }
  chest.icons = graphics.icons(name)
  chest.icon = nil
  chest.fast_replaceable_group = nil
  chest.next_upgrade = nil
  chest.picture = graphics.sprite(name)
  chest.water_reflection = nil
  local item = {
    type = "item",
    name = name,
    icons = chest.icons,
    subgroup = "galactic-bazaar",
    order = order,
    place_result = name,
    stack_size = 50,
  }
  local recipe = {
    type = "recipe",
    name = name,
    enabled = false,
    energy_required = 2,
    ingredients = {
      { type = "item", name = "steel-chest", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 5 },
    },
    results = { { type = "item", name = name, amount = 1 } },
  }
  return chest, item, recipe
end

data:extend({ cargo_chest("gb-export-chest", "b[cargo]-a[export]") })
data:extend({ cargo_chest("gb-import-chest", "b[cargo]-b[import]") })
