-- NPC planets (#83, ADR-0018): the runtime side of scripts/core/planets.lua. The catalog — the
-- abstract planets and the real planets of the loaded game (#87) — limited to the resources and
-- crafting categories that exist, is shared by all forces
-- (storage.planets, rebuilt on configuration change); each force's reservations live in its state
-- (storage.forces[i].reservations). Goods shipped from a planet travel by transit (#84).
local core = require("scripts.core.planets")
local freight = require("scripts.freight")
local random = require("scripts.core.random")
local transit = require("scripts.core.transit")

local planets = {}

local function exists(kind, name)
  if kind == "resource" then return prototypes.item[name] ~= nil end
  return prototypes.recipe_category[name] ~= nil
end

-- The force's next draw for transit losses, from its own state in storage: deterministic on every
-- peer, and independent of when the force ships.
local function draw(force_index)
  local states = storage.planet_rng
  local state, value = random.next(states[force_index] or random.seed(force_index * 104729 + 3))
  states[force_index] = state
  return value
end

--- on_forces_merged: the merged force's draw state goes, so that a force created later under its
--- index starts afresh.
function planets.on_forces_merged(event)
  storage.planet_rng[event.source_index] = nil
end

local HOME = "nauvis"

-- The value of a surface property on a space location, or the property's default.
local function property(location, name)
  local properties = location.surface_properties or {}
  if properties[name] ~= nil then return properties[name] end
  local prototype = prototypes.surface_property[name]
  return prototype and prototype.default_value or 0
end

local function meets(location, conditions)
  for _, condition in ipairs(conditions) do
    local value = property(location, condition.property)
    if value < (condition.min or -math.huge) or value > (condition.max or math.huge) then return false end
  end
  return true
end

local function sorted_keys(set)
  local list = {}
  for key in pairs(set) do list[#list + 1] = key end
  table.sort(list)
  return list
end

-- The items the resources a planet generates are mined into (fluids left out).
local function planet_resources(location)
  local items = {}
  local settings = location.map_gen_settings
  local entities = settings and settings.autoplace_settings and settings.autoplace_settings.entity
  for entity_name in pairs(entities and entities.settings or {}) do
    local entity = prototypes.entity[entity_name]
    local mined = entity and entity.type == "resource" and entity.mineable_properties.products or {}
    for _, product in ipairs(mined) do
      if product.type == "item" then items[product.name] = true end
    end
  end
  return sorted_keys(items)
end

-- The planet's signature crafting category: of the visible recipes it can host and the home planet
-- cannot, the category most of them belong to (ties to the first name); none without such recipes.
-- With Space Age: Vulcanus metallurgy, Fulgora electromagnetics, Gleba organic, Aquilo cryogenics.
local function planet_categories(location, home)
  local counts = {}
  for _, recipe in pairs(prototypes.recipe) do
    local conditions = recipe.surface_conditions
    if conditions and not recipe.hidden and meets(location, conditions) and not (home and meets(home, conditions)) then
      for _, category in ipairs(recipe.categories) do counts[category] = (counts[category] or 0) + 1 end
    end
  end
  local best
  for _, category in ipairs(sorted_keys(counts)) do
    if not best or counts[category] > counts[best] then best = category end
  end
  return { best }
end

-- Catalog entries of the real planets of the loaded game (#87), by name.
local function real_planets()
  local home = prototypes.space_location[HOME]
  local origin = home or { distance = 0, orientation = 0 }
  local entries = {}
  for _, name in ipairs(sorted_keys(prototypes.space_location)) do
    local location = prototypes.space_location[name]
    if location.type == "planet" and name ~= HOME then
      entries[#entries + 1] = core.real_planet(name, core.distance_units(origin, location),
        planet_resources(location), planet_categories(location, home))
    end
  end
  return entries
end

--- on_init and on_configuration_changed: builds the catalog for the loaded game and drops the
--- reservations of specialties no longer in it. Returns the dropped reservations of each force
--- ({[force_index] = {reservation...}}), for the services that back them to withdraw.
function planets.init()
  local catalog = {}
  for _, planet in ipairs(core.CATALOG) do catalog[#catalog + 1] = planet end
  for _, planet in ipairs(real_planets()) do catalog[#catalog + 1] = planet end
  storage.planets = core.available_catalog(catalog, exists)
  storage.planet_rng = storage.planet_rng or {}
  local dropped = {}
  for force_index, state in pairs(storage.forces) do
    if state.reservations then dropped[force_index] = core.drop_unknown(storage.planets, state.reservations) end
  end
  return dropped
end

--- The localised name of a catalog planet: the game's own name for a real planet, the mod's for an
--- abstract one, the internal name when neither has a key.
function planets.caption(planet_name)
  local planet = core.find(storage.planets, planet_name)
  local key = planet and planet.real and "space-location-name." or "gb-planets.name-"
  return { "?", { key .. planet_name }, planet_name }
end

--- The catalog of NPC planets: {{name, distance, real, specialties = {{kind, name, slots}...}}...}.
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
--- land after the planet's transit delay, each good less a share lost on the way, drawn from the
--- force's state. `paid` (optional) is the price the force paid per unit shipped, so that what
--- cannot land is sold back. Returns what `freight.ship` returns, or false and "unknown-planet".
function planets.ship(force_index, hub_unit_number, planet_name, goods, contract_id, paid)
  local planet = core.find(storage.planets, planet_name)
  if not planet then return false, "unknown-planet" end
  local shares, unit_costs = {}, {}
  for index = 1, #goods do
    shares[index] = transit.loss_share(planet.distance, draw(force_index))
    -- The force paid for the units shipped, so each arriving unit cost it a little more.
    unit_costs[index] = paid and paid / (1 - shares[index]) or 0
  end
  return freight.ship(force_index, hub_unit_number, goods, contract_id,
    { distance = planet.distance, shares = shares, unit_costs = unit_costs })
end

--- Frees early the slots a force reserved for contract `contract_id`.
function planets.release(force_index, contract_id)
  local reservations = reservations_of(force_index)
  if reservations then core.release(reservations, contract_id) end
end

return planets
