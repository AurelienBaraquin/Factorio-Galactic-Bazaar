-- Storage rental buildings (#119): the vault uplink sends what is put in it to the vaults the force
-- rents from NPCs at its hub; the rental warehouse holds the goods a NPC stores with the force,
-- closed to the player by the script. Both are derived from the steel chest, tinted.
local function chest(name, tint, order, ingredients)
  local entity = table.deepcopy(data.raw["container"]["steel-chest"])
  entity.name = name
  entity.icons = { { icon = "__base__/graphics/icons/steel-chest.png", tint = tint } }
  entity.icon = nil
  entity.minable = { mining_time = 0.2, result = name }
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  for _, layer in pairs(entity.picture.layers or { entity.picture }) do
    if not layer.draw_as_shadow then layer.tint = tint end
  end
  return {
    entity,
    {
      type = "item",
      name = name,
      icons = entity.icons,
      subgroup = "galactic-bazaar",
      order = order,
      place_result = name,
      stack_size = 50,
    },
    {
      type = "recipe",
      name = name,
      enabled = false,
      energy_required = 2,
      ingredients = ingredients,
      results = { { type = "item", name = name, amount = 1 } },
    },
  }
end

data:extend(chest("gb-vault-uplink", { 0.75, 0.55, 1, 1 }, "a[cargo]-f[vault-uplink]", {
  { type = "item", name = "steel-chest", amount = 1 },
  { type = "item", name = "electronic-circuit", amount = 5 },
}))
data:extend(chest("gb-rental-warehouse", { 0.55, 0.7, 1, 1 }, "a[cargo]-g[rental-warehouse]", {
  { type = "item", name = "steel-chest", amount = 1 },
  { type = "item", name = "electronic-circuit", amount = 5 },
}))
