-- Registry of trading hubs (storage.hubs), kept in step with their construction and destruction.
local hubs = {}

hubs.NAME = "gb-hub"

local function register(entity)
  storage.hubs[entity.unit_number] = { entity = entity }
  script.register_on_object_destroyed(entity)
end

--- on_init and on_configuration_changed: creates the registry and drops hubs that no longer exist
--- (for example after their prototype was removed).
function hubs.init()
  storage.hubs = storage.hubs or {}
  local gone = {}
  for unit_number, hub in pairs(storage.hubs) do
    if not hub.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do storage.hubs[unit_number] = nil end
end

--- Registers a newly built hub; returns true when the entity was a hub.
function hubs.on_built(entity)
  if entity.name ~= hubs.NAME then return false end
  register(entity)
  return true
end

--- Forgets a destroyed hub; returns true when the unit number was a hub.
function hubs.forget(unit_number)
  if not storage.hubs[unit_number] then return false end
  storage.hubs[unit_number] = nil
  return true
end

--- The registered hub entity with this unit number, or nil.
function hubs.get(unit_number)
  local hub = storage.hubs[unit_number]
  return hub and hub.entity.valid and hub.entity or nil
end

--- Whether a hub has power to trade.
function hubs.has_power(hub)
  return hub.energy > 0
end

--- Unit number of the nearest registered hub of the entity's force on its surface within `range`
--- tiles (ADR-0005); with `powered_only`, the nearest one that has power. Ties go to the lowest unit
--- number, so every peer picks the same hub.
function hubs.nearest(entity, range, powered_only)
  local best, best_distance
  local candidates = entity.surface.find_entities_filtered({
    name = hubs.NAME, force = entity.force, position = entity.position, radius = range,
  })
  for _, hub in ipairs(candidates) do
    if hubs.get(hub.unit_number) and (not powered_only or hubs.has_power(hub)) then
      local dx, dy = hub.position.x - entity.position.x, hub.position.y - entity.position.y
      local distance = dx * dx + dy * dy
      if not best or distance < best_distance or (distance == best_distance and hub.unit_number < best.unit_number) then
        best, best_distance = hub, distance
      end
    end
  end
  return best and best.unit_number or nil
end

return hubs
