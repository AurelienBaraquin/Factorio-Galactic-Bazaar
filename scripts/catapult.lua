-- Electromagnetic catapults (#67): 48-slot chests attached to the nearest hub of their force in range
-- (ADR-0005) that sell their contents in bulk, one shot at a time: a shot sells every plain stack
-- while each unit fetches at least the export floor, and draws SHOT_MJ from the catapult's capacitor,
-- a hidden electric-energy-interface under it that charges from the network. Without enough energy,
-- no shot. Catapults are visited in turn, up to VISITS per PASS_TICKS and at most one shot per pass,
-- each shooting at most every SHOT_TICKS.
-- State lives in storage.catapults.
local cargo = require("scripts.cargo")
local hubs = require("scripts.hubs")

local catapult = {}

catapult.NAME = "gb-catapult"
catapult.CAPACITOR = "gb-catapult-capacitor"
catapult.HUB_RANGE = 10
catapult.SHOT_MJ = 50
catapult.SHOT_TICKS = 120
catapult.PASS_TICKS = 6
-- Catapults visited per pass at most; a pass stops at the first shot.
catapult.VISITS = 5

local MJ = 1e6

-- The catapult's capacitor: one already under it (an area clone copies both) or a new one. It cannot
-- be damaged: nothing lets a player see or repair it.
local function place_capacitor(entity)
  local capacitor = entity.surface.find_entities_filtered({
    name = catapult.CAPACITOR, position = entity.position, limit = 1,
  })[1]
  capacitor = capacitor or entity.surface.create_entity({
    name = catapult.CAPACITOR, position = entity.position, force = entity.force,
  })
  capacitor.destructible = false
  return capacitor
end

-- The catapult's capacitor, placed again if it is gone (another mod destroyed it).
local function capacitor_of(module)
  if not (module.capacitor and module.capacitor.valid) then module.capacitor = place_capacitor(module.entity) end
  return module.capacitor
end

--- on_init and on_configuration_changed: creates the state, drops catapults that no longer exist,
--- gives back a capacitor to any catapult that lost its own, and re-attaches them.
function catapult.init()
  storage.catapults = storage.catapults or { modules = {}, order = {}, cursor = 1 }
  local state = storage.catapults
  local gone = {}
  for unit_number, module in pairs(state.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do catapult.forget(unit_number) end
  for _, module in pairs(state.modules) do
    capacitor_of(module)
    hubs.attach(module, catapult.HUB_RANGE)
  end
end

--- Registers a newly built catapult and places its capacitor; returns true when the entity was one.
function catapult.on_built(entity)
  if entity.name ~= catapult.NAME then return false end
  local state = storage.catapults
  if state.modules[entity.unit_number] then return true end
  local module = { entity = entity, capacitor = place_capacitor(entity), next_shot = 0 }
  hubs.attach(module, catapult.HUB_RANGE)
  state.modules[entity.unit_number] = module
  state.order[#state.order + 1] = entity.unit_number
  module.order_index = #state.order
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed catapult and removes its capacitor, leaving the visiting order in O(1);
--- returns true when the unit number was one.
function catapult.forget(unit_number)
  local state = storage.catapults
  local module = state.modules[unit_number]
  if not module then return false end
  if module.capacitor and module.capacitor.valid then module.capacitor.destroy() end
  state.modules[unit_number] = nil
  local order, index, last = state.order, module.order_index, #state.order
  if index ~= last then
    order[index] = order[last]
    state.modules[order[index]].order_index = index
  end
  order[last] = nil
  if state.cursor > last then state.cursor = 1 end
  return true
end

--- A hub appeared: catapults in its range move to it if it is now their nearest hub.
function catapult.on_hub_built(hub)
  local nearby = hub.surface.find_entities_filtered({
    name = catapult.NAME, force = hub.force, position = hub.position, radius = catapult.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.catapults.modules[entity.unit_number]
    if module then hubs.attach(module, catapult.HUB_RANGE) end
  end
end

--- A hub disappeared: its catapults look for another hub in range.
function catapult.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.catapults.modules) do
    if module.hub == hub_unit_number and module.entity.valid then hubs.attach(module, catapult.HUB_RANGE) end
  end
end

--- on_forces_merged: catapults now belong to the merged force and may use its hubs.
function catapult.on_forces_merged()
  for _, module in pairs(storage.catapults.modules) do
    if module.entity.valid then hubs.attach(module, catapult.HUB_RANGE) end
  end
end

-- Fires a catapult if it is ready: its shot interval passed, its capacitor holds a shot and it has a
-- powered hub of its force. The energy is spent only when the shot sold something. Returns the units
-- sold.
local function shoot(module, tick)
  local entity = module.entity
  if tick < module.next_shot then return 0 end
  local capacitor = capacitor_of(module)
  if capacitor.energy < catapult.SHOT_MJ * MJ or not hubs.trading_hub(module, catapult.HUB_RANGE) then return 0 end
  local sold = cargo.sell_stacks(entity.get_inventory(defines.inventory.chest), entity.force.index,
    cargo.DEFAULT_MIN_PRICE_RATIO, nil, nil, nil, cargo.JOURNAL_MERGE_TICKS)
  if sold > 0 then
    capacitor.energy = capacitor.energy - catapult.SHOT_MJ * MJ
    module.next_shot = tick + catapult.SHOT_TICKS
  end
  return sold
end

--- on_nth_tick(PASS_TICKS): catapults are visited in turn, up to VISITS per pass, until one shoots;
--- empty ones are passed over cheaply.
function catapult.on_pass_tick(event)
  local state = storage.catapults
  for _ = 1, math.min(catapult.VISITS, #state.order) do
    if state.cursor > #state.order then state.cursor = 1 end
    local module = state.modules[state.order[state.cursor]]
    state.cursor = state.cursor + 1
    if module and module.entity.valid and not module.entity.get_inventory(defines.inventory.chest).is_empty()
      and shoot(module, event.tick) > 0 then
      return
    end
  end
end

catapult.shoot = shoot

return catapult
