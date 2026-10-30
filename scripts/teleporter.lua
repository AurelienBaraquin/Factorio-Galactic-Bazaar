-- Teleporters (#66): electric buildings attached to the nearest hub of their force in range
-- (ADR-0005) that give their hub the teleporter tier (ADR-0014) while they are powered: a high but
-- bounded throughput for a constant power draw. Without power, a hub's teleporter shipments already
-- queued wait instead of landing. State lives in storage.teleporters, with an index of each hub's
-- teleporters.
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")

local teleporter = {}

teleporter.NAME = "gb-teleporter"
teleporter.HUB_RANGE = 10
teleporter.TIER = "teleporter"
-- A teleporter works while its buffer holds at least this share of its capacity: a network that
-- cannot keep up drains it below.
teleporter.POWERED_SHARE = 0.5

local function attach(module)
  hubs.attach_indexed(module, teleporter.HUB_RANGE, storage.teleporters.by_hub)
end

--- on_init and on_configuration_changed: creates the state, drops teleporters that no longer exist
--- and re-attaches the others.
function teleporter.init()
  storage.teleporters = storage.teleporters or { modules = {} }
  local modules = storage.teleporters.modules
  local gone = {}
  for unit_number, module in pairs(modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do modules[unit_number] = nil end
  storage.teleporters.by_hub = {}
  for _, module in pairs(modules) do
    module.hub = nil
    attach(module)
  end
end

--- Registers a newly built teleporter; returns true when the entity was one.
function teleporter.on_built(entity)
  if entity.name ~= teleporter.NAME then return false end
  local modules = storage.teleporters.modules
  if modules[entity.unit_number] then return true end
  local module = { entity = entity }
  modules[entity.unit_number] = module
  attach(module)
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed teleporter; returns true when the unit number was one.
function teleporter.forget(unit_number)
  local module = storage.teleporters.modules[unit_number]
  if not module then return false end
  storage.teleporters.modules[unit_number] = nil
  hubs.unindex(storage.teleporters.by_hub, module.hub, unit_number)
  return true
end

--- A hub appeared: teleporters in its range move to it if it is now their nearest hub.
function teleporter.on_hub_built(hub)
  local nearby = hub.surface.find_entities_filtered({
    name = teleporter.NAME, force = hub.force, position = hub.position, radius = teleporter.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.teleporters.modules[entity.unit_number]
    if module then attach(module) end
  end
end

--- A hub disappeared: its teleporters look for another hub in range.
function teleporter.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.teleporters.modules) do
    if module.hub == hub_unit_number then attach(module) end
  end
end

--- on_forces_merged: teleporters now belong to the merged force and may use its hubs.
function teleporter.on_forces_merged()
  for _, module in pairs(storage.teleporters.modules) do attach(module) end
end

--- Whether a hub has a powered teleporter of its force: true or false, or nil when it has no
--- teleporter of its force at all.
function teleporter.powered(hub_unit_number)
  local hub = hubs.get(hub_unit_number)
  if not hub then return nil end
  local found = nil
  for unit_number in pairs(storage.teleporters.by_hub[hub_unit_number] or {}) do
    local entity = storage.teleporters.modules[unit_number].entity
    if entity.valid and entity.force == hub.force then
      if entity.energy >= entity.electric_buffer_size * teleporter.POWERED_SHARE then return true end
      found = false
    end
  end
  return found
end

freight.register_tier_provider({
  tier = teleporter.TIER,
  available = function(hub_unit_number) return teleporter.powered(hub_unit_number) == true end,
  delivers = teleporter.powered,
})

return teleporter
