-- The teleporter (#66): an electric building that gives its trading hub the teleporter delivery
-- tier while powered, for a constant 20 MW draw. Derived from the base electric-energy-interface,
-- with a rendered animation: a field ring turning around a warp core (prototypes/graphics.lua). Its
-- intake is capped a little above its draw, so that a network that cannot keep up drains its buffer
-- (and a fresh one fills in seconds rather than in one tick).
local graphics = require("prototypes.graphics")

local entity = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
entity.name = "gb-teleporter"
entity.icons = graphics.icons("gb-teleporter")
entity.icon = nil
entity.hidden = false
entity.minable = { mining_time = 1, result = "gb-teleporter" }
entity.max_health = 1000
entity.subgroup = "galactic-bazaar"
entity.order = "b[delivery]-b[teleporter]"
entity.gui_mode = "none"
entity.allow_copy_paste = false
entity.energy_source = {
  type = "electric", usage_priority = "secondary-input", buffer_capacity = "40MJ", input_flow_limit = "24MW",
}
entity.energy_production = "0kW"
entity.energy_usage = "20MW"
entity.picture = nil
entity.animation = graphics.animation("gb-teleporter")
entity.continuous_animation = true
entity.drawing_box_vertical_extension = 0.8

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
