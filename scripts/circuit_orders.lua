-- Order combinators (ADR-0011): combinators that read item signals on their circuit input and buy
-- that many units once per ORDER_TICKS, delivered by orbital capsule to their hub's import chests,
-- within a spending budget per period. Each works through the nearest powered hub of its force in
-- range (ADR-0005). State lives in storage.circuit_orders.
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local orders = require("scripts.core.orders")

local circuit_orders = {}

circuit_orders.NAME = "gb-order-combinator"
circuit_orders.HUB_RANGE = 10
-- Ticks between two readings of every order combinator: one order per item and period at most.
circuit_orders.ORDER_TICKS = 600
circuit_orders.BUDGET_SIGNAL = "gb-credits"
-- Ticks over which a force's recurring orders of one item share one journal entry per kind.
circuit_orders.JOURNAL_MERGE_TICKS = 3600

local W = defines.wire_connector_id

--- on_init and on_configuration_changed: creates the state, drops combinators that no longer exist
--- and re-attaches the others.
function circuit_orders.init()
  storage.circuit_orders = storage.circuit_orders or { modules = {} }
  local modules = storage.circuit_orders.modules
  local gone = {}
  for unit_number, module in pairs(modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do modules[unit_number] = nil end
  for _, module in pairs(modules) do hubs.attach(module, circuit_orders.HUB_RANGE) end
end

-- An order combinator only reads: it emits nothing and keeps no section (a blueprint or pasted
-- settings could add some).
local function silence(entity)
  local behavior = entity.get_or_create_control_behavior()
  for i = behavior.sections_count, 1, -1 do behavior.remove_section(i) end
  if behavior.enabled then behavior.enabled = false end
end

--- Registers a newly built order combinator; returns true when the entity was one.
function circuit_orders.on_built(entity)
  if entity.name ~= circuit_orders.NAME then return false end
  local modules = storage.circuit_orders.modules
  if modules[entity.unit_number] then return true end
  entity.operable = false
  silence(entity)
  local module = { entity = entity }
  hubs.attach(module, circuit_orders.HUB_RANGE)
  modules[entity.unit_number] = module
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed order combinator; returns true when the unit number was one.
function circuit_orders.forget(unit_number)
  if not storage.circuit_orders.modules[unit_number] then return false end
  storage.circuit_orders.modules[unit_number] = nil
  return true
end

--- A hub appeared: order combinators in its range move to it if it is now their nearest hub.
function circuit_orders.on_hub_built(hub)
  local nearby = hub.surface.find_entities_filtered({
    name = circuit_orders.NAME, force = hub.force, position = hub.position, radius = circuit_orders.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.circuit_orders.modules[entity.unit_number]
    if module then hubs.attach(module, circuit_orders.HUB_RANGE) end
  end
end

--- A hub disappeared: its order combinators look for another hub in range.
function circuit_orders.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.circuit_orders.modules) do
    if module.hub == hub_unit_number then hubs.attach(module, circuit_orders.HUB_RANGE) end
  end
end

--- on_forces_merged: order combinators now belong to the merged force and may use its hubs.
function circuit_orders.on_forces_merged()
  for _, module in pairs(storage.circuit_orders.modules) do hubs.attach(module, circuit_orders.HUB_RANGE) end
end

-- Places the orders a combinator's input asks for, in name order, while each fits in the period's
-- budget; an order the hub refuses (queue full, no import chest...) is skipped.
local function place_orders(module)
  local entity = module.entity
  silence(entity)
  local hub = hubs.trading_hub(module, circuit_orders.HUB_RANGE)
  local state = storage.forces[entity.force.index]
  if not (hub and state) then return end
  local requests, budget_signal = orders.requests(entity.get_signals(W.circuit_red, W.circuit_green),
    circuit_orders.BUDGET_SIGNAL)
  local budget = orders.budget(state.balance, budget_signal)
  for _, request in ipairs(requests) do
    local cost, fee = freight.preview(entity.force.index, request.name, request.units)
    if cost and cost + fee <= budget then
      local ok, paid, charged = freight.order(entity.force.index, hub.unit_number, request.name, request.units,
        circuit_orders.JOURNAL_MERGE_TICKS)
      if ok then budget = budget - paid - charged end
    end
  end
end

--- on_nth_tick(ORDER_TICKS): every order combinator places its orders.
function circuit_orders.on_order_tick()
  for _, module in pairs(storage.circuit_orders.modules) do
    if module.entity.valid then place_orders(module) end
  end
end

return circuit_orders
