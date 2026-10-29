-- The trading hub: the terminal's central building. Its interface (opened on click) gives access to
-- the market; modules attach to it. It draws a constant amount of power.
local TINT = { 0.55, 0.8, 1, 1 }

local hub = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
hub.name = "gb-hub"
hub.icons = { { icon = "__base__/graphics/icons/accumulator.png", tint = TINT } }
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
hub.picture = table.deepcopy(hub.picture)
for _, layer in pairs(hub.picture.layers or { hub.picture }) do
  if not layer.draw_as_shadow then layer.tint = TINT end
end

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
