-- Rental warehouses (#119, ADR-0024): storage space of the force a NPC rents. Like a rental
-- assembler (ADR-0017), an idle, empty rental warehouse attached to a hub (ADR-0005) is offered every
-- OFFER_TICKS: a counterparty stores one item the force's industry knows, sized by its contract scale
-- (scripts/core/storage_rental.lua). On acceptance the guarantee is held (its penalty raised to what
-- buying the goods back on the market would cost, with a margin) and the goods are put in the
-- warehouse, closed to the player. In the last SERVICE_TICKS before the deadline the counterparty
-- takes them back through a hub of the force, which fulfils the contract (a custody contract: no
-- reputation) and pays the rent; goods missing then (taken by an inserter, the warehouse mined or
-- destroyed, no hub) fail it at the deadline, the guarantee kept and reputation −1. Once the contract ends the
-- warehouse is released and what is left of the goods goes back to the counterparty. State lives in
-- storage.warehouses = {chests = {[unit_number] = {entity, hub, contract, stored (the item names
-- it holds for an accepted contract)}}}, created on first use, since an event handler may run
-- before the configuration change of a save that predates it.
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local market = require("scripts.market")
local notifications = require("scripts.notifications")
local offers = require("scripts.core.contract_offers")
local reputation = require("scripts.core.reputation")
local storage_rental = require("scripts.core.storage_rental")

local warehouses = {}

warehouses.NAME = "gb-rental-warehouse"
warehouses.TECHNOLOGY = "gb-storage-rental"
warehouses.HUB_RANGE = 10
warehouses.OFFER_TICKS = 3600 * 5
warehouses.SERVICE_TICKS = 60

local function chests()
  storage.warehouses = storage.warehouses or { chests = {} }
  return storage.warehouses.chests
end

--- The warehouses (read only), for the building status.
function warehouses.chests()
  return chests()
end

-- The warehouse module storing for contract `id`, or nil.
local function chest_of(id)
  for _, module in pairs(chests()) do
    if module.contract == id then return module end
  end
end

-- The warehouse stops storing for a contract: what is left of its goods goes back to the
-- counterparty (an item a removed mod took with it is already gone).
local function release(module)
  if module.entity.valid then
    local inventory = module.entity.get_inventory(defines.inventory.chest)
    for _, name in ipairs(module.stored or {}) do
      local held = prototypes.item[name] and inventory.get_item_count({ name = name, quality = "normal" }) or 0
      if held > 0 then inventory.remove({ name = name, quality = "normal", count = held }) end
    end
  end
  module.contract, module.stored = nil, nil
end

--- Registers a newly built rental warehouse, closed to the player and emptied (a clone may carry a
--- counterparty's goods); returns true when the entity was one.
function warehouses.on_built(entity)
  if entity.name ~= warehouses.NAME then return false end
  if chests()[entity.unit_number] then return true end
  entity.operable = false
  entity.get_inventory(defines.inventory.chest).clear()
  local module = { entity = entity }
  hubs.attach(module, warehouses.HUB_RANGE)
  chests()[entity.unit_number] = module
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed rental warehouse; returns true when the unit number was one. Its contract
--- stays open: the goods it held are no longer there to hand back.
function warehouses.forget(unit_number)
  if not chests()[unit_number] then return false end
  chests()[unit_number] = nil
  return true
end

--- A hub appeared or disappeared, or forces merged: warehouses look for their nearest hub again.
function warehouses.reattach()
  for _, module in pairs(chests()) do hubs.attach(module, warehouses.HUB_RANGE) end
end

--- The items a counterparty may store with a force, by name: the sole products of the recipes an
--- incoming contract could name (scripts/incoming_contracts.lua), not spoilable, in recipe order.
function warehouses.candidates(force)
  local list, seen = {}, {}
  for _, recipe in ipairs(incoming.candidates(force)) do
    local name = recipe.products[1].name
    if not seen[name] and prototypes.item[name].get_spoil_ticks() == 0 then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  return list
end

--- Offers one warehouse: an item drawn from its force's candidates, sized by its contract scale.
--- Returns the contract id, or nil.
function warehouses.make_offer(module, candidates)
  local force_index = module.entity.force_index
  local item = offers.pick(candidates, incoming.draw(force_index))
  if not item then return nil end
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  local spec = storage_rental.warehouse(item, storage.base_values["item/" .. item], prototypes.item[item].stack_size,
    #inventory, incoming.draw(force_index), reputation.contract_scale(storage.forces[force_index].reputation))
  local id = spec and contracts.offer(force_index, spec)
  if id then module.contract = id end
  return id
end

local function researched(force)
  local technology = force.technologies[warehouses.TECHNOLOGY]
  return technology ~= nil and technology.researched
end

--- on_nth_tick(OFFER_TICKS): each idle, empty warehouse attached to a hub, of a force that researched
--- storage rental and has room in its Contracts tab, is offered, in unit number order; each force is
--- told once how many of its warehouses were offered, the alert pointing at the first.
function warehouses.on_offer_tick()
  local units = {}
  for unit_number, module in pairs(chests()) do
    local entity = module.entity
    if not module.contract and entity.valid and module.hub and hubs.get(module.hub)
      and entity.get_inventory(defines.inventory.chest).is_empty() then
      units[#units + 1] = unit_number
    end
  end
  table.sort(units)
  local offered, candidates = {}, {}
  for _, unit_number in ipairs(units) do
    local module = chests()[unit_number]
    local force = module.entity.force
    if researched(force) and #contracts.listed(force.index) < contracts.MAX_LISTED then
      candidates[force.index] = candidates[force.index] or warehouses.candidates(force)
      local id = warehouses.make_offer(module, candidates[force.index])
      if id then
        offered[force.index] = offered[force.index] or { id = id, entity = module.entity, count = 0 }
        offered[force.index].count = offered[force.index].count + 1
      end
    end
  end
  for force_index, first in pairs(offered) do
    notifications.contract(force_index, "contract-offer", contracts.get(force_index, first.id), first.entity,
      first.count)
  end
end

-- The penalty of a warehouse contract at acceptance: at least what buying its goods back on the
-- force's market would cost now, with the price impact, plus a margin (storage_rental.warehouse_penalty).
-- Never below the plain market's cost: a market event (ADR-0025) may raise the buy price, never
-- lower the guarantee.
local function penalty_now(force_index, contract)
  local cost = 0
  for _, goods in ipairs(contract.provides) do
    local price = market.preview(force_index, goods.kind, goods.name, "buy", goods.count)
    if not price then return storage_rental.warehouse_penalty(contract.penalty, nil) end
    local plain = market.plain_preview(force_index, goods.kind, goods.name, "buy", goods.count)
    cost = cost + math.max(price, plain or price)
  end
  return storage_rental.warehouse_penalty(contract.penalty, cost)
end

--- Accepts a warehouse offer: the force puts up the guarantee, its penalty raised to the cost of
--- buying the goods back (see `penalty_now`), and the goods are put in the warehouse; or nothing
--- changes. Returns true, or false and a
--- reason (not-offered, warehouse-gone, warehouse-no-hub, warehouse-not-empty, and those of
--- contracts.can_accept).
function warehouses.accept(force_index, id)
  local contract = contracts.get(force_index, id)
  if not (contract and contract.kind == "warehouse") then return false, "not-offered" end
  local module = chest_of(id)
  if not (module and module.entity.valid and module.entity.force_index == force_index) then
    return false, "warehouse-gone"
  end
  if not (module.hub and hubs.get(module.hub)) then return false, "warehouse-no-hub" end
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  if not inventory.is_empty() then return false, "warehouse-not-empty" end
  local penalty = penalty_now(force_index, contract)
  local ok, reason = contracts.can_accept(force_index, id, contract.deposit + penalty)
  if not ok then return false, reason end
  for _, goods in ipairs(contract.provides) do
    local inserted = inventory.insert({ name = goods.name, quality = "normal", count = goods.count })
    if inserted < goods.count then
      inventory.clear()
      return false, "warehouse-not-empty"
    end
  end
  -- The guarantee held is deposit plus penalty: the penalty is set for the acceptance, and set back
  -- when it fails.
  local offered_penalty = contract.penalty
  contract.penalty = penalty
  ok, reason = contracts.accept(force_index, id)
  if not ok then
    contract.penalty = offered_penalty
    inventory.clear()
    return false, reason
  end
  module.stored = {}
  for _, goods in ipairs(contract.provides) do module.stored[#module.stored + 1] = goods.name end
  return true
end

-- The counterparty takes its goods back: what the warehouse holds of each, up to what is owed.
local function collect(module, force_index, contract)
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  for _, goods in ipairs(contract.requires) do
    local held = inventory.get_item_count({ name = goods.name, quality = "normal" })
    local taken = held > 0 and contracts.deliver(force_index, contract.id, core.key(goods), held) or 0
    if taken > 0 then inventory.remove({ name = goods.name, quality = "normal", count = taken }) end
  end
end

-- Serves one warehouse at `tick`: one whose contract ended is released; a rented one gives its goods
-- back in the last SERVICE_TICKS of the term, through a hub of its force.
local function serve(module, tick)
  local entity = module.entity
  if not (entity.valid and module.contract) then return end
  local force_index = entity.force_index
  local contract = contracts.get(force_index, module.contract)
  if not (contract and (contract.state == core.OFFERED or contract.state == core.ACTIVE)) then
    return release(module)
  end
  if contract.state ~= core.ACTIVE or contract.due_tick - tick >= warehouses.SERVICE_TICKS then return end
  local hub = module.hub and hubs.get(module.hub)
  if hub and hub.force_index == force_index then collect(module, force_index, contract) end
end

--- on_nth_tick(SERVICE_TICKS): every warehouse is served.
function warehouses.on_service_tick(event)
  for _, module in pairs(chests()) do serve(module, event.tick) end
end

--- on_init and on_configuration_changed: creates the state, forgets warehouses that no longer exist,
--- re-attaches the others and keeps them closed to the player.
function warehouses.init()
  local gone = {}
  for unit_number, module in pairs(chests()) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do chests()[unit_number] = nil end
  for _, module in pairs(chests()) do module.entity.operable = false end
  warehouses.reattach()
end

return warehouses
