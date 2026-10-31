-- Incoming contracts (#76, ADR-0015): counterparties offer each force to craft for them. An offer
-- names a recipe the force can make; on acceptance the ingredients are shipped free to the hub the
-- force accepted at, and the products are collected from contract chests attached to the force's
-- hubs (ADR-0005). Offers come every OFFER_TICKS, at most MAX_OFFERS open at a time and
-- contracts.MAX_LISTED contracts offered to the force open together. State lives in
-- storage.incoming_contracts (chests and each force's random state); contracts live in the force's
-- book (scripts/contracts.lua).
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local notifications = require("scripts.notifications")
local offers = require("scripts.core.contract_offers")
local random = require("scripts.core.random")
local reputation = require("scripts.core.reputation")

local incoming = {}

incoming.CHEST = "gb-contract-chest"
incoming.TECHNOLOGY = "gb-contracts"
incoming.HUB_RANGE = 10
incoming.OFFER_TICKS = 3600 * 5
incoming.MAX_OFFERS = 3
incoming.COLLECT_TICKS = 60
-- Crafting categories a recipe of an offer may have: what assembling machines make.
incoming.CATEGORIES = { crafting = true, ["advanced-crafting"] = true }

-- Whether every good of a list still exists (a mod may have been removed).
local function goods_exist(list)
  for _, goods in ipairs(list) do
    local exists = goods.kind == "fluid" and prototypes.fluid[goods.name] or prototypes.item[goods.name]
    if not exists then return false end
  end
  return true
end

-- Withdraws the contracts of the listed kinds (incoming and rental) whose goods no longer exist:
-- offers are declined, active contracts voided with their guarantee back (the force is not at
-- fault).
local function withdraw_vanished()
  for force_index, state in pairs(storage.forces) do
    local ids = {}
    for id, contract in pairs(state.contracts and state.contracts.open or {}) do
      if contracts.LISTED_KINDS[contract.kind]
        and not (goods_exist(contract.provides) and goods_exist(contract.requires)) then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      if not contracts.void(force_index, id) then contracts.decline(force_index, id) end
    end
  end
end

--- on_init and on_configuration_changed: creates the state, withdraws contracts whose goods no
--- longer exist, drops chests that no longer exist and re-attaches the others.
function incoming.init()
  storage.incoming_contracts = storage.incoming_contracts or { chests = {}, rng = {} }
  withdraw_vanished()
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

--- on_forces_merged: chests look for their nearest hub again; the merged force's random state goes,
--- so that a force created later under its index starts afresh.
function incoming.on_forces_merged(event)
  storage.incoming_contracts.rng[event.source_index] = nil
  incoming.reattach()
end

-- The recipes a force can offer to craft, sorted by name: enabled, visible, made in an assembling
-- machine, item ingredients and one sure item product in a whole amount, every good with a base
-- value.
local function assembled(prototype, categories)
  for _, category in ipairs(prototype.categories) do
    if (categories or incoming.CATEGORIES)[category] then return true end
  end
  return false
end

local function valued(name) return storage.base_values["item/" .. name] ~= nil end

--- The single sure product of a recipe in a whole amount, with a base value, or nil.
function incoming.sole_product(products)
  local product = #products == 1 and products[1]
  local amount = product and product.type == "item" and product.amount
  local sure = amount and amount >= 1 and amount % 1 == 0 and (product.probability or 1) == 1
    and (product.extra_count_fraction or 0) == 0
  return sure and valued(product.name) and product or nil
end

-- A recipe's ingredients as goods, or nil when one is not a valued item.
local function item_ingredients(ingredients)
  if #ingredients == 0 then return nil end
  local list = {}
  for _, ingredient in ipairs(ingredients) do
    if ingredient.type ~= "item" or not valued(ingredient.name) then return nil end
    list[#list + 1] = { kind = "item", name = ingredient.name, count = ingredient.amount }
  end
  return list
end

--- The recipes a force can be offered to craft, sorted by name (see above); with `categories` (a set
--- of crafting category names), only recipes of one of them.
function incoming.candidates(force, categories)
  local list = {}
  for name, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden and assembled(recipe.prototype, categories) then
      local product = incoming.sole_product(recipe.products)
      local ingredients = product and item_ingredients(recipe.ingredients)
      if ingredients then
        list[#list + 1] = {
          name = name, energy = recipe.energy, ingredients = ingredients,
          products = { { kind = "item", name = product.name, count = product.amount } },
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

--- The force's next random draw, from its own deterministic state.
function incoming.draw(force_index)
  local rng = storage.incoming_contracts.rng
  local state, value = random.next(rng[force_index] or random.seed(force_index * 7919 + 1))
  rng[force_index] = state
  return value
end

-- Whether a force may get another offer: fewer than MAX_OFFERS open incoming offers and room in
-- the contracts window.
local function room_for_offer(force_index, state)
  local offered = 0
  for _, contract in pairs(state.contracts.open) do
    if contract.kind == "incoming" and contract.state == core.OFFERED then offered = offered + 1 end
  end
  return offered < incoming.MAX_OFFERS and #contracts.listed(force_index) < contracts.MAX_LISTED
end

local function has_hub(force)
  for _, hub in pairs(storage.hubs) do
    if hub.entity.valid and hub.entity.force == force then return true end
  end
  return false
end

--- Makes one offer to a force from a recipe it can craft, sized by its reputation, and tells the
--- force; returns its id, or nil.
function incoming.make_offer(force)
  local recipe = offers.pick(incoming.candidates(force), incoming.draw(force.index))
  local scale = reputation.contract_scale(storage.forces[force.index].reputation)
  local spec = recipe and offers.offer(recipe, storage.base_values, incoming.draw(force.index), scale)
  local id = spec and contracts.offer(force.index, spec)
  if id then notifications.contract(force.index, "contract-offer", contracts.get(force.index, id)) end
  return id
end

-- Whether a force has researched contracts.
local function researched(force)
  local technology = force.technologies[incoming.TECHNOLOGY]
  return technology and technology.researched
end

--- on_nth_tick(OFFER_TICKS): each force that researched contracts, has a hub and room for an offer
--- gets one.
function incoming.on_offer_tick()
  for force_index, state in pairs(storage.forces) do
    local force = game.forces[force_index]
    if force and state.contracts and researched(force) and room_for_offer(force_index, state)
      and has_hub(force) then
      incoming.make_offer(force)
    end
  end
end

--- What a goods list would sell for on a force's market now.
function incoming.market_value(force_index, list)
  local value = 0
  for _, goods in ipairs(list) do
    local quote = market.quote(force_index, goods.kind, goods.name)
    value = value + (quote and quote.sell or 0) * goods.count
  end
  return value
end

--- The penalty of a contract at acceptance: at least what `at_stake` (the goods the force could keep)
--- would sell for on its market now, so that keeping them never pays even above their base value.
function incoming.penalty_now(force_index, contract, at_stake)
  local value = incoming.market_value(force_index, at_stake)
  return math.min(core.MAX_CREDITS, math.max(contract.penalty, offers.PENALTY_SHARE * value))
end

--- Accepts an incoming offer at a hub: the guarantee is taken and the ingredients shipped to the hub,
--- or nothing changes. Returns true, or false and a reason.
function incoming.accept(force_index, id, hub_unit_number)
  local contract = contracts.get(force_index, id)
  if not (contract and contract.kind == "incoming") then return false, "not-offered" end
  local penalty = incoming.penalty_now(force_index, contract, contract.provides)
  local ok, reason = contracts.can_accept(force_index, id, contract.deposit + penalty)
  if not ok then return false, reason end
  local shipped, refusal = freight.ship(force_index, hub_unit_number, contract.provides, id)
  if not shipped then return false, refusal end
  contract.penalty = penalty
  return contracts.accept(force_index, id)
end

-- Ids of a force's active incoming contracts, oldest first.
local function active_ids(force_index)
  local state = storage.forces[force_index]
  local ids = {}
  for id, contract in pairs(state and state.contracts and state.contracts.open or {}) do
    if contract.kind == "incoming" and contract.state == core.ACTIVE then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

-- Hands over what a contract chest holds of the goods its force's active incoming contracts (`ids`
-- by force index, filled on demand) still need, oldest contract first; a good leaves the chest only
-- for what a contract took.
local function collect(module, ids_by_force)
  local entity = module.entity
  if not (entity.valid and module.hub and hubs.get(module.hub)) then return end
  local force_index = entity.force_index
  ids_by_force[force_index] = ids_by_force[force_index] or active_ids(force_index)
  local ids = ids_by_force[force_index]
  if #ids == 0 then return end
  local state = storage.forces[force_index]
  local inventory = entity.get_inventory(defines.inventory.chest)
  for _, id in ipairs(ids) do
    for key, owed in pairs(core.remaining(state.contracts.open[id])) do
      local name = owed > 0 and key:match("^item/([^@]+)$")
      local held = name and inventory.get_item_count({ name = name, quality = "normal" }) or 0
      if held > 0 then
        local taken = contracts.deliver(force_index, id, key, math.min(held, owed))
        if taken > 0 then inventory.remove({ name = name, quality = "normal", count = taken }) end
      end
    end
  end
end

--- on_nth_tick(COLLECT_TICKS): every contract chest hands over what open contracts need.
function incoming.on_collect_tick()
  local ids_by_force = {}
  for _, module in pairs(storage.incoming_contracts.chests) do collect(module, ids_by_force) end
end

return incoming
