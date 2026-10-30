-- Order combinators (ADR-0011): combinators that read item signals on their circuit input and buy
-- that many units once per ORDER_TICKS, delivered by orbital capsule to their hub's import chests.
-- Nothing is bought without a positive budget signal, which caps what the force spends through
-- order combinators in the period. Combinators are spread over SLOTS passes by unit number, so
-- that no tick reads all of them. Each works through the nearest powered hub of its force in range
-- (ADR-0005). State lives in storage.circuit_orders.
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local orders = require("scripts.core.orders")

local circuit_orders = {}

circuit_orders.NAME = "gb-order-combinator"
circuit_orders.HUB_RANGE = 10
-- Ticks between two readings of an order combinator (one order per item and period at most), split
-- into SLOTS passes of PASS_TICKS.
circuit_orders.ORDER_TICKS = 600
circuit_orders.PASS_TICKS = 60
circuit_orders.SLOTS = circuit_orders.ORDER_TICKS / circuit_orders.PASS_TICKS
circuit_orders.BUDGET_SIGNAL = "gb-budget"
-- The balance emitted by price combinators: an input carrying it is prices, not orders.
circuit_orders.REFUSED_SIGNAL = "gb-credits"
-- Ticks over which a force's recurring orders of one item share one journal entry per kind.
circuit_orders.JOURNAL_MERGE_TICKS = 3600

local W = defines.wire_connector_id

--- on_init and on_configuration_changed: creates the state, drops combinators that no longer exist
--- and re-attaches the others.
function circuit_orders.init()
  storage.circuit_orders = storage.circuit_orders or { modules = {} }
  storage.circuit_orders.spent = storage.circuit_orders.spent or {}
  local modules = storage.circuit_orders.modules
  local gone = {}
  for unit_number, module in pairs(modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do modules[unit_number] = nil end
  for _, module in pairs(modules) do hubs.attach(module, circuit_orders.HUB_RANGE) end
end

-- An order combinator only reads: it emits nothing and keeps no section (a blueprint or pasted
-- settings could add some). Returns true when it had to silence it: its output may still be on
-- the network this tick, so it must not be read as orders.
local function silence(entity)
  local behavior = entity.get_or_create_control_behavior()
  local changed = behavior.sections_count > 0 or behavior.enabled
  for i = behavior.sections_count, 1, -1 do behavior.remove_section(i) end
  if behavior.enabled then behavior.enabled = false end
  return changed
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

--- on_entity_settings_pasted: pasted signals on an order combinator are removed at once.
function circuit_orders.on_settings_pasted(event)
  local entity = event.destination
  if entity.valid and storage.circuit_orders.modules[entity.unit_number] then silence(entity) end
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
function circuit_orders.on_forces_merged(event)
  storage.circuit_orders.spent[event.source_index] = nil
  for _, module in pairs(storage.circuit_orders.modules) do hubs.attach(module, circuit_orders.HUB_RANGE) end
end

-- What a force has spent through order combinators in the current period.
local function spending(force_index, tick)
  local period = math.floor(tick / circuit_orders.ORDER_TICKS)
  local spent = storage.circuit_orders.spent[force_index]
  if not spent or spent.period ~= period then
    spent = { period = period, credits = 0 }
    storage.circuit_orders.spent[force_index] = spent
  end
  return spent
end

-- Places the orders a combinator's input asks for, fluids then items, each in name order, while
-- each fits in what its budget leaves for the force this period; stops when the hub's capsule queue
-- is full.
local function place_orders(module, tick)
  local entity = module.entity
  if silence(entity) then return end
  local hub = hubs.trading_hub(module, circuit_orders.HUB_RANGE)
  local force_index = entity.force.index
  local state = storage.forces[force_index]
  if not (hub and state) then return end
  if freight.queued(hub.unit_number) >= freight.tier(hub.unit_number).max_capsules then return end
  local requests, budget, refused = orders.requests(entity.get_signals(W.circuit_red, W.circuit_green),
    circuit_orders.BUDGET_SIGNAL, circuit_orders.REFUSED_SIGNAL)
  if refused or budget <= 0 or #requests == 0 then return end
  local spent = spending(force_index, tick)
  for _, request in ipairs(requests) do
    local allowance = orders.allowance(budget, spent.credits, state.balance)
    if allowance <= 0 then return end
    local ok, paid, fee = freight.order(force_index, hub.unit_number, request.name, request.units,
      circuit_orders.JOURNAL_MERGE_TICKS, allowance, request.kind)
    if ok then
      spent.credits = spent.credits + paid + fee
    elseif paid == "queue-full" then
      return
    end
  end
end

--- on_nth_tick(PASS_TICKS): the order combinators of this pass's slot place their orders.
function circuit_orders.on_pass_tick(event)
  local slot = (event.tick / circuit_orders.PASS_TICKS) % circuit_orders.SLOTS
  for unit_number, module in pairs(storage.circuit_orders.modules) do
    if unit_number % circuit_orders.SLOTS == slot and module.entity.valid then place_orders(module, event.tick) end
  end
end

return circuit_orders
