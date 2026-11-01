-- Machine capacity rental (#78, ADR-0017): a rental assembler attached to a hub (ADR-0005) is offered
-- to counterparties. An offer rents it for one recipe (scripts/core/contract_offers.lua); once
-- accepted, the machine works only for the counterparty: the script sets its recipe, keeps a few
-- crafts of ingredients in it and takes its products every SERVICE_TICKS, delivering them to the
-- contract, whose rent comes in installments (scripts/contracts.lua). The force provides the machine
-- and its power; it cannot open it. State lives in storage.rentals.
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local notifications = require("scripts.notifications")
local offers = require("scripts.core.contract_offers")

local rental = {}

rental.NAME = "gb-rental-assembler"
rental.TECHNOLOGY = "gb-capacity-rental"
rental.HUB_RANGE = 10
rental.OFFER_TICKS = 3600 * 5
rental.SERVICE_TICKS = 60
-- Ingredients kept in a rented machine: what it crafts in this many seconds, at least one craft.
rental.BUFFER_SECONDS = 4

local function machines() return storage.rentals.machines end

-- Unit numbers of every machine, in order.
local function sorted_units()
  local units = {}
  for unit_number in pairs(machines()) do units[#units + 1] = unit_number end
  table.sort(units)
  return units
end

-- The machine module renting for contract `id`, or nil.
local function machine_of(id)
  for _, module in pairs(machines()) do
    if module.contract == id then return module end
  end
end

-- The machine stops working for a contract: its recipe, ingredients and products go back to the
-- counterparty.
local function release(module)
  module.contract, module.recipe, module.crafts, module.provided = nil, nil, nil, nil
  local entity = module.entity
  if entity.valid then
    entity.set_recipe(nil)
    entity.get_output_inventory().clear()
  end
end

-- Whether a machine can still craft `recipe_name` (a mod may have removed it or changed it).
local function craftable(entity, recipe_name)
  local recipe = prototypes.recipe[recipe_name]
  if not recipe then return false end
  for _, category in ipairs(recipe.categories) do
    if entity.prototype.crafting_categories[category] then return true end
  end
  return false
end

-- Closes a machine to the player: no GUI, and no recipe set by a circuit network (a blueprint may
-- carry that setting).
local function close_to_player(entity)
  entity.operable = false
  local control = entity.get_control_behavior()
  if control then control.circuit_set_recipe = false end
end

--- on_init and on_configuration_changed: creates the state, drops machines that no longer exist,
--- withdraws rentals whose recipe the machine can no longer craft (the force is not at fault),
--- re-attaches the others and keeps them closed to the player.
function rental.init()
  storage.rentals = storage.rentals or { machines = {} }
  local gone = {}
  for unit_number, module in pairs(machines()) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do machines()[unit_number] = nil end
  for _, unit_number in ipairs(sorted_units()) do
    local module = machines()[unit_number]
    local force_index = module.entity.force_index
    local contract = module.contract and contracts.get(force_index, module.contract)
    if module.recipe and not craftable(module.entity, module.recipe) then
      if not contracts.void(force_index, module.contract) then contracts.decline(force_index, module.contract) end
      release(module)
    elseif contract and contract.state == core.OFFERED and not contract.passive then
      -- An offer made on the terms before #122 (rent from the products' value): no guarantee is held
      -- yet, so it is declined and the machine offered again on the current terms.
      contracts.decline(force_index, module.contract)
      release(module)
    end
    close_to_player(module.entity)
    hubs.attach(module, rental.HUB_RANGE)
  end
end

--- Registers a newly built rental assembler; returns true when the entity was one.
function rental.on_built(entity)
  if entity.name ~= rental.NAME then return false end
  if machines()[entity.unit_number] then return true end
  local module = { entity = entity }
  close_to_player(entity)
  -- A clone or a revived ghost may carry a recipe or products: the machine starts idle and empty.
  entity.set_recipe(nil)
  entity.get_output_inventory().clear()
  hubs.attach(module, rental.HUB_RANGE)
  machines()[entity.unit_number] = module
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed rental assembler; returns true when the unit number was one. Its contract
--- stays open: the capacity it promised is no longer there.
function rental.forget(unit_number)
  if not machines()[unit_number] then return false end
  machines()[unit_number] = nil
  return true
end

--- A hub appeared or disappeared, or forces merged: machines look for their nearest hub again.
function rental.reattach()
  for _, module in pairs(machines()) do
    if module.entity.valid then hubs.attach(module, rental.HUB_RANGE) end
  end
end

-- Whether the surface a machine stands on meets a recipe's surface conditions (Space Age).
local function meets_conditions(surface, recipe_name)
  for _, condition in ipairs(prototypes.recipe[recipe_name].surface_conditions or {}) do
    local value = surface.get_property(condition.property)
    if value < (condition.min or -math.huge) or value > (condition.max or math.huge) then return false end
  end
  return true
end

--- The recipes a machine could be rented for, sorted by name: those of its force an incoming
--- contract could name, of its crafting categories, whose surface conditions its surface meets.
function rental.candidates(entity)
  local list = {}
  for _, recipe in ipairs(incoming.candidates(entity.force, entity.prototype.crafting_categories)) do
    if meets_conditions(entity.surface, recipe.name) then list[#list + 1] = recipe end
  end
  return list
end

--- Offers one machine for rent: a recipe it can craft where it stands, drawn from its force's state.
--- Returns the contract id, or nil.
function rental.make_offer(module)
  local entity = module.entity
  local force = entity.force
  local prototype = entity.prototype
  local recipe = offers.pick(rental.candidates(entity), incoming.draw(force.index))
  if not recipe then return nil end
  local crafts = offers.rental_crafts(recipe.energy, prototype.get_crafting_speed(entity.quality))
  local spec = offers.rental(recipe, storage.base_values, incoming.draw(force.index), crafts)
  local id = spec and contracts.offer(force.index, spec)
  if id then module.contract, module.recipe, module.crafts, module.provided = id, recipe.name, crafts, {} end
  return id
end

local function researched(force)
  local technology = force.technologies[rental.TECHNOLOGY]
  return technology and technology.researched
end

--- on_nth_tick(OFFER_TICKS): each idle machine attached to a hub, of a force that researched rental
--- and has room in its Contracts tab, is offered for rent, in unit number order; each force is told
--- once how many of its machines were offered, the alert pointing at the first.
function rental.on_offer_tick()
  local units = {}
  for unit_number, module in pairs(machines()) do
    if not module.contract and module.entity.valid and module.hub and hubs.get(module.hub) then
      units[#units + 1] = unit_number
    end
  end
  table.sort(units)
  local offered = {}
  for _, unit_number in ipairs(units) do
    local module = machines()[unit_number]
    local force = module.entity.force
    local id = researched(force) and #contracts.listed(force.index) < contracts.MAX_LISTED and rental.make_offer(module)
    if id then
      offered[force.index] = offered[force.index] or { id = id, entity = module.entity, count = 0 }
      offered[force.index].count = offered[force.index].count + 1
    end
  end
  for force_index, first in pairs(offered) do
    notifications.contract(force_index, "contract-offer", contracts.get(force_index, first.id), first.entity,
      first.count)
  end
end

--- Accepts a rental offer: the force puts up the guarantee, raised to the market value of what it
--- could keep from the machine, and the machine is set to the recipe; or nothing changes. Returns
--- true, or false and a reason.
function rental.accept(force_index, id)
  local contract = contracts.get(force_index, id)
  if not (contract and contract.kind == "rental") then return false, "not-offered" end
  local module = machine_of(id)
  if not (module and module.entity.valid and module.entity.force_index == force_index) then
    return false, "machine-gone"
  end
  if not (module.hub and hubs.get(module.hub)) then return false, "machine-no-hub" end
  local at_stake = contract.requires
  if incoming.market_value(force_index, contract.provides) > incoming.market_value(force_index, contract.requires) then
    at_stake = contract.provides
  end
  local penalty = incoming.penalty_now(force_index, contract, at_stake)
  local ok, reason = contracts.can_accept(force_index, id, contract.deposit + penalty)
  if not ok then return false, reason end
  contract.penalty = penalty
  ok, reason = contracts.accept(force_index, id)
  if ok then module.entity.set_recipe(module.recipe) end
  return ok, reason
end

-- Takes the machine's products for the contract. Every product leaves the machine, delivered or
-- not: what it made beyond the contract (a productivity bonus) is the counterparty's too.
local function collect(module, force_index, contract)
  local output = module.entity.get_output_inventory()
  for _, goods in ipairs(contract.requires) do
    local held = output.get_item_count({ name = goods.name, quality = "normal" })
    if held > 0 then
      contracts.deliver(force_index, contract.id, core.key(goods), held)
      output.remove({ name = goods.name, quality = "normal", count = held })
    end
  end
end

-- Tops the machine's ingredients up to BUFFER_SECONDS of crafting, never beyond what the contract
-- provides in all.
local function provision(module, contract)
  local entity = module.entity
  local input = entity.get_inventory(defines.inventory.crafter_input)
  local seconds_per_craft = entity.get_recipe().energy / entity.prototype.get_crafting_speed(entity.quality)
  local buffer = math.max(1, math.ceil(rental.BUFFER_SECONDS / seconds_per_craft))
  for _, goods in ipairs(contract.provides) do
    local per_craft = goods.count / module.crafts
    local wanted = per_craft * buffer - input.get_item_count({ name = goods.name, quality = "normal" })
    local left = goods.count - (module.provided[goods.name] or 0)
    local count = math.floor(math.min(wanted, left))
    if count > 0 then
      local inserted = input.insert({ name = goods.name, quality = "normal", count = count })
      module.provided[goods.name] = (module.provided[goods.name] or 0) + inserted
    end
  end
end

-- Serves one machine: one whose contract ended is released; only a rented machine has a recipe (a
-- pasted one is undone), and it hands its products over and gets ingredients through a hub.
local function serve(module)
  local entity = module.entity
  if not entity.valid then return end
  local force_index = entity.force_index
  local contract = module.contract and contracts.get(force_index, module.contract)
  if module.contract and not (contract and (contract.state == core.OFFERED or contract.state == core.ACTIVE)) then
    release(module)
    contract = nil
  end
  local rented = contract and contract.state == core.ACTIVE
  local wanted = rented and module.recipe or nil
  local recipe = entity.get_recipe()
  if (recipe and recipe.name) ~= wanted then entity.set_recipe(wanted) end
  if not (rented and module.hub and hubs.get(module.hub)) then return end
  collect(module, force_index, contract)
  if not core.complete(contract) then provision(module, contract) end
end

--- on_nth_tick(SERVICE_TICKS): every machine is served.
function rental.on_service_tick()
  for _, module in pairs(machines()) do serve(module) end
end

--- on_entity_settings_pasted: a rented machine keeps the counterparty's recipe, an idle one none.
function rental.on_settings_pasted(event)
  local module = event.destination.valid and machines()[event.destination.unit_number]
  if module then serve(module) end
end

--- on_forces_merged: machines now belong to the merged force and may use its hubs.
function rental.on_forces_merged()
  rental.reattach()
end

return rental
