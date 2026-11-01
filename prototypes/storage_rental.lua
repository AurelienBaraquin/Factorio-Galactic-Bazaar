-- Storage rental buildings (#119): the vault uplink sends what is put in it to the vaults the force
-- rents from NPCs at its hub; the rental warehouse holds the goods a NPC stores with the force,
-- closed to the player by the script. Both are derived from the steel chest, with rendered graphics:
-- crates with the finance band, an uplink antenna or a warehouse roof (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local function chest(name, order, ingredients)
  local entity = table.deepcopy(data.raw["container"]["steel-chest"])
  entity.name = name
  entity.icons = graphics.icons(name)
  entity.icon = nil
  entity.minable = { mining_time = 0.2, result = name }
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  entity.picture = graphics.sprite(name)
  entity.water_reflection = nil
  entity.drawing_box_vertical_extension = graphics.vertical_extension(name)
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

data:extend(chest("gb-vault-uplink", "a[cargo]-f[vault-uplink]", {
  { type = "item", name = "steel-chest", amount = 1 },
  { type = "item", name = "electronic-circuit", amount = 5 },
}))
data:extend(chest("gb-rental-warehouse", "a[cargo]-g[rental-warehouse]", {
  { type = "item", name = "steel-chest", amount = 1 },
  { type = "item", name = "electronic-circuit", amount = 5 },
}))
