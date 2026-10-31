-- The rental assembler (#78): an assembling machine that works only for counterparties renting it.
-- Derived from assembling machine 2, tinted teal; no module slots, and beacons may change only its
-- speed, consumption and pollution, so that its products stay what the contract counts.
local TINT = { 0.45, 0.9, 0.85, 1 }

local entity = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
entity.name = "gb-rental-assembler"
entity.icons = { { icon = "__base__/graphics/icons/assembling-machine-2.png", tint = TINT } }
entity.icon = nil
entity.minable = { mining_time = 0.2, result = "gb-rental-assembler" }
entity.fast_replaceable_group = nil
entity.next_upgrade = nil
entity.module_slots = 0
entity.allowed_effects = { "consumption", "speed", "pollution" }
for _, layer in pairs(entity.graphics_set.animation.layers or { entity.graphics_set.animation }) do
  if not layer.draw_as_shadow then layer.tint = TINT end
end

data:extend({
  entity,
  {
    type = "item",
    name = "gb-rental-assembler",
    icons = entity.icons,
    subgroup = "galactic-bazaar",
    order = "a[cargo]-e[rental]",
    place_result = "gb-rental-assembler",
    stack_size = 50,
  },
  {
    type = "recipe",
    name = "gb-rental-assembler",
    enabled = false,
    energy_required = 2,
    ingredients = {
      { type = "item", name = "assembling-machine-2", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 10 },
    },
    results = { { type = "item", name = "gb-rental-assembler", amount = 1 } },
  },
})
