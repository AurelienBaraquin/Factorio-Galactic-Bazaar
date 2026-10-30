-- Incoming contracts (#76, ADR-0015): counterparties offer each force to craft for them. An offer
-- names a recipe the force can make; on acceptance the ingredients are shipped free to the hub the
-- force accepted at, and the products are collected from contract chests attached to the force's
-- hubs (ADR-0005). Offers come every OFFER_TICKS, at most MAX_OFFERS open at a time. State lives in
-- storage.incoming_contracts (chests and each force's random state); contracts live in the force's
-- book (scripts/contracts.lua).
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local offers = require("scripts.core.contract_offers")
local random = require("scripts.core.random")

local incoming = {}

incoming.CHEST = "gb-contract-chest"
incoming.TECHNOLOGY = "gb-contracts"
incoming.HUB_RANGE = 10
incoming.OFFER_TICKS = 3600 * 5
incoming.MAX_OFFERS = 3
incoming.COLLECT_TICKS = 60
-- Crafting categories a recipe of an offer may have: what assembling machines make.
incoming.CATEGORIES = { crafting = true, ["advanced-crafting"] = true }

--- on_init and on_configuration_changed: creates the state, drops chests that no longer exist and
--- re-attaches the others.
function incoming.init()
  storage.incoming_contracts = storage.incoming_contracts or { chests = {}, rng = {} }
  local chests = storage.incoming_contracts.chests
  local gone = {}
  for unit_number, module in pairs(chests) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do chests[unit_number] = nil end
  for _, module in pairs(chests) do hubs.attach(module, incoming.HUB_RANGE) end
end

--- Registers a newly built contract chest; returns true when the entity was one.
function incoming.on_built(entity)
  if entity.name ~= incoming.CHEST then return false end
  local chests = storage.incoming_contracts.chests
  if chests[entity.unit_number] then return true end
  local module = { entity = entity }
  hubs.attach(module, incoming.HUB_RANGE)
  chests[entity.unit_number] = module
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed contract chest; returns true when the unit number was one.
function incoming.forget(unit_number)
  if not storage.incoming_contracts.chests[unit_number] then return false end
  storage.incoming_contracts.chests[unit_number] = nil
  return true
end

--- A hub appeared or disappeared, or forces merged: chests look for their nearest hub again.
function incoming.reattach()
  for _, module in pairs(storage.incoming_contracts.chests) do
    if module.entity.valid then hubs.attach(module, incoming.HUB_RANGE) end
  end
end

-- The recipes a force can offer to craft, sorted by name: enabled, visible, made in an assembling
-- machine, item ingredients and one item product, every good with a base value.
local function assembled(prototype)
  for _, category in ipairs(prototype.categories) do
    if incoming.CATEGORIES[category] then return true end
  end
  return false
end

local function candidates(force)
  local list = {}
  for name, recipe in pairs(force.recipes) do
    local ok = recipe.enabled and not recipe.hidden and assembled(recipe.prototype)
      and #recipe.products == 1 and recipe.products[1].type == "item" and #recipe.ingredients > 0
    if ok then
      local ingredients = {}
      for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type ~= "item" then ok = false break end
        ingredients[#ingredients + 1] = { kind = "item", name = ingredient.name, count = ingredient.amount }
      end
      local product = recipe.products[1]
      local count = product.amount or ((product.amount_min or 0) + (product.amount_max or 0)) / 2
      if ok and count >= 1 and (product.probability or 1) == 1 then
        list[#list + 1] = {
          name = name, energy = recipe.energy, ingredients = ingredients,
          products = { { kind = "item", name = product.name, count = count } },
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- The force's next random draw, from its own deterministic state.
local function draw(force_index)
  local rng = storage.incoming_contracts.rng
  local state, value = random.next(rng[force_index] or random.seed(force_index * 7919 + 1))
  rng[force_index] = state
  return value
end

local function open_offers(state)
  local count = 0
  for _, contract in pairs(state.contracts.open) do
    if contract.kind == "incoming" and contract.state == core.OFFERED then count = count + 1 end
  end
  return count
end

local function has_hub(force)
  for _, hub in pairs(storage.hubs) do
    if hub.entity.valid and hub.entity.force == force then return true end
  end
  return false
end

--- Makes one offer to a force from a recipe it can craft; returns its id, or nil.
function incoming.make_offer(force)
  local recipe = offers.pick(candidates(force), draw(force.index))
  local spec = recipe and offers.offer(recipe, storage.base_values, draw(force.index))
  return spec and contracts.offer(force.index, spec)
end

-- Whether a force has researched contracts.
local function researched(force)
  local technology = force.technologies[incoming.TECHNOLOGY]
  return technology and technology.researched
end

--- on_nth_tick(OFFER_TICKS): each force that researched contracts, has a hub and fewer than
--- MAX_OFFERS open offers gets one.
function incoming.on_offer_tick()
  for force_index, state in pairs(storage.forces) do
    local force = game.forces[force_index]
    if force and state.contracts and researched(force) and open_offers(state) < incoming.MAX_OFFERS
      and has_hub(force) then
      incoming.make_offer(force)
    end
  end
end

--- Accepts an incoming offer at a hub: the guarantee is taken and the ingredients shipped to the hub,
--- or nothing changes. Returns true, or false and a reason.
function incoming.accept(force_index, id, hub_unit_number)
  local contract = contracts.get(force_index, id)
  if not (contract and contract.kind == "incoming" and contract.state == core.OFFERED) then
    return false, "not-offered"
  end
  if storage.forces[force_index].balance < core.guarantee(contract) then return false, "insufficient-funds" end
  local shipped, reason = freight.ship(force_index, hub_unit_number, contract.provides, id)
  if not shipped then return false, reason end
  return contracts.accept(force_index, id)
end

-- Hands over what a contract chest holds of the goods its force's active incoming contracts still
-- need, oldest contract first; a good leaves the chest only for what a contract took.
local function collect(module)
  local entity = module.entity
  if not (entity.valid and module.hub and hubs.get(module.hub)) then return end
  local state = storage.forces[entity.force.index]
  if not (state and state.contracts) then return end
  local inventory = entity.get_inventory(defines.inventory.chest)
  local ids = {}
  for id, contract in pairs(state.contracts.open) do
    if contract.kind == "incoming" and contract.state == core.ACTIVE then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    for key, owed in pairs(core.remaining(state.contracts.open[id])) do
      local name = owed > 0 and key:match("^item/([^@]+)$")
      local held = name and inventory.get_item_count({ name = name, quality = "normal" }) or 0
      if held > 0 then
        local taken = contracts.deliver(entity.force.index, id, key, math.min(held, owed))
        if taken > 0 then inventory.remove({ name = name, quality = "normal", count = taken }) end
      end
    end
  end
end

--- on_nth_tick(COLLECT_TICKS): every contract chest hands over what open contracts need.
function incoming.on_collect_tick()
  for _, module in pairs(storage.incoming_contracts.chests) do collect(module) end
end

return incoming
