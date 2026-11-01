-- The trading hub: the terminal's central building. Its interface (opened on click) gives access to
-- the market; modules attach to it. It draws a constant amount of power. Rendered graphics: a
-- terminal with a sweeping rooftop dish (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local hub = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
hub.name = "gb-hub"
hub.icons = graphics.icons("gb-hub")
hub.icon = nil
hub.hidden = false
hub.minable = { mining_time = 0.5, result = "gb-hub" }
hub.max_health = 400
hub.subgroup = "galactic-bazaar"
hub.order = "a[hub]"
hub.gui_mode = "none"
hub.allow_copy_paste = false
hub.energy_source = { type = "electric", usage_priority = "secondary-input", buffer_capacity = "200kJ" }
hub.energy_production = "0kW"
hub.energy_usage = "100kW"
hub.picture = nil
hub.animation = graphics.animation("gb-hub")
hub.continuous_animation = true
hub.drawing_box_vertical_extension = 0.8

data:extend({
  { type = "item-subgroup", name = "galactic-bazaar", group = "logistics", order = "z[galactic-bazaar]" },
  hub,
  {
    type = "item",
    name = "gb-hub",
    icons = hub.icons,
    subgroup = "galactic-bazaar",
    order = "a[hub]",
    place_result = "gb-hub",
    stack_size = 10,
  },
  {
    type = "recipe",
    name = "gb-hub",
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "electronic-circuit", amount = 20 },
      { type = "item", name = "steel-plate", amount = 10 },
      { type = "item", name = "iron-gear-wheel", amount = 10 },
    },
    results = { { type = "item", name = "gb-hub", amount = 1 } },
  },
})
