-- Registry of trading hubs (storage.hubs), kept in step with their construction and destruction.
local hubs = {}

hubs.NAME = "gb-hub"

-- Every way an entity can appear; each is registered with a name filter in control.lua.
hubs.BUILT_EVENTS = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_entity_cloned,
}
hubs.FILTER = { { filter = "name", name = hubs.NAME } }

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

function hubs.on_built(event)
  local entity = event.entity or event.destination
  if entity and entity.valid and entity.name == hubs.NAME then register(entity) end
end

function hubs.on_object_destroyed(event)
  if event.type == defines.target_type.entity then storage.hubs[event.useful_id] = nil end
end

--- The registered hub entity with this unit number, or nil.
function hubs.get(unit_number)
  local hub = storage.hubs[unit_number]
  return hub and hub.entity.valid and hub.entity or nil
end

return hubs
