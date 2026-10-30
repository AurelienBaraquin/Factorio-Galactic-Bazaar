-- Price signal combinators (ADR-0010): constant combinators that emit, on the circuit network, the
-- buy or sell price of every tradeable item and fluid (normal quality) and the force's balance, each
-- through the nearest powered hub of its force in range (ADR-0005). Prices are snapshot per force
-- every UPDATE_TICKS, built SNAPSHOT_CHUNK prices per pass so that no tick pays for all of them;
-- combinators keep the last complete snapshot meanwhile, and are rewritten one per PASS_TICKS, in
-- turn, only when their force's snapshot changed. State lives in storage.price_signals.
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local signals = require("scripts.core.signals")

local price_signals = {}

price_signals.KINDS = { ["gb-buy-price-combinator"] = "buy", ["gb-sell-price-combinator"] = "sell" }
price_signals.HUB_RANGE = 10
-- Age, in ticks, after which a force's price snapshot is taken again.
price_signals.UPDATE_TICKS = 600
-- Ticks between two combinator visits, and combinators visited per pass.
price_signals.PASS_TICKS = 6
price_signals.BATCH = 1
-- Prices quoted per pass while a snapshot is being built.
price_signals.SNAPSHOT_CHUNK = 40
price_signals.BALANCE_SIGNAL = "gb-credits"

local function filter(type, name, value)
  return { value = { type = type, name = name, quality = "normal", comparator = "=" }, min = value }
end

-- Tradeable keys in snapshot order: every item, then every fluid. Returns the kind and name of the
-- `index`-th, or nil past the end.
local function key_at(index)
  local items = storage.tradeable_items
  if index <= #items then return "item", items[index] end
  local name = storage.tradeable_fluids[index - #items]
  return name and "fluid", name
end

-- Quotes the next SNAPSHOT_CHUNK keys of a force's snapshot in progress; when it reaches the end,
-- adds the balance and publishes it as the force's snapshot.
local function advance(force_index, builder)
  for _ = 1, price_signals.SNAPSHOT_CHUNK do
    local kind, name = key_at(builder.index)
    if not kind then
      local balance = signals.balance(storage.forces[force_index].balance)
      if balance ~= 0 then
        builder.buy[#builder.buy + 1] = filter("virtual", price_signals.BALANCE_SIGNAL, balance)
        builder.sell[#builder.sell + 1] = filter("virtual", price_signals.BALANCE_SIGNAL, balance)
      end
      local previous = storage.price_signals.snapshots[force_index]
      storage.price_signals.snapshots[force_index] = {
        tick = builder.tick, version = (previous and previous.version or 0) + 1, buy = builder.buy, sell = builder.sell,
      }
      storage.price_signals.builders[force_index] = nil
      return
    end
    builder.index = builder.index + 1
    local quote = market.quote(force_index, kind, name)
    if quote then
      local buy_value, sell_value = signals.price(quote.buy), signals.price(quote.sell)
      if buy_value ~= 0 then builder.buy[#builder.buy + 1] = filter(kind, name, buy_value) end
      if sell_value ~= 0 then builder.sell[#builder.sell + 1] = filter(kind, name, sell_value) end
    end
  end
end

-- The force's last complete snapshot (nil before the first one); starts building a new one when it
-- is missing or older than UPDATE_TICKS.
local function snapshot(force_index)
  local state = storage.price_signals
  local current = state.snapshots[force_index]
  local stale = not current or game.tick - current.tick >= price_signals.UPDATE_TICKS
  if stale and not state.builders[force_index] then
    state.builders[force_index] = { tick = game.tick, index = 1, buy = {}, sell = {} }
  end
  return current
end

--- on_init and on_configuration_changed: creates the state, drops combinators that no longer exist,
--- re-attaches the others and forgets every snapshot (prices or signals may have changed).
function price_signals.init()
  storage.price_signals = storage.price_signals or { modules = {}, order = {}, cursor = 1 }
  local state = storage.price_signals
  local gone = {}
  for unit_number, module in pairs(state.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do price_signals.forget(unit_number) end
  for _, module in pairs(state.modules) do
    hubs.attach(module, price_signals.HUB_RANGE)
    module.written = nil
  end
  state.snapshots = {}
  state.builders = {}
end

--- Registers a newly built combinator; returns true when the entity was one. It stays silent until
--- its first update, and players cannot open it (the script owns its signals).
function price_signals.on_built(entity)
  local side = price_signals.KINDS[entity.name]
  if not side then return false end
  entity.operable = false
  entity.get_or_create_control_behavior().enabled = false
  local state = storage.price_signals
  local module = { entity = entity, side = side }
  hubs.attach(module, price_signals.HUB_RANGE)
  state.modules[entity.unit_number] = module
  state.order[#state.order + 1] = entity.unit_number
  module.order_index = #state.order
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed combinator, leaving the visiting order in O(1); returns true when the unit
--- number was one.
function price_signals.forget(unit_number)
  local state = storage.price_signals
  local module = state.modules[unit_number]
  if not module then return false end
  state.modules[unit_number] = nil
  local order, index = state.order, module.order_index
  local last = #order
  if index ~= last then
    order[index] = order[last]
    state.modules[order[index]].order_index = index
  end
  order[last] = nil
  if state.cursor > last then state.cursor = 1 end
  return true
end

--- A hub appeared: combinators in its range move to it if it is now their nearest hub.
function price_signals.on_hub_built(hub)
  local names = {}
  for name in pairs(price_signals.KINDS) do names[#names + 1] = name end
  local nearby = hub.surface.find_entities_filtered({
    name = names, force = hub.force, position = hub.position, radius = price_signals.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.price_signals.modules[entity.unit_number]
    if module then hubs.attach(module, price_signals.HUB_RANGE) end
  end
end

--- A hub disappeared: its combinators look for another hub in range.
function price_signals.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.price_signals.modules) do
    if module.hub == hub_unit_number then hubs.attach(module, price_signals.HUB_RANGE) end
  end
end

--- on_forces_merged: combinators now belong to the merged force and may use its hubs.
function price_signals.on_forces_merged()
  for _, module in pairs(storage.price_signals.modules) do
    hubs.attach(module, price_signals.HUB_RANGE)
    module.written = nil
  end
end

-- Writes the force's current signals into a combinator if they changed; silences it without a
-- powered hub.
local function update(module)
  local entity = module.entity
  if not entity.valid then return end
  local behavior = entity.get_or_create_control_behavior()
  if not hubs.trading_hub(module, price_signals.HUB_RANGE) or not storage.forces[entity.force.index] then
    if behavior.enabled then behavior.enabled = false end
    module.written = nil
    return
  end
  local current = snapshot(entity.force.index)
  if not current or (module.written == current.version and module.force_index == entity.force.index) then return end
  local section = behavior.get_section(1) or behavior.add_section()
  section.filters = current[module.side]
  for i = behavior.sections_count, 2, -1 do behavior.remove_section(i) end
  behavior.enabled = true
  module.written, module.force_index = current.version, entity.force.index
end

--- on_nth_tick(PASS_TICKS): advances the snapshots being built, then updates the next BATCH
--- combinators.
function price_signals.on_pass_tick()
  local state = storage.price_signals
  for force_index, builder in pairs(state.builders) do
    if storage.forces[force_index] then advance(force_index, builder) else state.builders[force_index] = nil end
  end
  local order = state.order
  for _ = 1, math.min(price_signals.BATCH, #order) do
    if state.cursor > #order then state.cursor = 1 end
    local module = state.modules[order[state.cursor]]
    state.cursor = state.cursor + 1
    if module then update(module) end
  end
end

return price_signals
