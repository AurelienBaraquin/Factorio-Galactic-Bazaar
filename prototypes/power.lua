-- The power module: two substations that trade electricity with the market (ADR-0009). Both are
-- electric-energy-interfaces with the "tertiary" priority, like accumulators: the export substation
-- only charges from the network's surplus, the import substation only discharges when the network
-- lacks power. The script settles their buffers with the market and sizes them for the force's
-- research level, which caps the throughput (flow limits cannot be changed at runtime, so they are
-- set here for the highest level, 40 MW; the buffer is the first level's 10 MW for 5 s). Rendered
-- graphics: a transformer with the trading band and an arrow for the flow (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local SUBSTATIONS = {
  { name = "gb-power-export", input = "40MW", output = "0W", order = "d[power]-a[export]" },
  { name = "gb-power-import", input = "0W", output = "40MW", order = "d[power]-b[import]" },
}

for _, spec in ipairs(SUBSTATIONS) do
  local entity = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
  entity.name = spec.name
  entity.icons = graphics.icons(spec.name)
  entity.icon = nil
  entity.hidden = false
  entity.minable = { mining_time = 0.5, result = spec.name }
  entity.max_health = 300
  entity.subgroup = "galactic-bazaar"
  entity.order = spec.order
  entity.gui_mode = "none"
  entity.allow_copy_paste = false
  entity.energy_source = {
    type = "electric", usage_priority = "tertiary", buffer_capacity = "50MJ",
    input_flow_limit = spec.input, output_flow_limit = spec.output,
  }
  entity.energy_production = "0kW"
  entity.energy_usage = "0kW"
  entity.picture = graphics.sprite(spec.name)
  entity.drawing_box_vertical_extension = graphics.vertical_extension(spec.name)
  data:extend({
    entity,
    {
      type = "item",
      name = spec.name,
      icons = entity.icons,
      subgroup = "galactic-bazaar",
      order = spec.order,
      place_result = spec.name,
      stack_size = 10,
    },
    {
      type = "recipe",
      name = spec.name,
      enabled = false,
      energy_required = 5,
      ingredients = {
        { type = "item", name = "steel-plate", amount = 10 },
        { type = "item", name = "electronic-circuit", amount = 10 },
        { type = "item", name = "copper-cable", amount = 20 },
      },
      results = { { type = "item", name = spec.name, amount = 1 } },
    },
  })
end
