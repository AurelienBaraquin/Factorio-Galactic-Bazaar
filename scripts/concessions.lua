-- Mining concessions (#85, ADR-0019): a force leases slots of a resource a NPC planet extracts
-- (ADR-0018). The lease is a contract that charges the force every period (scripts/contracts.lua);
-- each period the planet ships the slots' units to the hub the lease was taken at, by transit (#84),
-- and the charge is taken only for a period shipped. The slots stay reserved for the term and are
-- released when the contract ends. Leases live in storage.concessions.
local cargo = require("scripts.cargo")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local hubs = require("scripts.hubs")
local offers = require("scripts.core.contract_offers")
local planets = require("scripts.planets")

local concessions = {}

concessions.SWEEP_TICKS = 60

local function leases() return storage.concessions end

--- The terms of a lease of `slots` slots of `resource`: its contract spec, or nil when the resource
--- has no value.
function concessions.terms(planet_name, resource, slots)
  return offers.concession(planet_name, resource, storage.base_values["item/" .. resource], slots)
end

--- Leases one slot of `resource` on `planet_name` for a force, delivered to a hub of its force.
--- Either the lease is made whole (contract accepted, slot reserved) or nothing changes. Returns the
--- contract id, or nil and a reason (unknown-specialty, no-capacity, not-tradeable, no-import-chest,
--- too-many-contracts, insufficient-funds).
function concessions.lease(force_index, hub_unit_number, planet_name, resource)
  local free = planets.free(force_index, planet_name, "resource", resource)
  if not free then return nil, "unknown-specialty" end
  if free < 1 then return nil, "no-capacity" end
  local spec = concessions.terms(planet_name, resource, 1)
  if not spec then return nil, "not-tradeable" end
  if not cargo.has_import(hub_unit_number) then return nil, "no-import-chest" end
  if #contracts.listed(force_index) >= contracts.MAX_LISTED then return nil, "too-many-contracts" end
  if storage.forces[force_index].balance < spec.deposit then return nil, "insufficient-funds" end
  local id = contracts.offer(force_index, spec)
  if not id then return nil, "not-tradeable" end
  local until_tick = game.tick + spec.duration_ticks + 1
  if not planets.reserve(force_index, planet_name, "resource", resource, 1, until_tick, id) then
    contracts.decline(force_index, id)
    return nil, "no-capacity"
  end
  local accepted, reason = contracts.accept(force_index, id)
  if not accepted then
    contracts.decline(force_index, id)
    planets.release(force_index, id)
    return nil, reason
  end
  leases()[id] = { force_index = force_index, hub = hub_unit_number, planet = planet_name, resource = resource,
    slots = 1 }
  return id
end

-- Whether a period of a lease can ship: its hub exists and has an import chest.
local function can_serve(_, contract)
  local lease = leases()[contract.id]
  return lease ~= nil and hubs.get(lease.hub) ~= nil and cargo.has_import(lease.hub)
end

-- Serves one period of a lease: ships its units from the planet, at the price per unit the charge
-- pays. Returns whether it shipped.
local function serve(force_index, contract)
  local lease = leases()[contract.id]
  local units = offers.concession_units(lease.slots)
  local goods = { { kind = "item", name = lease.resource, count = units } }
  return (planets.ship(force_index, lease.hub, lease.planet, goods, contract.id, contract.charge / units))
end
contracts.register_service("concession", can_serve, serve)

--- on_nth_tick(SWEEP_TICKS): leases whose contract ended release their slots and are forgotten.
function concessions.on_sweep_tick()
  local ended = {}
  for id, lease in pairs(leases()) do
    local contract = contracts.get(lease.force_index, id)
    if not (contract and contract.state == core.ACTIVE) then ended[#ended + 1] = id end
  end
  table.sort(ended)
  for _, id in ipairs(ended) do
    planets.release(leases()[id].force_index, id)
    leases()[id] = nil
  end
end

--- on_forces_merged: the merged force's leases now belong to the destination, with their contracts.
function concessions.on_forces_merged(event)
  for _, lease in pairs(leases()) do
    if lease.force_index == event.source_index then lease.force_index = event.destination.index end
  end
end

--- on_init and on_configuration_changed: creates the state, then voids the leases whose planet
--- specialty is gone (`dropped`, from planets.init: {[force_index] = {reservation...}}), the force
--- not being at fault.
function concessions.init(dropped)
  storage.concessions = storage.concessions or {}
  for force_index, reservations in pairs(dropped or {}) do
    for _, reservation in ipairs(reservations) do
      local id = reservation.contract
      if id and leases()[id] then contracts.void(force_index, id) end
    end
  end
  concessions.on_sweep_tick()
end

return concessions
