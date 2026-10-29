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

return hubs
