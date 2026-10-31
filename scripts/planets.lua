-- NPC planets (#83, ADR-0018): the runtime side of scripts/core/planets.lua. The catalog, limited to
-- the resources and crafting categories of the loaded game, is shared by all forces
-- (storage.planets, rebuilt on configuration change); each force's reservations live in its state
-- (storage.forces[i].reservations).
local core = require("scripts.core.planets")

local planets = {}

local function exists(kind, name)
  if kind == "resource" then return prototypes.item[name] ~= nil end
  return prototypes.recipe_category[name] ~= nil
end

--- on_init and on_configuration_changed: builds the catalog for the loaded game.
function planets.init()
  storage.planets = core.available_catalog(core.CATALOG, exists)
end

--- The catalog of NPC planets: {{name, distance, specialties = {{kind, name, slots}...}}...}.
function planets.catalog()
  return storage.planets
end

local function reservations_of(force_index)
  local state = storage.forces[force_index]
  return state and state.reservations
end

--- Free slots of a planet's specialty for a force now, or nil when there is no such specialty or
--- force.
function planets.free(force_index, planet_name, kind, name)
  local reservations = reservations_of(force_index)
  if not reservations then return nil end
  return core.free(storage.planets, reservations, planet_name, kind, name, game.tick)
end

--- Reserves slots of a planet's specialty for a force until `until_tick`. Returns the reservation,
--- or nil and a reason (see scripts/core/planets.lua, or no-force).
function planets.reserve(force_index, planet_name, kind, name, slots, until_tick)
  local reservations = reservations_of(force_index)
  if not reservations then return nil, "no-force" end
  return core.reserve(storage.planets, reservations, planet_name, kind, name, slots, game.tick, until_tick)
end

return planets
