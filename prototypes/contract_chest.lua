-- The contract chest (#76): products put in it are handed over to the force's open incoming
-- contracts. Derived from the steel chest, tinted gold.
local TINT = { 1, 0.85, 0.3, 1 }

local entity = table.deepcopy(data.raw["container"]["steel-chest"])
entity.name = "gb-contract-chest"
entity.icons = { { icon = "__base__/graphics/icons/steel-chest.png", tint = TINT } }
entity.icon = nil
entity.minable = { mining_time = 0.2, result = "gb-contract-chest" }
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
for _, layer in pairs(entity.picture.layers or { entity.picture }) do
  if not layer.draw_as_shadow then layer.tint = TINT end
end

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
