-- Docking bays (#65): chests attached to the nearest hub of their force in range (ADR-0005) that
-- give their hub the cargo shuttle tier (ADR-0014) while they hold enough chemical fuel. Each
-- shuttle shipment burns FUEL_MJ_PER_SHIPMENT of fuel, taken from the bays' items when an order is
-- paid; what a burnt item gives beyond the need stays in the bay's fuel buffer. State lives in
-- storage.docking_bays, with an index of each hub's bays so that a tier read visits only those.
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")

local docking_bay = {}

docking_bay.NAME = "gb-docking-bay"
docking_bay.HUB_RANGE = 10
docking_bay.TIER = "shuttle"
-- Fuel one shuttle rotation burns: one rocket fuel.
docking_bay.FUEL_MJ_PER_SHIPMENT = 100

local MJ = 1e6
-- Below this, fuel still needed counts as burnt (float residue of non-binary fuel values).
local RESIDUE_MJ = 1e-9

-- Attaches a bay to the nearest hub of its force in range, keeping storage.docking_bays.by_hub in
-- step.
local function attach(module)
  hubs.attach_indexed(module, docking_bay.HUB_RANGE, storage.docking_bays.by_hub)
end

-- The fuel value in MJ of one `name` item when it is a chemical fuel, nil otherwise.
local function fuel_mj(name)
  local item = prototypes.item[name]
  if not (item and item.fuel_value > 0) then return nil end
  for _, category in ipairs(item.fuel_categories or {}) do
    if category == "chemical" then return item.fuel_value / MJ end
  end
  return nil
end

--- on_init and on_configuration_changed: creates the state, drops bays that no longer exist and
--- re-attaches the others.
function docking_bay.init()
  storage.docking_bays = storage.docking_bays or { modules = {} }
  local modules = storage.docking_bays.modules
  local gone = {}
  for unit_number, module in pairs(modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do modules[unit_number] = nil end
  storage.docking_bays.by_hub = {}
  for _, module in pairs(modules) do
    module.hub = nil
    attach(module)
  end
end

--- Registers a newly built bay; returns true when the entity was one.
function docking_bay.on_built(entity)
  if entity.name ~= docking_bay.NAME then return false end
  local modules = storage.docking_bays.modules
  if modules[entity.unit_number] then return true end
  local module = { entity = entity, fuel_mj = 0 }
  modules[entity.unit_number] = module
  attach(module)
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed bay; returns true when the unit number was one. Its fuel buffer is lost.
function docking_bay.forget(unit_number)
  local module = storage.docking_bays.modules[unit_number]
  if not module then return false end
  storage.docking_bays.modules[unit_number] = nil
  hubs.unindex(storage.docking_bays.by_hub, module.hub, unit_number)
  return true
end

--- A hub appeared: bays in its range move to it if it is now their nearest hub.
function docking_bay.on_hub_built(hub)
  local nearby = hub.surface.find_entities_filtered({
    name = docking_bay.NAME, force = hub.force, position = hub.position, radius = docking_bay.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.docking_bays.modules[entity.unit_number]
    if module then attach(module) end
  end
end

--- A hub disappeared: its bays look for another hub in range.
function docking_bay.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.docking_bays.modules) do
    if module.hub == hub_unit_number then attach(module) end
  end
end

--- on_forces_merged: bays now belong to the merged force and may use its hubs.
function docking_bay.on_forces_merged()
  for _, module in pairs(storage.docking_bays.modules) do attach(module) end
end

-- The bays of a hub that belong to its force, by unit number (a fixed order on every peer).
local function bays_of(hub_unit_number)
  local hub = hubs.get(hub_unit_number)
  local bays = {}
  if not hub then return bays end
  for unit_number in pairs(storage.docking_bays.by_hub[hub_unit_number] or {}) do
    local module = storage.docking_bays.modules[unit_number]
    if module.entity.valid and module.entity.force == hub.force then bays[#bays + 1] = unit_number end
  end
  table.sort(bays)
  return bays
end

-- The chemical fuel stacks of a bay, any quality, as {name, quality, count, mj}, sorted by name then
-- quality.
local function fuel_stacks(module)
  local stacks = {}
  for _, content in ipairs(module.entity.get_inventory(defines.inventory.chest).get_contents()) do
    local mj = fuel_mj(content.name)
    if mj then
      stacks[#stacks + 1] = { name = content.name, quality = content.quality, count = content.count, mj = mj }
    end
  end
  table.sort(stacks, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.quality < b.quality
  end)
  return stacks
end

--- Fuel in MJ one bay holds: its buffer and its chemical fuel items.
function docking_bay.bay_fuel(module)
  local total = module.fuel_mj
  for _, stack in ipairs(fuel_stacks(module)) do total = total + stack.count * stack.mj end
  return total
end

--- Fuel in MJ the bays of a hub hold: their buffers and their chemical fuel items; with `enough`,
--- counting stops as soon as the total reaches it (what a tier read needs to know).
function docking_bay.fuel(hub_unit_number, enough)
  local total = 0
  for _, unit_number in ipairs(bays_of(hub_unit_number)) do
    local module = storage.docking_bays.modules[unit_number]
    total = total + module.fuel_mj
    if enough and total >= enough then return total end
    for _, stack in ipairs(fuel_stacks(module)) do total = total + stack.count * stack.mj end
    if enough and total >= enough then return total end
  end
  return total
end

-- Burns `need` MJ from a bay: its buffer first, then whole items in name order, the surplus of the
-- last item going to the buffer. Returns what is still needed.
local function burn(module, need)
  local from_buffer = math.min(module.fuel_mj, need)
  module.fuel_mj, need = module.fuel_mj - from_buffer, need - from_buffer
  if need < RESIDUE_MJ then return 0 end
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  for _, stack in ipairs(fuel_stacks(module)) do
    if need <= 0 then break end
    local count = math.min(stack.count, math.ceil(need / stack.mj))
    local removed = inventory.remove({ name = stack.name, count = count, quality = stack.quality })
    local energy = removed * stack.mj
    module.fuel_mj = module.fuel_mj + math.max(0, energy - need)
    need = need - energy
    if need < RESIDUE_MJ then need = 0 end
  end
  return math.max(0, need)
end

freight.register_tier_provider({
  tier = docking_bay.TIER,
  available = function(hub_unit_number)
    return docking_bay.fuel(hub_unit_number, docking_bay.FUEL_MJ_PER_SHIPMENT) >= docking_bay.FUEL_MJ_PER_SHIPMENT
  end,
  can_supply = function(hub_unit_number, shipments)
    local need = shipments * docking_bay.FUEL_MJ_PER_SHIPMENT
    return docking_bay.fuel(hub_unit_number, need) >= need
  end,
  supply = function(hub_unit_number, shipments)
    local need = shipments * docking_bay.FUEL_MJ_PER_SHIPMENT
    for _, unit_number in ipairs(bays_of(hub_unit_number)) do
      if need <= 0 then return end
      need = burn(storage.docking_bays.modules[unit_number], need)
    end
  end,
})

return docking_bay
