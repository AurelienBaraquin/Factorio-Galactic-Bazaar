-- Market events (#120, ADR-0025): shortages, surpluses and crises that move the market of some goods
-- for a while. Pure Lua: the adapter (scripts/market_events.lua) keeps one state for the galaxy in
-- storage.market_events and adds each key's shift to the displacement of every force's market.
--
-- An event acts like a flow of NPC trades on its goods: their displacement (scripts/core/market.lua)
-- moves towards a goal and decays like any displacement, with the market's half-life h. Within a
-- segment that starts at tick t0 with shift x0, the shift is G + (x0 - G) 2^(-(t - t0)/h), G the goal.
-- At every pass while the event is active, from the random state, the event may end early, or the
-- goal takes a bounded random step; the new segment starts from the shift reached, so the shift stays
-- continuous and prices never jump. After its end the shift halves every h. Shifts are in market
-- depths: negative pushes prices up. The goal never crosses zero, so an event's shift keeps its sign.
--
-- An event only makes prices worse for the trader (scripts/core/market.lua, shifted prices): a
-- shortage raises what buyers pay, a surplus lowers what sellers get, the other side staying the
-- plain price. So any trade under an event is at most as good as the same trade without it, whatever
-- the event's course and whatever a player knows of it. A key gets no other event until its last one
-- is forgotten (draw below), so a good has one event at a time.
--
-- Draws and steps come from one random state seeded from the map and mixed, at each draw and pass,
-- with `entropy` from the adapter: figures every peer shares but nobody can know in advance (the
-- forces' balances and journals). Never from the tick alone. Whether a forecast is called off and its
-- first goal are drawn when it is due to start, not when it is drawn, so not even the saved state
-- tells them early.
local quality = require("scripts.core.quality")
local random = require("scripts.core.random")

local market_events = {}

-- Bounds of the two settings (settings.lua reads them).
market_events.LIMITS = { min_frequency = 0, max_frequency = 4, min_magnitude = 0.25, max_magnitude = 3 }

market_events.DEFAULTS = {
  -- Mean ticks between two draws at frequency 1 (30 min); each interval is 0.5 to 1.5 times it,
  -- divided by the frequency.
  interval_ticks = 108000,
  -- How long before its start an announced event is told.
  warning_ticks = 18000,
  announce_chance = 0.5,
  -- Share of announced events called off when due.
  cancel_chance = 0.25,
  -- Longest an event may last; it may end at any pass before.
  min_duration_ticks = 36000,
  max_duration_ticks = 108000,
  -- Ticks between two passes (the adapter's PASS_TICKS), and the chance an active event ends at each.
  pass_ticks = 600,
  end_chance = 1 / 180,
  -- Largest step of the goal at each pass, in depths at magnitude 1.
  goal_step = 0.03,
  -- Most events announced or active at once.
  max_open = 3,
  crisis_min_keys = 3,
  crisis_max_keys = 12,
  -- Half-lives after its end at which an event is forgotten: its shift is then below 2^-10 (0.1 %) of
  -- what it was at its end.
  retention_half_lives = 10,
  -- Knots of an event's past path kept for the NPC price history (one per NPC step).
  trail_size = 31,
  trail_ticks = 3600,
  -- Kinds, drawn in this order by weight. Goals are in depths towards the kind's `direction` (-1
  -- pushes prices up), times the magnitude: the first goal is drawn in [start_low, start_high], later
  -- ones stay in [0, ceiling].
  kind_order = { "shortage", "surplus", "crisis" },
  kinds = {
    shortage = { weight = 0.4, direction = -1, start_low = 0.4, start_high = 1.0, ceiling = 1.5 },
    surplus = { weight = 0.4, direction = 1, start_low = 0.4, start_high = 1.0, ceiling = 1.5 },
    crisis = { weight = 0.2, direction = -1, start_low = 0.25, start_high = 0.6, ceiling = 0.9 },
  },
}

local MODULUS = 2147483647

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function roll(state)
  local value
  state.rng, value = random.next(state.rng)
  return value
end

--- Mixes `entropy` (a number every peer shares, unknown in advance) into the random state.
function market_events.mix(state, entropy)
  local rng = random.seed((state.rng + math.floor(math.abs(entropy or 0)) % MODULUS) % MODULUS)
  -- A first draw after seeding is nearly proportional to the seed: close entropies would give close
  -- rolls. Three steps scatter them.
  for _ = 1, 3 do rng = random.next(rng) end
  state.rng = rng
end

-- Ticks until the next draw: 0.5 to 1.5 mean intervals at `frequency`; one mean interval (a later
-- check) when events are off.
local function interval(state, frequency, params)
  frequency = clamp(frequency or 1, market_events.LIMITS.min_frequency, market_events.LIMITS.max_frequency)
  if frequency <= 0 then return params.interval_ticks end
  return math.floor(params.interval_ticks * (0.5 + roll(state)) / frequency)
end

--- Rebuilds the index of the events by key ({[key] = {event...}}, oldest first).
function market_events.reindex(state)
  local by_key = {}
  for _, event in ipairs(state.events) do
    for _, key in ipairs(event.keys) do
      local list = by_key[key]
      if not list then
        list = {}
        by_key[key] = list
      end
      list[#list + 1] = event
    end
  end
  state.by_key = by_key
end

--- A new state from `seed` (the map's, never the tick), its first draw scheduled from `tick`.
function market_events.new_state(seed, tick, frequency, params)
  local state = { rng = random.seed(seed), next_id = 1, events = {}, by_key = {} }
  state.next_tick = tick + interval(state, frequency, params)
  return state
end

--- "announced" before its start, "active" until its end, then "ended"; a called-off event is
--- "cancelled" from its start.
function market_events.phase(event, tick)
  if tick < event.start_tick then return "announced" end
  if event.cancelled then return "cancelled" end
  if tick < event.end_tick then return "active" end
  return "ended"
end

local function is_open(event, tick)
  local phase = market_events.phase(event, tick)
  return phase == "announced" or phase == "active"
end

--- Events announced or active at `tick`.
function market_events.open_count(state, tick)
  local count = 0
  for _, event in ipairs(state.events) do
    if is_open(event, tick) then count = count + 1 end
  end
  return count
end

-- Keys of `keys` that no open event touches.
local function free_keys(keys, busy)
  local free = {}
  for _, key in ipairs(keys) do
    if not busy[key] then free[#free + 1] = key end
  end
  return free
end

local function pick_kind(state, params)
  local total = 0
  for _, name in ipairs(params.kind_order) do total = total + params.kinds[name].weight end
  local target = roll(state) * total
  for _, name in ipairs(params.kind_order) do
    target = target - params.kinds[name].weight
    if target <= 0 then return name end
  end
  return params.kind_order[#params.kind_order]
end

-- The keys and family of an event of `kind`, from the free candidates; nil when there are none.
local function pick_keys(state, kind, candidates, busy, params)
  if kind ~= "crisis" then
    -- Most keys are free: a few random tries, then the free list only when they all hit busy keys.
    local keys = candidates.keys
    for _ = 1, 4 do
      if #keys == 0 then return nil end
      local key = keys[math.min(#keys, math.floor(roll(state) * #keys) + 1)]
      if not busy[key] then return { key } end
    end
    local free = free_keys(keys, busy)
    if #free == 0 then return nil end
    return { free[math.min(#free, math.floor(roll(state) * #free) + 1)] }
  end
  local families = {}
  for _, family in ipairs(candidates.families) do
    local free = free_keys(family.keys, busy)
    if #free >= params.crisis_min_keys then families[#families + 1] = { name = family.name, keys = free } end
  end
  if #families == 0 then return nil end
  local family = families[math.min(#families, math.floor(roll(state) * #families) + 1)]
  local keys = family.keys
  -- A random subset when the family is larger than a crisis: partial Fisher-Yates, then sorted.
  local count = math.min(#keys, params.crisis_max_keys)
  for i = 1, count do
    local j = math.min(#keys, i + math.floor(roll(state) * (#keys - i + 1)))
    keys[i], keys[j] = keys[j], keys[i]
  end
  local chosen = {}
  for i = 1, count do chosen[i] = keys[i] end
  table.sort(chosen)
  return chosen, family.name
end

--- Draws the next event when `tick` reached the scheduled draw: mixes `entropy` into the random
--- state, schedules the following draw, then returns the new event (also appended to `state.events`),
--- or nil when events are off, `max_open` are already open or no candidate key is free (a key is
--- busy while any event of it is kept, fading ones included). `candidates` = {keys = sorted
--- "item/<name>" and "fluid/<name>", families = {{name, keys}...} sorted}, or a function returning
--- it, called only when an event can be drawn; `settings` = {frequency, magnitude}. An event: {id,
--- kind, family (a crisis), keys, direction, magnitude (the setting it was drawn at, bounded), goal
--- (towards its direction, in depths; nil until it starts), segment_tick, segment_shift, trail,
--- announce_tick (nil when not announced), start_tick, end_tick (its latest end), cancelled (decided
--- when it starts)}.
function market_events.draw(state, tick, candidates, settings, params, entropy)
  if tick < state.next_tick then return nil end
  market_events.mix(state, entropy)
  local frequency = clamp(settings.frequency or 1, market_events.LIMITS.min_frequency,
    market_events.LIMITS.max_frequency)
  state.next_tick = tick + interval(state, frequency, params)
  if frequency <= 0 or market_events.open_count(state, tick) >= params.max_open then return nil end
  if type(candidates) == "function" then candidates = candidates() end
  local kind = pick_kind(state, params)
  local keys, family = pick_keys(state, kind, candidates, state.by_key or {}, params)
  if not keys then return nil end
  local spec = params.kinds[kind]
  local magnitude = clamp(settings.magnitude or 1, market_events.LIMITS.min_magnitude,
    market_events.LIMITS.max_magnitude)
  local duration = math.floor(params.min_duration_ticks
    + (params.max_duration_ticks - params.min_duration_ticks) * roll(state))
  local announced = roll(state) < params.announce_chance
  local start = announced and tick + params.warning_ticks or tick
  local event = { id = state.next_id, kind = kind, family = family, keys = keys, direction = spec.direction,
    magnitude = magnitude, segment_tick = start, segment_shift = 0, trail = { { start, 0 } },
    announce_tick = announced and tick or nil, start_tick = start, end_tick = start + duration }
  state.next_id = state.next_id + 1
  state.events[#state.events + 1] = event
  market_events.reindex(state)
  return event
end

-- The shift of the event's current segment at `tick` (no earlier than its start).
local function segment(event, tick, half_life_ticks)
  local goal = event.direction * event.goal
  return goal + (event.segment_shift - goal) * 0.5 ^ ((tick - event.segment_tick) / half_life_ticks)
end

-- The shift at `tick`, before the current segment began: linear between the knots of the trail and
-- the segment's start (for the NPC price history only).
local function past(event, tick)
  local trail = event.trail
  local previous = trail[1]
  if tick <= previous[1] then return previous[2] end
  for i = 2, #trail + 1 do
    local knot = trail[i] or { event.segment_tick, event.segment_shift }
    if tick <= knot[1] then
      local span = knot[1] - previous[1]
      if span <= 0 then return knot[2] end
      return previous[2] + (knot[2] - previous[2]) * (tick - previous[1]) / span
    end
    previous = knot
  end
  return event.segment_shift
end

--- The shift an event gives its goods' displacement at `tick`, in market depths (negative pushes
--- prices up): 0 before its start and when called off; on its current segment, or interpolated on
--- its trail before that segment; after its end, its shift at the end halving every half-life.
function market_events.depths(event, tick, half_life_ticks)
  if event.cancelled or not event.goal or tick <= event.start_tick then return 0 end
  if tick >= event.end_tick then
    local at_end = event.end_shift or segment(event, event.end_tick, half_life_ticks)
    return at_end * 0.5 ^ ((tick - event.end_tick) / half_life_ticks)
  end
  if tick < event.segment_tick then return past(event, tick) end
  return segment(event, tick, half_life_ticks)
end

--- The events of a market key (any quality), oldest first; an empty table without any.
local NONE = {}
function market_events.events_of(state, key)
  if not (state and state.by_key) then return NONE end
  local found = state.by_key[key]
  if found then return found end
  -- A key of another quality has an "@"; most reads are of normal keys, which need no split.
  if not key:find("@", 1, true) then return NONE end
  local base_key = quality.split(key)
  return base_key ~= key and state.by_key[base_key] or NONE
end

--- The total shift of a market key (any quality) at `tick`, in depths; 0 without a state.
function market_events.key_depths(state, key, tick, half_life_ticks)
  local total = 0
  for _, event in ipairs(market_events.events_of(state, key)) do
    total = total + market_events.depths(event, tick, half_life_ticks)
  end
  return total
end

-- At the first pass at or after an event's start: whether a forecast is called off and its first goal.
local function begin(state, event, tick, params)
  if event.announce_tick and roll(state) < params.cancel_chance then
    event.cancelled = true
    return
  end
  local spec = params.kinds[event.kind]
  event.goal = (spec.start_low + (spec.start_high - spec.start_low) * roll(state)) * event.magnitude
  event.segment_tick, event.segment_shift = tick, 0
end

--- At each pass, for every event active at `tick`: mixes `entropy` into the random state once; an
--- event due to start is called off (a forecast, chance `cancel_chance`) or gets its first goal; a
--- running one ends now with chance `end_chance`, or starts a new segment from the shift reached
--- with the goal moved by at most `goal_step` (× magnitude), kept between 0 and the kind's ceiling. A
--- knot of the path is kept every `trail_ticks` for the price history.
function market_events.evolve(state, tick, half_life_ticks, params, entropy)
  local mixed = false
  for _, event in ipairs(state.events) do
    local active = market_events.phase(event, tick) == "active"
    local starting = active and not event.goal
    if starting or (active and tick > event.segment_tick) then
      if not mixed then
        market_events.mix(state, entropy)
        mixed = true
      end
    end
    if starting then
      begin(state, event, tick, params)
    elseif active and tick > event.segment_tick then
      local shift = segment(event, tick, half_life_ticks)
      local trail = event.trail
      if tick >= trail[#trail][1] + params.trail_ticks then
        trail[#trail + 1] = { tick, shift }
        if #trail > params.trail_size then table.remove(trail, 1) end
      end
      if roll(state) < params.end_chance then
        event.end_tick, event.end_shift = tick, shift
      else
        local spec = params.kinds[event.kind]
        local step = (2 * roll(state) - 1) * params.goal_step * event.magnitude
        event.goal = clamp(event.goal + step, 0, spec.ceiling * event.magnitude)
        event.segment_tick, event.segment_shift = tick, shift
      end
    end
  end
end

-- What to tell for each phase.
local NOTICES = { announced = "announced", active = "started", cancelled = "cancelled", ended = "ended" }

--- The phase changes not told yet at `tick`, oldest event first: {{event, notice}...}, `notice`
--- "announced", "started", "cancelled" or "ended"; each is marked told (`event.told`).
function market_events.notices(state, tick)
  local result = {}
  for _, event in ipairs(state.events) do
    local phase = market_events.phase(event, tick)
    if event.told ~= phase then
      event.told = phase
      result[#result + 1] = { event = event, notice = NOTICES[phase] }
    end
  end
  return result
end

--- Drops called-off events once due and ended ones `retention_half_lives` after their end.
function market_events.prune(state, tick, half_life_ticks, params)
  local kept = {}
  for _, event in ipairs(state.events) do
    local phase = market_events.phase(event, tick)
    local forgotten = phase == "cancelled"
      or tick >= event.end_tick + params.retention_half_lives * half_life_ticks
    if not forgotten then kept[#kept + 1] = event end
  end
  if #kept ~= #state.events then
    state.events = kept
    market_events.reindex(state)
  end
end

--- Keeps only the keys present in `values` ([key] = value, the base values), and the events that
--- still have one.
function market_events.retain_keys(state, values)
  local kept = {}
  for _, event in ipairs(state.events) do
    local keys = {}
    for _, key in ipairs(event.keys) do
      if values[key] then keys[#keys + 1] = key end
    end
    event.keys = keys
    if #keys > 0 then kept[#kept + 1] = event end
  end
  state.events = kept
  market_events.reindex(state)
end

-- Salts of the NPC drift (scripts/core/npc_market.lua): one per minute of game time, drawn from the
-- mixed random state at the first pass of that minute, kept for SALT_SLOTS minutes (more than the
-- steps an NPC catch-up ever runs). A step uses the salt of the minute before its own, which is always
-- drawn by then; a minute without one (before the state existed) has none.
local SALT_SLOTS = 32
local MINUTE = 3600

--- At each pass: draws the salt of the current minute if it is not drawn yet, after mixing `entropy`.
function market_events.draw_salt(state, tick, entropy)
  local minute = math.floor(tick / MINUTE)
  state.salts = state.salts or {}
  local slot = state.salts[minute % SALT_SLOTS + 1]
  if slot and slot[1] == minute then return end
  market_events.mix(state, entropy)
  state.salts[minute % SALT_SLOTS + 1] = { minute, roll(state) }
end

--- The salt of an NPC step at `tick`: the one of the minute before, or nil when it is not kept.
function market_events.salt_at(state, tick)
  local minute = math.floor(tick / MINUTE) - 1
  local slot = state and state.salts and state.salts[minute % SALT_SLOTS + 1]
  if slot and slot[1] == minute then return slot[2] end
  return nil
end

-- Whether an event has the shape this version reads, its goal and shifts on its own side of zero.
local function valid(event)
  if type(event) ~= "table" or not (event.trail and event.direction and event.keys and event.start_tick
    and event.end_tick and event.segment_tick and event.segment_shift) then
    return false
  end
  local direction = event.direction
  return (event.goal == nil or event.goal >= 0) and event.segment_shift * direction >= 0
    and (event.end_shift == nil or event.end_shift * direction >= 0)
end

--- Drops the events that lack the fields this version reads or whose goal or shift is on the wrong
--- side of zero (development saves of 0.1.36 kept such events), and rebuilds the index. Returns how
--- many were dropped.
function market_events.drop_invalid(state)
  local kept = {}
  for _, event in ipairs(state.events or {}) do
    if valid(event) then kept[#kept + 1] = event end
  end
  local dropped = #(state.events or {}) - #kept
  state.events = kept
  market_events.reindex(state)
  return dropped
end

--- The range of the factor an event of `kind` drawn at `magnitude` can put on the mid price: low,
--- high (1 and the factor at its ceiling, in either order).
function market_events.effect_range(kind, magnitude, params)
  local spec = params.kinds[kind]
  magnitude = clamp(magnitude, market_events.LIMITS.min_magnitude, market_events.LIMITS.max_magnitude)
  local far = math.exp(-spec.direction * spec.ceiling * magnitude)
  return math.min(1, far), math.max(1, far)
end

return market_events
