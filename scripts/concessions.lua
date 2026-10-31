-- Mining concessions (#85) and outsourced production (#86), ADR-0019: a force leases a slot of a
-- resource a NPC planet extracts, or books a slot of a crafting category it serves for one of its
-- recipes (ADR-0018). The lease is a contract that charges the force every period
-- (scripts/contracts.lua); each period the planet ships its units (ore, or the recipe's products) to
-- the hub the lease was taken at, by transit (#84), and the charge is taken only for a period
-- shipped. The slots stay reserved for the term and are
-- released when the contract ends. Leases live in storage.concessions.
local account = require("scripts.core.account")
local cargo = require("scripts.cargo")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local offers = require("scripts.core.contract_offers")
local planets = require("scripts.planets")

local concessions = {}

concessions.SWEEP_TICKS = 60
-- Research that unlocks leasing an ore slot, and booking a crafting slot (#88).
concessions.CONCESSION_TECHNOLOGY = "gb-planetary-concessions"
concessions.OUTSOURCING_TECHNOLOGY = "gb-outsourcing"

--- Whether a force has researched `technology`.
function concessions.researched(force, technology)
  local found = force.technologies[technology]
  return found ~= nil and found.researched
end

local function leases() return storage.concessions end

--- The terms of a lease of `slots` slots of `resource`: its contract spec, or nil when the resource
--- has no value.
function concessions.terms(planet_name, resource, slots)
  return offers.concession(planet_name, resource, storage.base_values["item/" .. resource], slots)
end

-- Makes a lease whole or not at all: checks the slot, the hub, the window and the funds, then offers
-- the contract, reserves the slot and accepts. `specialty` = {kind, name} is the planet's slot;
-- `spec` the contract; `item` and `units` what each period ships.
local function make_lease(force_index, hub_unit_number, planet_name, specialty, spec, item, units)
  if not cargo.has_import(hub_unit_number) then return nil, "no-import-chest" end
  if #contracts.listed(force_index) >= contracts.MAX_LISTED then return nil, "too-many-contracts" end
  if account.available(storage.forces[force_index]) < spec.deposit then return nil, "insufficient-funds" end
  local id = contracts.offer(force_index, spec)
  if not id then return nil, "not-tradeable" end
  local until_tick = game.tick + spec.duration_ticks + 1
  if not planets.reserve(force_index, planet_name, specialty.kind, specialty.name, 1, until_tick, id) then
    contracts.decline(force_index, id)
    return nil, "no-capacity"
  end
  local accepted, reason = contracts.accept(force_index, id)
  if not accepted then
    contracts.decline(force_index, id)
    planets.release(force_index, id)
    return nil, reason
  end
  leases()[id] = { force_index = force_index, hub = hub_unit_number, planet = planet_name, item = item, units = units }
  return id
end

-- Free slots of a planet's specialty for a force, or nil and a refusal reason.
local function free_slot(force_index, planet_name, kind, name)
  local free = planets.free(force_index, planet_name, kind, name)
  if not free then return nil, "unknown-specialty" end
  if free < 1 then return nil, "no-capacity" end
  return free
end

--- Leases one slot of `resource` on `planet_name` for a force, delivered to a hub of its force.
--- Either the lease is made whole (contract accepted, slot reserved) or nothing changes. Returns the
--- contract id, or nil and a reason (not-researched, unknown-specialty, no-capacity, not-tradeable,
--- no-import-chest, too-many-contracts, insufficient-funds).
function concessions.lease(force_index, hub_unit_number, planet_name, resource)
  if not concessions.researched(game.forces[force_index], concessions.CONCESSION_TECHNOLOGY) then
    return nil, "not-researched"
  end
  local free, refusal = free_slot(force_index, planet_name, "resource", resource)
  if not free then return nil, refusal end
  local spec = concessions.terms(planet_name, resource, 1)
  if not spec then return nil, "not-tradeable" end
  return make_lease(force_index, hub_unit_number, planet_name, { kind = "resource", name = resource }, spec,
    resource, offers.concession_units(1))
end

-- The recipe of a booking as {energy, product, amount}, or nil and a reason: one of the force's
-- enabled recipes, of the category, with one sure item product in a whole amount (#86).
local function bookable(force, planet_name, category, recipe_name)
  local recipe = recipe_name and force.recipes[recipe_name]
  if not recipe then return nil, "no-recipe" end
  if not recipe.enabled or recipe.hidden then return nil, "recipe-locked" end
  local in_category = false
  for _, name in ipairs(recipe.prototype.categories) do
    if name == category then in_category = true end
  end
  if not in_category then return nil, "wrong-category" end
  if not planets.can_host(planet_name, recipe.prototype) then return nil, "wrong-planet" end
  local product = incoming.sole_product(recipe.products)
  if not product then return nil, "not-craftable" end
  return { energy = recipe.energy, product = product.name, amount = product.amount }
end

--- Books one crafting slot of `category` on `planet_name` for a force's recipe `recipe_name`: the
--- planet buys the ingredients, crafts and ships the products to a hub of the force every period
--- (#86). Made whole or not at all. Returns the contract id, or nil and a reason (those of `lease`,
--- no-recipe, recipe-locked, wrong-category, wrong-planet, not-craftable, too-slow).
function concessions.book(force_index, hub_unit_number, planet_name, category, recipe_name)
  if not concessions.researched(game.forces[force_index], concessions.OUTSOURCING_TECHNOLOGY) then
    return nil, "not-researched"
  end
  local free, refusal = free_slot(force_index, planet_name, "crafting", category)
  if not free then return nil, refusal end
  local recipe, reason = bookable(game.forces[force_index], planet_name, category, recipe_name)
  if not recipe then return nil, reason end
  local units = offers.outsourcing_units(recipe.energy, recipe.amount, 1)
  if units < 1 then return nil, "too-slow" end
  local spec = offers.outsourcing(planet_name, recipe, storage.base_values["item/" .. recipe.product], 1)
  if not spec then return nil, "not-tradeable" end
  return make_lease(force_index, hub_unit_number, planet_name, { kind = "crafting", name = category }, spec,
    recipe.product, units)
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
  local goods = { { kind = "item", name = lease.item, count = lease.units } }
  return (planets.ship(force_index, lease.hub, lease.planet, goods, contract.id, contract.charge / lease.units))
end
contracts.register_service("concession", can_serve, serve)
contracts.register_service("outsourcing", can_serve, serve)

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
  -- Leases from 0.1.21 named their ore `resource` and their size `slots`.
  for _, lease in pairs(leases()) do
    if not lease.item then
      lease.item, lease.units = lease.resource, offers.concession_units(lease.slots)
      lease.resource, lease.slots = nil, nil
    end
  end
  for force_index, reservations in pairs(dropped or {}) do
    for _, reservation in ipairs(reservations) do
      local id = reservation.contract
      if id and leases()[id] then contracts.void(force_index, id) end
    end
  end
  concessions.on_sweep_tick()
end

return concessions
