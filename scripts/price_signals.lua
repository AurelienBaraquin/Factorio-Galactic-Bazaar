-- Price signal combinators (ADR-0010): constant combinators that emit, on the circuit network, the
-- buy or sell price of every tradeable item and fluid (normal quality) and the force's balance, each
-- through the nearest powered hub of its force in range (ADR-0005).
--
-- Prices are snapshot per force every UPDATE_TICKS, quoted SNAPSHOT_CHUNK per pass so that no tick
-- pays for all of them; a snapshot gets a new version only when a price changed. A combinator holds
-- two sections the script owns: the prices (rewritten whole when the version changed, the costly
-- write) and the balance (one slot, read live at each visit). Every PASS_TICKS, up to VISITS
-- combinators are visited in turn, stopping after one price rewrite. State lives in
-- storage.price_signals.
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local signals = require("scripts.core.signals")

local price_signals = {}

price_signals.KINDS = { ["gb-buy-price-combinator"] = "buy", ["gb-sell-price-combinator"] = "sell" }
price_signals.HUB_RANGE = 10
-- Age, in ticks, after which a force's price snapshot is taken again.
price_signals.UPDATE_TICKS = 600
-- Ticks between two passes, and combinators visited per pass (a pass stops after one price rewrite).
price_signals.PASS_TICKS = 6
price_signals.VISITS = 10
-- Prices quoted per pass while a snapshot is being built.
price_signals.SNAPSHOT_CHUNK = 40
price_signals.BALANCE_SIGNAL = "gb-credits"

local PRICES, BALANCE = 1, 2

local function filter(type, name, value)
  return { value = { type = type, name = name, quality = "normal", comparator = "=" }, min = value }
end

local function same_filters(a, b)
  if #a ~= #b then return false end
  for i, entry in ipairs(a) do
    if entry.min ~= b[i].min or entry.value.name ~= b[i].value.name or entry.value.type ~= b[i].value.type then
      return false
    end
  end
  return true
end

-- Quotes the next SNAPSHOT_CHUNK keys of a force's snapshot in progress, from the lists of tradeable
-- keys captured when it started (an override may replace them meanwhile); when it reaches the end,
-- publishes it, with a new version only if a price changed.
local function advance(force_index, builder)
  for _ = 1, price_signals.SNAPSHOT_CHUNK do
    local kind, name
    if builder.index <= #builder.items then
      kind, name = "item", builder.items[builder.index]
    elseif builder.index <= #builder.items + #builder.fluids then
      kind, name = "fluid", builder.fluids[builder.index - #builder.items]
    else
      local previous = storage.price_signals.snapshots[force_index]
      local unchanged = previous and same_filters(previous.buy, builder.buy)
        and same_filters(previous.sell, builder.sell)
      storage.price_signals.snapshots[force_index] = {
        tick = builder.tick, buy = builder.buy, sell = builder.sell,
        version = previous and (unchanged and previous.version or previous.version + 1) or 1,
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
    state.builders[force_index] = {
      tick = game.tick, index = 1, items = storage.tradeable_items, fluids = storage.tradeable_fluids,
      buy = {}, sell = {},
    }
  end
  return current
end

-- Gives a combinator exactly the two plain sections the script owns (no group, active, multiplier
-- 1), recreating them if anything else is there (a blueprint, pasted settings, another mod). Returns
-- true when it had to.
local function own_sections(behavior)
  local plain = behavior.sections_count == 2
  for i = 1, plain and 2 or 0 do
    local section = behavior.get_section(i)
    plain = plain and section.is_manual and section.group == "" and section.active and section.multiplier == 1
  end
  if plain then return false end
  for i = behavior.sections_count, 1, -1 do behavior.remove_section(i) end
  behavior.add_section()
  behavior.add_section()
  return true
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
    module.written, module.written_balance = nil, nil
  end
  state.snapshots = {}
  state.builders = {}
end

--- Registers a newly built combinator; returns true when the entity was one (already registered
--- included). It stays silent until its first update, and players cannot open it (the script owns
--- its signals).
function price_signals.on_built(entity)
  local side = price_signals.KINDS[entity.name]
  if not side then return false end
  local state = storage.price_signals
  if state.modules[entity.unit_number] then return true end
  entity.operable = false
  local behavior = entity.get_or_create_control_behavior()
  own_sections(behavior)
  behavior.enabled = false
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

--- on_entity_settings_pasted: pasted signals on one of our combinators are replaced at its next visit.
function price_signals.on_settings_pasted(event)
  local module = event.destination.valid and storage.price_signals.modules[event.destination.unit_number]
  if module then module.written, module.written_balance = nil, nil end
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

--- on_forces_merged: combinators now belong to the merged force and may use its hubs; the merged
--- force's snapshot goes, since its index may be given to a new force.
function price_signals.on_forces_merged(event)
  local state = storage.price_signals
  state.snapshots[event.source_index] = nil
  state.builders[event.source_index] = nil
  for _, module in pairs(state.modules) do
    hubs.attach(module, price_signals.HUB_RANGE)
    module.written, module.written_balance = nil, nil
  end
end

-- Brings a combinator up to date: silences it without a powered hub; otherwise rewrites its prices
-- when its force's snapshot version changed and its balance slot when the balance changed. Returns
-- true when it rewrote the prices.
local function update(module)
  local entity = module.entity
  if not entity.valid then return false end
  local behavior = entity.get_or_create_control_behavior()
  local force_index = entity.force.index
  if not hubs.trading_hub(module, price_signals.HUB_RANGE) or not storage.forces[force_index] then
    if behavior.enabled then behavior.enabled = false end
    module.written, module.written_balance = nil, nil
    return false
  end
  local current = snapshot(force_index)
  if not current then return false end
  if own_sections(behavior) or module.force_index ~= force_index then
    module.written, module.written_balance = nil, nil
  end
  local rewrote = false
  if module.written ~= current.version then
    behavior.get_section(PRICES).filters = current[module.side]
    module.written, module.force_index, rewrote = current.version, force_index, true
  end
  local balance = signals.balance(storage.forces[force_index].balance)
  if module.written_balance ~= balance then
    local section = behavior.get_section(BALANCE)
    if balance == 0 then
      section.clear_slot(1)
    else
      section.set_slot(1, filter("virtual", price_signals.BALANCE_SIGNAL, balance))
    end
    module.written_balance = balance
  end
  if not behavior.enabled then behavior.enabled = true end
  return rewrote
end

--- on_nth_tick(PASS_TICKS): advances the snapshots being built, then visits up to VISITS
--- combinators in turn, stopping after one price rewrite.
function price_signals.on_pass_tick()
  local state = storage.price_signals
  for force_index, builder in pairs(state.builders) do
    if storage.forces[force_index] then advance(force_index, builder) else state.builders[force_index] = nil end
  end
  local order = state.order
  for _ = 1, math.min(price_signals.VISITS, #order) do
    if state.cursor > #order then state.cursor = 1 end
    local module = state.modules[order[state.cursor]]
    state.cursor = state.cursor + 1
    if module and update(module) then return end
  end
end

return price_signals
