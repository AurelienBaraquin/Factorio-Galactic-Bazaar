-- The teleporter (#66): an electric building that gives its trading hub the teleporter delivery
-- tier while powered, for a constant 20 MW draw. Derived from the base electric-energy-interface,
-- tinted violet.
local TINT = { 0.75, 0.45, 1, 1 }

local entity = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
entity.name = "gb-teleporter"
entity.icons = { { icon = "__base__/graphics/icons/accumulator.png", tint = TINT } }
entity.icon = nil
entity.hidden = false
entity.minable = { mining_time = 1, result = "gb-teleporter" }
entity.max_health = 1000
entity.subgroup = "galactic-bazaar"
entity.order = "b[delivery]-b[teleporter]"
entity.gui_mode = "none"
entity.allow_copy_paste = false
entity.energy_source = { type = "electric", usage_priority = "secondary-input", buffer_capacity = "40MJ" }
entity.energy_production = "0kW"
entity.energy_usage = "20MW"
entity.picture = table.deepcopy(entity.picture)
for _, layer in pairs(entity.picture.layers or { entity.picture }) do
  if not layer.draw_as_shadow then layer.tint = TINT end
end

data:extend({
  entity,
  {
    type = "item",
    name = "gb-teleporter",
    icons = entity.icons,
    subgroup = "galactic-bazaar",
    order = "b[delivery]-b[teleporter]",
    place_result = "gb-teleporter",
    stack_size = 5,
  },
  {
    type = "recipe",
    name = "gb-teleporter",
    enabled = false,
    energy_required = 30,
    ingredients = {
      { type = "item", name = "processing-unit", amount = 100 },
      { type = "item", name = "low-density-structure", amount = 50 },
      { type = "item", name = "steel-plate", amount = 200 },
    },
    results = { { type = "item", name = "gb-teleporter", amount = 1 } },
  },
})
