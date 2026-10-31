-- NPC planets (#83, ADR-0018): the runtime side of scripts/core/planets.lua. The catalog, limited to
-- the resources and crafting categories of the loaded game, is shared by all forces
-- (storage.planets, rebuilt on configuration change); each force's reservations live in its state
-- (storage.forces[i].reservations). Goods shipped from a planet travel by transit (#84).
local core = require("scripts.core.planets")
local freight = require("scripts.freight")
local transit = require("scripts.core.transit")

local planets = {}

local function exists(kind, name)
  if kind == "resource" then return prototypes.item[name] ~= nil end
  return prototypes.recipe_category[name] ~= nil
end

--- on_init and on_configuration_changed: builds the catalog for the loaded game and drops the
--- reservations of specialties no longer in it. Returns the dropped reservations of each force
--- ({[force_index] = {reservation...}}), for the services that back them to withdraw.
function planets.init()
  storage.planets = core.available_catalog(core.CATALOG, exists)
  local dropped = {}
  for force_index, state in pairs(storage.forces) do
    if state.reservations then dropped[force_index] = core.drop_unknown(storage.planets, state.reservations) end
  end
  return dropped
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

--- Reserves slots of a planet's specialty for a force until `until_tick`, for contract
--- `contract_id` (optional). Returns the reservation, or nil and a reason (see
--- scripts/core/planets.lua, or no-force).
function planets.reserve(force_index, planet_name, kind, name, slots, until_tick, contract_id)
  local reservations = reservations_of(force_index)
  if not reservations then return nil, "no-force" end
  return core.reserve(storage.planets, reservations, planet_name, kind, name, slots, game.tick, until_tick,
    contract_id)
end

--- The transit terms from a planet: {delay_ticks, max_loss}, or nil when it is not in the catalog.
function planets.transit_terms(planet_name)
  local planet = core.find(storage.planets, planet_name)
  return planet and transit.terms(planet.distance)
end

--- Ships goods from a planet to a hub of a force for contract `contract_id`, through freight: they
--- land after the planet's transit delay, less a share lost on the way, drawn from the contract and
--- the tick. Returns what `freight.ship` returns, or false and "unknown-planet".
function planets.ship(force_index, hub_unit_number, planet_name, goods, contract_id)
  local planet = core.find(storage.planets, planet_name)
  if not planet then return false, "unknown-planet" end
  local origin = { distance = planet.distance, seed = (contract_id or 0) * 7919 + game.tick }
  return freight.ship(force_index, hub_unit_number, goods, contract_id, origin)
end

--- Frees early the slots a force reserved for contract `contract_id`.
function planets.release(force_index, contract_id)
  local reservations = reservations_of(force_index)
  if reservations then core.release(reservations, contract_id) end
end

return planets
