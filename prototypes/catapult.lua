-- The electromagnetic catapult (#67): a 48-slot chest that sells its contents to the market in bulk,
-- one shot at a time, each shot drawing energy from a capacitor: a hidden electric-energy-interface
-- the script places under the catapult, charging from the electric network. Rendered graphics: a
-- crate with the logistics band and a coil-wound launch rail (prototypes/graphics.lua).
local graphics = require("prototypes.graphics")

local catapult = table.deepcopy(data.raw["container"]["steel-chest"])
catapult.name = "gb-catapult"
catapult.icons = graphics.icons("gb-catapult")
catapult.icon = nil
catapult.minable = { mining_time = 1, result = "gb-catapult" }
catapult.inventory_size = 48
catapult.max_health = 600
catapult.fast_replaceable_group = nil
catapult.next_upgrade = nil
catapult.picture = graphics.sprite("gb-catapult")
catapult.water_reflection = nil
catapult.drawing_box_vertical_extension = graphics.vertical_extension("gb-catapult")

local capacitor = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
capacitor.name = "gb-catapult-capacitor"
capacitor.hidden = true
capacitor.flags = { "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game",
  "placeable-off-grid", "not-flammable", "not-repairable", "not-in-kill-statistics" }
capacitor.minable = nil
capacitor.collision_mask = { layers = {} }
-- The catapult's own footprint, so that poles power it exactly where they power the catapult.
capacitor.collision_box = table.deepcopy(catapult.collision_box)
capacitor.selection_box = nil
capacitor.gui_mode = "none"
capacitor.allow_copy_paste = false
capacitor.energy_source = {
  type = "electric", usage_priority = "secondary-input", buffer_capacity = "100MJ", input_flow_limit = "30MW",
}
capacitor.energy_production = "0kW"
capacitor.energy_usage = "0kW"
capacitor.picture = { filename = "__core__/graphics/empty.png", width = 1, height = 1 }
capacitor.localised_name = { "entity-name.gb-catapult" }

data:extend({
  catapult,
  capacitor,
  {
    type = "item",
    name = "gb-catapult",
    icons = catapult.icons,
    subgroup = "galactic-bazaar",
    order = "a[cargo]-c[catapult]",
    place_result = "gb-catapult",
    stack_size = 10,
  },
  {
    type = "recipe",
    name = "gb-catapult",
    enabled = false,
    energy_required = 20,
    ingredients = {
      { type = "item", name = "steel-plate", amount = 100 },
      { type = "item", name = "advanced-circuit", amount = 30 },
      { type = "item", name = "accumulator", amount = 10 },
      { type = "item", name = "electric-engine-unit", amount = 20 },
    },
    results = { { type = "item", name = "gb-catapult", amount = 1 } },
  },
})
