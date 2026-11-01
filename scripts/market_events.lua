-- Market events (#120, ADR-0025): shortages, surpluses and crises drawn for the whole galaxy, kept in
-- storage.market_events and told to the forces that have researched the Galactic Bazaar. The rules
-- are in scripts/core/market_events.lua; scripts/market.lua adds each key's shift to every force's
-- displacement when it reads a market. A pass every PASS_TICKS draws the next event when it is due,
-- moves the active events along their uncertain path, tells the phase changes and forgets old events;
-- the settings gb-market-events-frequency and -magnitude are read at each draw.
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local core = require("scripts.core.market_events")
local market_model = require("scripts.core.market")
local notifications = require("scripts.notifications")

local market_events = {}

market_events.PARAMS = core.DEFAULTS
market_events.PASS_TICKS = core.DEFAULTS.pass_ticks
market_events.FREQUENCY_SETTING = "gb-market-events-frequency"
market_events.MAGNITUDE_SETTING = "gb-market-events-magnitude"
market_events.HALF_LIFE_TICKS = market_model.DEFAULTS.half_life_ticks

local PARAMS = market_events.PARAMS
local HALF_LIFE = market_events.HALF_LIFE_TICKS

--- The two settings now: {frequency, magnitude}.
function market_events.settings()
  return { frequency = settings.global[market_events.FREQUENCY_SETTING].value,
    magnitude = settings.global[market_events.MAGNITUDE_SETTING].value }
end

-- The state, created when missing: a save from before market events has none until
-- on_configuration_changed, which the pass can run before. Seeded from the map; every draw and pass
-- then mixes in the forces' accounts (entropy below). A development save of 0.1.36 may hold a state
-- without the index, whose events have another shape: they are dropped.
local function state()
  local current = storage.market_events
  if not current then
    current = core.new_state(game.default_map_gen_settings.seed * 31 + 17, game.tick,
      market_events.settings().frequency, PARAMS)
    storage.market_events = current
  elseif not current.by_key then
    core.drop_invalid(current)
  end
  return current
end

-- What the random state is mixed with: the forces' balances and journal sizes, the same on every peer
-- but unknown before they happen, plus the tick (never the tick alone).
local function entropy()
  local total = game.tick
  for index, force_state in pairs(storage.forces) do
    total = total + index * 104729 + math.floor(math.abs(force_state.balance or 0) * 1000) % 2147483647
      + #(force_state.journal or {}) * 7919
  end
  return total
end

-- What can be drawn: the tradeable items and fluids, and their families (item subgroups).
local function build_candidates()
  local keys, by_family = {}, {}
  local function add(kind, name, prototype)
    local key = kind .. "/" .. name
    keys[#keys + 1] = key
    local family = prototype.subgroup.name
    by_family[family] = by_family[family] or {}
    table.insert(by_family[family], key)
  end
  for _, name in ipairs(storage.tradeable_items or {}) do
    local prototype = prototypes.item[name]
    if prototype then add("item", name, prototype) end
  end
  for _, name in ipairs(storage.tradeable_fluids or {}) do
    local prototype = prototypes.fluid[name]
    if prototype then add("fluid", name, prototype) end
  end
  table.sort(keys)
  local families = {}
  for name, family_keys in pairs(by_family) do
    table.sort(family_keys)
    families[#families + 1] = { name = name, keys = family_keys }
  end
  table.sort(families, function(a, b) return a.name < b.name end)
  return { keys = keys, families = families }
end

-- The cached candidates, built when missing (a save from 0.1.36 before they were cached).
local function candidates()
  local current = state()
  current.candidates = current.candidates or build_candidates()
  return current.candidates
end

--- The base values were rebuilt (configuration change, an override): the candidates are built again
--- and goods that are no longer tradeable leave the events. Nothing before the state exists.
function market_events.on_values_rebuilt()
  local current = storage.market_events
  if not current then return end
  core.drop_invalid(current)
  core.retain_keys(current, storage.base_values)
  current.candidates = build_candidates()
end

--- on_init and on_configuration_changed (after base values are rebuilt): creates the state and
--- brings it in step with the base values.
function market_events.init()
  state()
  market_events.on_values_rebuilt()
end

--- The shift market events make on market key `key` at `tick` for a market `depth` units deep, in
--- units, and a function of the tick giving it for the NPC price history (nil without events).
function market_events.shift(key, tick, depth)
  local events = core.events_of(storage.market_events, key)
  if #events == 0 then return 0, nil end
  local function at(when)
    local total = 0
    for _, event in ipairs(events) do total = total + core.depths(event, when, HALF_LIFE) end
    return total * depth
  end
  return at(tick), at
end

--- The salt of an NPC step at `tick` (scripts/core/npc_market.lua), or nil.
function market_events.salt_at(tick)
  return core.salt_at(storage.market_events, tick)
end

--- The shift of `key` at `tick`, in market depths.
function market_events.depths(key, tick)
  return core.key_depths(storage.market_events, key, tick, HALF_LIFE)
end

--- The shift one event makes at `tick`, in market depths.
function market_events.event_depths(event, tick)
  return core.depths(event, tick, HALF_LIFE)
end

--- The events of a market key, oldest first (the item detail shows them).
function market_events.events_of(key)
  return core.events_of(storage.market_events, key)
end

--- Every event kept, oldest first (the Events tab lists them).
function market_events.list()
  return storage.market_events and storage.market_events.events or {}
end

--- The goods of an event as rich text icons, with the name of a single one.
function market_events.goods_caption(event)
  local icons = {}
  for _, key in ipairs(event.keys) do
    local kind, name = key:match("^(%a+)/(.+)$")
    icons[#icons + 1] = "[" .. kind .. "=" .. name .. "]"
  end
  if #event.keys ~= 1 then return table.concat(icons, "") end
  local kind, name = event.keys[1]:match("^(%a+)/(.+)$")
  local prototype = (kind == "item" and prototypes.item or prototypes.fluid)[name]
  return { "", icons[1], " ", prototype and prototype.localised_name or name }
end

--- A price factor as a signed percent change: "+65", "-33".
function market_events.percent(factor)
  return string.format("%+.0f", (factor - 1) * 100)
end

--- The range of what an event can do to the mid price, as a caption: never its own path.
function market_events.range_caption(event)
  local low, high = core.effect_range(event.kind, event.magnitude, PARAMS)
  return { "gb-events.effect-range", market_events.percent(low), market_events.percent(high) }
end

-- Whole minutes, rounded up: how long an event may still last is shown this coarsely.
local function minutes(ticks)
  return math.max(1, math.ceil(ticks / 3600))
end

--- Where an event stands at `tick`, as a caption: starts in, may last at most about N more minutes,
--- over since (its shift fading), or called off.
function market_events.phase_caption(event, tick)
  local phase = core.phase(event, tick)
  if phase == "announced" then
    return { "gb-events.phase-announced", catalog.format_duration(event.start_tick - tick) }
  elseif phase == "active" then
    return { "gb-events.phase-active", minutes(event.end_tick - tick) }
  elseif phase == "ended" then
    return { "gb-events.phase-ended", catalog.format_duration(tick - event.end_tick) }
  end
  return { "gb-events.phase-cancelled" }
end

--- What to do about an event, as a caption: events only ever make prices worse (ADR-0025), so the
--- answer is to avoid the side they hit.
function market_events.advice(event)
  return { "gb-events.advice-" .. event.kind }
end

-- The locale parameters of a notice: __1__ the kind, __2__ the goods, __3__ the time to the start
-- (announced) or the most minutes it may last (started) or the half-life (ended), __4__ the range of
-- its effect, __5__ the most minutes it may last from its start, __6__ what to do (announced and
-- started).
local function notice_parameters(event, notice, tick)
  local parameters = { { "gb-events.kind-" .. event.kind }, market_events.goods_caption(event) }
  local longest = minutes(event.end_tick - event.start_tick)
  if notice == "announced" then
    parameters[3] = catalog.format_duration(event.start_tick - tick)
    parameters[4] = market_events.range_caption(event)
    parameters[5] = longest
  elseif notice == "started" then
    parameters[3] = minutes(event.end_tick - tick)
    parameters[4] = market_events.range_caption(event)
    parameters[5] = longest
  elseif notice == "ended" then
    parameters[3] = catalog.format_duration(HALF_LIFE)
  end
  if notice == "announced" or notice == "started" then parameters[6] = market_events.advice(event) end
  parameters.group = event.id
  return parameters
end

-- The forces told of market events: those that have researched the Galactic Bazaar.
local function told_forces()
  local forces = {}
  for index in pairs(storage.forces) do
    local force = game.forces[index]
    if force and bazaar_gui.researched(force) then forces[#forces + 1] = force end
  end
  return forces
end

--- Every PASS_TICKS: draws the next event when due, moves the active events, tells the forces that
--- researched the Galactic Bazaar of the phase changes, forgets events whose shift is gone.
function market_events.on_pass_tick(event)
  local current = state()
  local tick = event.tick
  core.draw_salt(current, tick, entropy())
  if tick >= current.next_tick then
    core.draw(current, tick, candidates, market_events.settings(), PARAMS, entropy())
  end
  if #current.events == 0 then return end
  core.evolve(current, tick, HALF_LIFE, PARAMS, entropy())
  local changes = core.notices(current, tick)
  if #changes > 0 then
    local forces = told_forces()
    for _, change in ipairs(changes) do
      local parameters = notice_parameters(change.event, change.notice, tick)
      for _, force in ipairs(forces) do
        notifications.notify(force, "market-event-" .. change.notice, parameters)
      end
    end
  end
  core.prune(current, tick, HALF_LIFE, PARAMS)
end

return market_events
