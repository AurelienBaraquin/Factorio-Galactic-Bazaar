-- NPC planets (#83, ADR-0018). Pure Lua: the catalog of abstract planets, each with a distance and
-- specialties — a resource it extracts or a crafting category it serves — that have a finite number
-- of slots. A force reserves slots of a specialty until an end tick; they are free again after it.
-- Reservations are plain tables kept in the force's state.
local planets = {}

-- The abstract planets, for every force. `distance` is in transit units (#84); a slot is one mining
-- drill or one machine of crafting speed 1, abstracted.
planets.CATALOG = {
  { name = "ferrum-prime", distance = 1, specialties = {
    { kind = "resource", name = "iron-ore", slots = 4 },
    { kind = "resource", name = "copper-ore", slots = 2 },
    { kind = "crafting", name = "smelting", slots = 4 },
  } },
  { name = "carbo", distance = 2, specialties = {
    { kind = "resource", name = "coal", slots = 4 },
    { kind = "resource", name = "stone", slots = 3 },
    { kind = "crafting", name = "smelting", slots = 2 },
  } },
  { name = "fabrica-nova", distance = 2, specialties = {
    { kind = "crafting", name = "crafting", slots = 4 },
    { kind = "crafting", name = "advanced-crafting", slots = 2 },
  } },
  { name = "uranos-deep", distance = 4, specialties = {
    { kind = "resource", name = "uranium-ore", slots = 2 },
    { kind = "crafting", name = "chemistry", slots = 2 },
  } },
}

--- The catalog limited to what exists: `exists(kind, name)` tells whether a resource item or a
--- crafting category is in the game. Planets left without a specialty are dropped. Returns a new
--- list; the source is not changed.
function planets.available_catalog(catalog, exists)
  local list = {}
  for _, planet in ipairs(catalog) do
    local specialties = {}
    for _, specialty in ipairs(planet.specialties) do
      if exists(specialty.kind, specialty.name) then
        specialties[#specialties + 1] = { kind = specialty.kind, name = specialty.name, slots = specialty.slots }
      end
    end
    if #specialties > 0 then
      list[#list + 1] = { name = planet.name, distance = planet.distance, specialties = specialties }
    end
  end
  return list
end

--- The planet named `name` in a catalog, and its specialty `kind`/`specialty_name`, or nil.
function planets.find(catalog, name, kind, specialty_name)
  for _, planet in ipairs(catalog) do
    if planet.name == name then
      for _, specialty in ipairs(planet.specialties) do
        if specialty.kind == kind and specialty.name == specialty_name then return planet, specialty end
      end
      return planet, nil
    end
  end
  return nil, nil
end

-- Keeps in place the reservations for which `keep(reservation)` is true, in order; returns the
-- dropped ones.
local function filter(reservations, keep)
  local dropped, kept = {}, 0
  for index = 1, #reservations do
    local reservation = reservations[index]
    reservations[index] = nil
    if keep(reservation) then
      kept = kept + 1
      reservations[kept] = reservation
    else
      dropped[#dropped + 1] = reservation
    end
  end
  return dropped
end

--- Drops the reservations that ended at or before `tick`.
function planets.prune(reservations, tick)
  filter(reservations, function(reservation) return reservation.until_tick > tick end)
end

--- Ends early the reservations of contract `contract_id` (it was settled, abandoned or withdrawn).
function planets.release(reservations, contract_id)
  filter(reservations, function(reservation) return reservation.contract ~= contract_id end)
end

--- Drops the reservations whose specialty is no longer in the catalog (a mod change); returns them,
--- so that the services they back can withdraw their contracts.
function planets.drop_unknown(catalog, reservations)
  return filter(reservations, function(reservation)
    local _, specialty = planets.find(catalog, reservation.planet, reservation.kind, reservation.name)
    return specialty ~= nil
  end)
end

--- Slots of a planet's specialty held by `reservations` at `tick`.
function planets.used(reservations, planet_name, kind, name, tick)
  local used = 0
  for _, reservation in ipairs(reservations) do
    if reservation.planet == planet_name and reservation.kind == kind and reservation.name == name
      and reservation.until_tick > tick then
      used = used + reservation.slots
    end
  end
  return used
end

--- Free slots of a planet's specialty at `tick`, never below 0; nil when the catalog lacks it.
function planets.free(catalog, reservations, planet_name, kind, name, tick)
  local _, specialty = planets.find(catalog, planet_name, kind, name)
  if not specialty then return nil end
  return math.max(0, specialty.slots - planets.used(reservations, planet_name, kind, name, tick))
end

--- Reserves `slots` slots of a planet's specialty from `tick` until `until_tick` for contract
--- `contract_id` (optional), which `release` frees early. Returns the new reservation, appended to
--- `reservations`; or nil and a reason (unknown-planet, unknown-specialty, invalid-slots,
--- invalid-duration, no-capacity).
function planets.reserve(catalog, reservations, planet_name, kind, name, slots, tick, until_tick, contract_id)
  local planet, specialty = planets.find(catalog, planet_name, kind, name)
  if not planet then return nil, "unknown-planet" end
  if not specialty then return nil, "unknown-specialty" end
  if type(slots) ~= "number" or slots < 1 or slots % 1 ~= 0 then return nil, "invalid-slots" end
  if type(until_tick) ~= "number" or until_tick ~= until_tick or until_tick <= tick or until_tick == math.huge then
    return nil, "invalid-duration"
  end
  planets.prune(reservations, tick)
  if planets.free(catalog, reservations, planet_name, kind, name, tick) < slots then return nil, "no-capacity" end
  local reservation = {
    planet = planet_name, kind = kind, name = name, slots = slots, until_tick = until_tick, contract = contract_id,
  }
  reservations[#reservations + 1] = reservation
  return reservation
end

--- Gives a force state its reservation list if it lacks one.
function planets.init(state)
  state.reservations = state.reservations or {}
end

--- Carries a merged force's reservations over to the destination (they back its contracts).
function planets.merge(destination, source)
  planets.init(destination)
  planets.init(source)
  for _, reservation in ipairs(source.reservations) do
    destination.reservations[#destination.reservations + 1] = reservation
  end
end

return planets
