-- The docking bay (#65): a chest for chemical fuel that gives its trading hub the cargo shuttle
-- delivery tier while it holds enough fuel. Derived from the steel chest, tinted blue.
local TINT = { 0.45, 0.65, 1, 1 }

local entity = table.deepcopy(data.raw["container"]["steel-chest"])
entity.name = "gb-docking-bay"
entity.icons = { { icon = "__base__/graphics/icons/steel-chest.png", tint = TINT } }
entity.icon = nil
entity.minable = { mining_time = 0.5, result = "gb-docking-bay" }
entity.inventory_size = 10
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
for _, layer in pairs(entity.picture.layers or { entity.picture }) do
  if not layer.draw_as_shadow then layer.tint = TINT end
end

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
