-- The cargo module: an export chest whose content the market buys, and an import chest that
-- receives purchases. Both work when a trading hub of their force is in range (ADR-0005).
-- Placeholder graphics: the steel chest, tinted, with an arrow on the icon.
local function cargo_chest(name, tint, arrow, order)
  local chest = table.deepcopy(data.raw["container"]["steel-chest"])
  chest.name = name
  chest.minable = { mining_time = 0.2, result = name }
  chest.icons = {
    { icon = "__base__/graphics/icons/steel-chest.png", tint = tint },
    { icon = "__base__/graphics/icons/arrows/" .. arrow .. ".png", scale = 0.25, shift = { 8, -8 } },
  }
  chest.icon = nil
  chest.fast_replaceable_group = nil
  chest.next_upgrade = nil
  chest.picture = table.deepcopy(chest.picture)
  for _, layer in pairs(chest.picture.layers or { chest.picture }) do
    if not layer.draw_as_shadow then layer.tint = tint end
  end
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

data:extend({ cargo_chest("gb-export-chest", { 1, 0.65, 0.35, 1 }, "up-arrow", "b[cargo]-a[export]") })
data:extend({ cargo_chest("gb-import-chest", { 0.45, 1, 0.55, 1 }, "down-arrow", "b[cargo]-b[import]") })
