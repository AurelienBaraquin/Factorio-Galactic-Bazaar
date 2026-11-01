local market = require("scripts.core.market")
local market_events = require("scripts.core.market_events")
local random = require("scripts.core.random")

local params = market_events.DEFAULTS
local HALF_LIFE = 36000
local PASS = params.pass_ticks
local ON = { frequency = 1, magnitude = 1 }

local function candidates()
  local keys = {}
  for i = 1, 20 do keys[i] = string.format("item/good-%02d", i) end
  return {
    keys = keys,
    families = {
      { name = "metals", keys = { "item/good-01", "item/good-02", "item/good-03", "item/good-04" } },
      { name = "pair", keys = { "item/good-05", "item/good-06" } },
    },
  }
end

-- A started event of `kind` on `keys` with goal `goal` (towards its direction), from `start` for at
-- most `duration` ticks.
local function event(kind, keys, goal, start, duration, cancelled)
  return { id = 1, kind = kind, keys = keys, direction = params.kinds[kind].direction, magnitude = 1, goal = goal,
    segment_tick = start, segment_shift = 0, trail = { { start, 0 } }, start_tick = start,
    end_tick = start + duration, cancelled = cancelled }
end

local function state_of(events)
  local state = { rng = 1, next_id = #events + 1, events = events }
  market_events.reindex(state)
  return state
end

-- Draws events until one comes, at most `tries` due draws; returns it and the tick it came at.
local function draw_one(state, settings, tries)
  for _ = 1, tries or 50 do
    local tick = state.next_tick
    local drawn = market_events.draw(state, tick, candidates(), settings or ON, params, 0)
    if drawn then return drawn, tick end
  end
end

local function near(a, b, tolerance)
  return math.abs(a - b) <= (tolerance or 1e-12) * math.max(1, math.abs(a))
end

describe("market_events.new_state", function()
  it("schedules the first draw within half to one and a half mean intervals", function()
    local state = market_events.new_state(42, 1000, 1, params)
    assert.is_true(state.next_tick >= 1000 + params.interval_ticks / 2)
    assert.is_true(state.next_tick <= 1000 + params.interval_ticks * 1.5)
    assert.are.same({}, state.events)
  end)

  it("follows the seed, not the tick", function()
    local a = market_events.new_state(42, 0, 1, params)
    local b = market_events.new_state(42, 5000, 1, params)
    local c = market_events.new_state(43, 0, 1, params)
    assert.are.equal(a.next_tick, b.next_tick - 5000)
    assert.are_not.equal(a.next_tick, c.next_tick)
  end)
end)

describe("market_events.mix", function()
  it("changes the random state with the entropy, the same way on every peer", function()
    local a, b, c = { rng = 99 }, { rng = 99 }, { rng = 99 }
    market_events.mix(a, 123456.789)
    market_events.mix(b, 123456.789)
    market_events.mix(c, 654321)
    assert.are.equal(a.rng, b.rng)
    assert.are_not.equal(a.rng, c.rng)
    assert.are.equal(random.seed(a.rng), a.rng)
  end)

  it("makes a draw depend on the entropy, so the map seed alone does not give the calendar", function()
    local a, b = market_events.new_state(7, 0, 1, params), market_events.new_state(7, 0, 1, params)
    market_events.draw(a, a.next_tick, candidates(), ON, params, 1)
    market_events.draw(b, b.next_tick, candidates(), ON, params, 2)
    assert.are_not.equal(a.next_tick, b.next_tick)
  end)
end)

describe("market_events.draw", function()
  it("draws nothing before the scheduled tick", function()
    local state = market_events.new_state(1, 0, 1, params)
    local next_tick = state.next_tick
    assert.is_nil(market_events.draw(state, next_tick - 1, candidates(), ON, params, 0))
    assert.are.equal(next_tick, state.next_tick)
  end)

  it("draws an event with a bounded duration, leaving its goal and any call-off for its start", function()
    local state = market_events.new_state(7, 0, 1, params)
    local drawn, tick = draw_one(state)
    assert.is_truthy(drawn)
    assert.is_true(state.next_tick > tick)
    local duration = drawn.end_tick - drawn.start_tick
    assert.is_true(duration >= params.min_duration_ticks and duration <= params.max_duration_ticks)
    assert.are.equal(params.kinds[drawn.kind].direction, drawn.direction)
    assert.is_nil(drawn.goal)
    assert.is_nil(drawn.cancelled)
    assert.are.equal(drawn, state.by_key[drawn.keys[1]][1])
    assert.are.equal(drawn.announce_tick and tick + params.warning_ticks or tick, drawn.start_tick)
  end)

  it("draws the same events whatever tick each draw runs at", function()
    local a, b = market_events.new_state(99, 0, 1, params), market_events.new_state(99, 0, 1, params)
    for i = 1, 6 do
      local ea = market_events.draw(a, a.next_tick, candidates(), ON, params, 5)
      local eb = market_events.draw(b, b.next_tick + 777 * i, candidates(), ON, params, 5)
      assert.are.equal(ea == nil, eb == nil)
      if ea then
        assert.are.same({ ea.kind, ea.keys }, { eb.kind, eb.keys })
        assert.are.equal(ea.end_tick - ea.start_tick, eb.end_tick - eb.start_tick)
      end
      a.events, b.events = {}, {}
      market_events.reindex(a)
      market_events.reindex(b)
    end
  end)

  it("keeps the magnitude, bounded, on the event", function()
    local strong = draw_one(market_events.new_state(5, 0, 1, params), { frequency = 1, magnitude = 1000 })
    assert.are.equal(market_events.LIMITS.max_magnitude, strong.magnitude)
  end)

  it("draws nothing at frequency 0 and checks again an interval later, without reading the candidates", function()
    local state = market_events.new_state(3, 0, 0, params)
    local tick = state.next_tick
    local read = false
    local function lazy() read = true return candidates() end
    assert.is_nil(market_events.draw(state, tick, lazy, { frequency = 0, magnitude = 1 }, params, 0))
    assert.are.equal(tick + params.interval_ticks, state.next_tick)
    assert.is_false(read)
  end)

  it("does not read the candidates while max_open events are open", function()
    local state = market_events.new_state(3, 0, 1, params)
    for i = 1, params.max_open do
      state.events[i] = event("shortage", { "item/x" .. i }, 0.1, 0, 1e9)
    end
    market_events.reindex(state)
    local read = false
    local tick = state.next_tick
    assert.is_nil(market_events.draw(state, tick, function() read = true return candidates() end, ON, params, 0))
    assert.is_false(read)
  end)

  it("draws more often at a higher frequency", function()
    local state = market_events.new_state(3, 0, 4, params)
    assert.is_true(state.next_tick <= params.interval_ticks * 1.5 / 4)
  end)

  it("keeps at most max_open events open, and never draws goods that still have an event kept", function()
    local state = market_events.new_state(11, 0, 1, params)
    for _ = 1, 40 do
      local tick = state.next_tick
      local before = {}
      for key in pairs(state.by_key) do before[key] = true end
      local drawn = market_events.draw(state, tick, candidates(), { frequency = 4, magnitude = 1 }, params, 0)
      if drawn then
        for _, key in ipairs(drawn.keys) do assert.is_nil(before[key]) end
      end
      assert.is_true(market_events.open_count(state, tick) <= params.max_open)
    end
  end)

  it("gives a crisis a family of at least crisis_min_keys keys, at most crisis_max_keys", function()
    local state = market_events.new_state(1, 0, 1, params)
    local crisis
    for _ = 1, 400 do
      local drawn = market_events.draw(state, state.next_tick, candidates(), ON, params, 0)
      if drawn and drawn.kind == "crisis" then crisis = drawn break end
      state.events = {}
      market_events.reindex(state)
    end
    assert.is_truthy(crisis)
    assert.are.equal("metals", crisis.family)
    assert.is_true(#crisis.keys >= params.crisis_min_keys and #crisis.keys <= params.crisis_max_keys)
  end)

  it("draws nothing when no key is free", function()
    local state = market_events.new_state(1, 0, 1, params)
    assert.is_nil(market_events.draw(state, state.next_tick, { keys = {}, families = {} }, ON, params, 0))
    assert.are.same({}, state.events)
  end)
end)

describe("market_events.phase", function()
  it("is announced, active, then ended; a cancelled event never acts", function()
    local e = event("shortage", { "item/a" }, 1, 100, 50)
    assert.are.equal("announced", market_events.phase(e, 99))
    assert.are.equal("active", market_events.phase(e, 100))
    assert.are.equal("ended", market_events.phase(e, 150))
    e.cancelled = true
    assert.are.equal("announced", market_events.phase(e, 99))
    assert.are.equal("cancelled", market_events.phase(e, 100))
  end)
end)

describe("market_events.depths", function()
  it("is nothing before the start, moves towards the goal, then halves every half-life after the end", function()
    local e = event("shortage", { "item/a" }, 1.5, 1000, 36000)
    assert.are.equal(0, market_events.depths(e, 999, HALF_LIFE))
    assert.are.equal(0, market_events.depths(e, 1000, HALF_LIFE))
    assert.is_true(near(-0.75, market_events.depths(e, 1000 + HALF_LIFE, HALF_LIFE)))
    assert.is_true(near(-0.375, market_events.depths(e, 1000 + 2 * HALF_LIFE, HALF_LIFE)))
  end)

  it("is nothing for a cancelled event or one whose start is not decided yet", function()
    assert.are.equal(0, market_events.depths(event("shortage", { "item/a" }, 1, 0, 100, true), 50, HALF_LIFE))
    assert.are.equal(0, market_events.depths(event("shortage", { "item/a" }, nil, 0, 100), 50, HALF_LIFE))
  end)
end)

describe("market_events.evolve", function()
  local function active(seed)
    local e = event("surplus", { "item/a" }, 0.6, 0, params.max_duration_ticks)
    local state = state_of({ e })
    state.rng = random.seed(seed)
    return state, e
  end

  it("decides a forecast's call-off and every first goal at its start, from the entropy then", function()
    local function started(entropy)
      local e = event("shortage", { "item/a" }, nil, 600, 36000)
      e.announce_tick = 0
      local state = state_of({ e })
      market_events.evolve(state, 0, HALF_LIFE, params, entropy)
      assert.is_nil(e.goal)
      assert.is_nil(e.cancelled)
      market_events.evolve(state, 600, HALF_LIFE, params, entropy)
      return e
    end
    local seen, cancelled = {}, 0
    for entropy = 1, 200 do
      local e = started(entropy)
      if e.cancelled then
        cancelled = cancelled + 1
      else
        local spec = params.kinds.shortage
        assert.is_true(e.goal >= spec.start_low and e.goal <= spec.start_high)
        seen[e.goal] = true
      end
    end
    assert.is_true(cancelled > 20 and cancelled < 80)
    assert.is_true(next(seen) ~= nil)
  end)

  it("keeps the shift continuous across every pass, whatever the goal does", function()
    for seed = 1, 20 do
      local state, e = active(seed)
      for tick = PASS, e.end_tick, PASS do
        if market_events.phase(e, tick) ~= "active" then break end
        local before = market_events.depths(e, tick, HALF_LIFE)
        market_events.evolve(state, tick, HALF_LIFE, params, seed)
        assert.is_true(near(before, market_events.depths(e, tick, HALF_LIFE), 1e-12))
        assert.is_true(near(before, market_events.depths(e, tick - 1, HALF_LIFE), 1e-4))
      end
    end
  end)

  it("keeps the goal between 0 and the kind's ceiling times the magnitude, so the shift keeps its sign", function()
    local spec = params.kinds.surplus
    for seed = 1, 10 do
      local state, e = active(seed)
      e.magnitude = 2
      for tick = PASS, 400 * PASS, PASS do
        e.end_tick = tick + 1
        market_events.evolve(state, tick, HALF_LIFE, params, seed)
        assert.is_true(e.goal >= 0 and e.goal <= spec.ceiling * 2 + 1e-12)
        assert.is_true(market_events.depths(e, tick, HALF_LIFE) >= 0)
      end
    end
  end)

  it("may end an event early, continuously, and the shift then fades from where it was", function()
    local ended
    for seed = 1, 400 do
      local state, e = active(seed)
      market_events.evolve(state, PASS, HALF_LIFE, params, seed)
      if e.end_tick == PASS then ended = e break end
    end
    assert.is_truthy(ended)
    local at_end = ended.end_shift
    assert.is_true(near(at_end, market_events.depths(ended, PASS, HALF_LIFE)))
    assert.is_true(near(at_end / 2, market_events.depths(ended, PASS + HALF_LIFE, HALF_LIFE)))
    assert.are.equal("ended", market_events.phase(ended, PASS))
  end)

  it("leaves announced, ended and cancelled events alone", function()
    local waiting = event("shortage", { "item/a" }, 0.2, 10 * PASS, 36000)
    local over = event("shortage", { "item/b" }, 0.2, 0, PASS)
    local state = state_of({ waiting, over })
    local rng = state.rng
    market_events.evolve(state, 2 * PASS, HALF_LIFE, params, 77)
    assert.are.equal(rng, state.rng)
    assert.are.same({ 0.2, 0.2 }, { waiting.goal, over.goal })
  end)

  it("keeps knots of the path for the price history, read back between them", function()
    local state, e = active(3)
    local saved = params.end_chance
    params.end_chance = 0
    for tick = PASS, 3 * params.trail_ticks, PASS do market_events.evolve(state, tick, HALF_LIFE, params, 1) end
    params.end_chance = saved
    assert.are.equal(4, #e.trail)
    local knot = e.trail[3]
    assert.is_true(near(knot[2], market_events.depths(e, knot[1], HALF_LIFE)))
    local middle = market_events.depths(e, (e.trail[2][1] + knot[1]) / 2, HALF_LIFE)
    assert.is_true(near((e.trail[2][2] + knot[2]) / 2, middle))
  end)
end)

-- Trading on events with all public information, and more. Prices are those of scripts/core/market.lua
-- under a shift, for one unit (its own impact is negligible) of a good of base value 1 and default
-- depth. The force's own displacement starts at `s0` depths, halves every half-life and takes the NPC
-- drift of scripts/core/npc_market.lua each minute. Every trade is also priced on the plain market
-- (the same displacement, no event): the event version must never do better.
local MARKET = market.DEFAULTS
local NPC = require("scripts.core.npc_market").DEFAULTS
local DEPTH = market.depth(1, MARKET)

-- One event's course, sampled at every pass from its notice to 3 hours after its end: {own, shifts
-- (depths), goals (exact, the goal no player sees), start, ended, direction}.
local function course(seed, magnitude, s0)
  local state = market_events.new_state(seed * 7919, 0, 1, params)
  local e
  repeat
    e = market_events.draw(state, state.next_tick, { keys = { "item/a" }, families = {} },
      { frequency = 1, magnitude = magnitude }, params, seed * 13)
  until e
  local c = { own = {}, shifts = {}, goals = {}, direction = e.direction }
  local drift = random.seed(seed * 104729 + 7)
  local own = s0
  local tick = e.announce_tick or e.start_tick
  while not c.ended or tick <= e.end_tick + 3 * 216000 do
    if market_events.phase(e, tick) == "active" then
      market_events.evolve(state, tick, HALF_LIFE, params, seed * 31 + tick)
    end
    local i = #c.shifts + 1
    c.own[i], c.shifts[i] = own, market_events.depths(e, tick, HALF_LIFE)
    c.goals[i] = e.goal and e.direction * e.goal or 0
    if not c.start and tick >= e.start_tick then c.start = i end
    if not c.ended and market_events.phase(e, tick) ~= "active" and tick >= e.start_tick then c.ended = i end
    tick = tick + PASS
    own = market.decay(own, PASS, MARKET)
    if tick % NPC.step_ticks == 0 then
      local roll
      drift, roll = random.next(drift)
      own = own + (2 * roll - 1) * NPC.volatility
    end
  end
  return c
end

-- Price of buying (`side` "buy") or selling one unit at sample `i`, with the event or without it.
local function price(c, i, side, plain)
  local own, shift = c.own[i] * DEPTH, plain and 0 or c.shifts[i] * DEPTH
  if side == "buy" then return market.shifted_buy_price(1, own, shift, MARKET) end
  return market.shifted_sell_price(1, own, shift, MARKET)
end

-- Return of a round trip in at sample `i` and out at `j`: long buys then sells, short the reverse.
local function round_trip(c, i, j, is_long, plain)
  if is_long then return price(c, j, "sell", plain) / price(c, i, "buy", plain) - 1 end
  return price(c, i, "sell", plain) / price(c, j, "buy", plain) - 1
end

-- Each strategy gives {in, out, long} for one course, or nil when it does not trade. The favourable
-- side is to buy into a shortage or crisis and to sell into a surplus.
local function favourable(c) return c.direction < 0 end
local STRATEGIES = {
  ["naive: in at the notice, out at the end"] = function(c) return { 1, c.ended, favourable(c) } end,
  ["naive, other side"] = function(c) return { 1, c.ended, not favourable(c) } end,
  ["gap: in when the exact goal is 0.2 depths ahead, out when it is not"] = function(c)
    for i = c.start, c.ended do
      if math.abs(c.goals[i]) - math.abs(c.shifts[i]) >= 0.2 then
        for j = i + 1, c.ended do
          if math.abs(c.goals[j]) <= math.abs(c.shifts[j]) or j == c.ended then return { i, j, favourable(c) } end
        end
      end
    end
  end,
  ["fade: take the reversion at the end, out 3 h later"] = function(c)
    return { c.ended, #c.shifts, not favourable(c) }
  end,
  ["peak: in at the start, out at the best price (hindsight)"] = function(c)
    local best, best_j
    for j = c.start, #c.shifts do
      local r = round_trip(c, c.start, j, favourable(c))
      if not best or r > best then best, best_j = r, j end
    end
    return { c.start, best_j, favourable(c) }
  end,
  ["own reversion: in at the notice on the side it favours, out 3 h after the end"] = function(c)
    if c.own[1] == 0 then return nil end
    return { 1, #c.shifts, c.own[1] > 0 }
  end,
}

-- The best round trip in hindsight over the whole course, either side, with the event or without:
-- one pass per side, the best exit so far against the best entry before it.
local function clairvoyant(c, plain)
  local best, cheapest, dearest = -math.huge, nil, nil
  for i = 1, #c.shifts do
    local buy, sell = price(c, i, "buy", plain), price(c, i, "sell", plain)
    cheapest, dearest = math.min(cheapest or buy, buy), math.max(dearest or sell, sell)
    best = math.max(best, sell / cheapest - 1, dearest / buy - 1)
  end
  return best
end

--- Runs `count` courses at `magnitude` from own displacement `s0`: per strategy {event, plain, trades}
--- averages, and the clairvoyant bests with and without the event. Asserts that at every sample the
--- event's buy price is no lower and its sell price no higher than the plain market's.
local function simulate(magnitude, s0, count)
  local results, best, best_plain = {}, -math.huge, -math.huge
  for seed = 1, count do
    local c = course(seed, magnitude, s0)
    for i = 1, #c.shifts do
      assert.is_true(price(c, i, "buy") >= price(c, i, "buy", true) * (1 - 1e-12))
      assert.is_true(price(c, i, "sell") <= price(c, i, "sell", true) * (1 + 1e-12))
    end
    best, best_plain = math.max(best, clairvoyant(c)), math.max(best_plain, clairvoyant(c, true))
    for name, strategy in pairs(STRATEGIES) do
      local trade = strategy(c)
      if trade then
        local r = results[name] or { event = 0, plain = 0, trades = 0 }
        results[name] = r
        r.event = r.event + round_trip(c, trade[1], trade[2], trade[3])
        r.plain = r.plain + round_trip(c, trade[1], trade[2], trade[3], true)
        r.trades = r.trades + 1
      end
    end
  end
  for _, r in pairs(results) do r.event, r.plain = r.event / r.trades, r.plain / r.trades end
  return results, best, best_plain
end

describe("trading on market events", function()
  -- 12 courses per case here; docs/market.md gives the averages over 300.
  for _, magnitude in ipairs({ market_events.LIMITS.min_magnitude, 1, market_events.LIMITS.max_magnitude }) do
    for _, s0 in ipairs({ 0, 0.05, -0.05, 0.1, -0.1, 0.2, -0.2 }) do
      it("never does better than the plain market, at magnitude " .. magnitude .. " from " .. s0 .. " depths",
        function()
          local results, best, best_plain = simulate(magnitude, s0, 12)
          assert.is_true(best <= best_plain + 1e-12)
          for name, r in pairs(results) do
            assert.is_true(r.event <= r.plain + 1e-12, name)
            -- Without a displacement of its own to revert, no strategy gains from an event.
            if s0 == 0 then assert.is_true(r.event <= 0.01, name .. ": " .. r.event) end
          end
        end)
    end
  end
end)


describe("market_events.key_depths and events_of", function()
  it("sums the events of a key, any quality of an item included, and lists them oldest first", function()
    local first = event("shortage", { "item/a" }, 1, 0, 100)
    local second = event("crisis", { "item/a", "item/b" }, 0.5, 0, 100)
    second.id = 2
    local state = state_of({ first, second })
    local expected = market_events.depths(first, 100, HALF_LIFE) + market_events.depths(second, 100, HALF_LIFE)
    assert.is_true(near(expected, market_events.key_depths(state, "item/a", 100, HALF_LIFE)))
    assert.is_true(near(expected, market_events.key_depths(state, "item/a@rare", 100, HALF_LIFE)))
    assert.are.equal(0, market_events.key_depths(state, "item/c", 100, HALF_LIFE))
    assert.are.equal(0, market_events.key_depths(nil, "item/a", 100, HALF_LIFE))
    assert.are.same({ first, second }, market_events.events_of(state, "item/a@epic"))
    assert.are.same({}, market_events.events_of(state, "item/z"))
  end)
end)

describe("market_events.notices", function()
  it("tells each phase once, in order", function()
    local e = event("shortage", { "item/a" }, 1, 100, 50)
    local state = state_of({ e })
    assert.are.equal("announced", market_events.notices(state, 0)[1].notice)
    assert.are.same({}, market_events.notices(state, 50))
    assert.are.equal("started", market_events.notices(state, 100)[1].notice)
    assert.are.equal("ended", market_events.notices(state, 160)[1].notice)
    assert.are.same({}, market_events.notices(state, 170))
  end)

  it("tells an unannounced event when it starts and a cancelled one when it would have", function()
    local sudden = event("surplus", { "item/a" }, 1, 0, 150)
    local called_off = event("shortage", { "item/b" }, 1, 100, 50, true)
    called_off.id = 2
    local state = state_of({ sudden, called_off })
    local first = market_events.notices(state, 0)
    assert.are.equal("started", first[1].notice)
    assert.are.equal("announced", first[2].notice)
    assert.are.equal("cancelled", market_events.notices(state, 100)[1].notice)
    assert.are.same({ { event = sudden, notice = "ended" } }, market_events.notices(state, 200))
  end)
end)

describe("market_events.prune", function()
  it("drops cancelled events once due and ended ones once their shift is negligible, and reindexes", function()
    local done = event("shortage", { "item/a" }, 1, 0, 100)
    local cancelled = event("shortage", { "item/b" }, 1, 0, 100, true)
    local state = state_of({ done, cancelled })
    market_events.prune(state, 0, HALF_LIFE, params)
    assert.are.equal(1, #state.events)
    assert.is_nil(state.by_key["item/b"])
    local last = 100 + params.retention_half_lives * HALF_LIFE
    market_events.prune(state, last - 1, HALF_LIFE, params)
    assert.are.equal(1, #state.events)
    market_events.prune(state, last, HALF_LIFE, params)
    assert.are.equal(0, #state.events)
    assert.are.same({}, state.by_key)
  end)
end)

describe("market_events.retain_keys and drop_invalid", function()
  it("drops keys that lost their value, and events left without any", function()
    local both = event("crisis", { "item/a", "item/gone" }, 1, 0, 100)
    local gone = event("shortage", { "item/gone" }, 1, 0, 100)
    gone.id = 2
    local state = state_of({ both, gone })
    market_events.retain_keys(state, { ["item/a"] = 1 })
    assert.are.equal(1, #state.events)
    assert.are.same({ "item/a" }, both.keys)
    assert.is_nil(state.by_key["item/gone"])
  end)

  it("drops events of another shape and indexes the rest", function()
    local good = event("shortage", { "item/a" }, 1, 0, 100)
    local crossed = event("surplus", { "item/c" }, -0.2, 0, 100)
    local state = { rng = 1, events = { { id = 9, keys = { "item/b" }, depths = -1, start_tick = 0, end_tick = 9 },
      good, crossed } }
    assert.are.equal(2, market_events.drop_invalid(state))
    assert.are.same({ good }, state.events)
    assert.are.same({ good }, state.by_key["item/a"])
  end)
end)

describe("market_events.effect_range", function()
  it("gives the mid price factor range of a kind at a magnitude, from none to its ceiling", function()
    local low, high = market_events.effect_range("shortage", 1, params)
    assert.are.equal(1, low)
    assert.is_true(near(math.exp(params.kinds.shortage.ceiling), high))
    local s_low, s_high = market_events.effect_range("surplus", 2, params)
    assert.is_true(near(math.exp(-2 * params.kinds.surplus.ceiling), s_low))
    assert.are.equal(1, s_high)
  end)
end)

describe("market_events salts", function()
  it("draws one salt per minute, from the entropy, for the steps of the next minute", function()
    local a, b = { rng = 5, events = {} }, { rng = 5, events = {} }
    market_events.draw_salt(a, 3600 * 10, 111)
    market_events.draw_salt(b, 3600 * 10, 222)
    assert.are_not.equal(market_events.salt_at(a, 3600 * 11 + 5), market_events.salt_at(b, 3600 * 11 + 5))
    local first = market_events.salt_at(a, 3600 * 11)
    assert.is_true(first >= 0 and first < 1)
    -- Later passes in the same minute keep it.
    market_events.draw_salt(a, 3600 * 10 + 600, 999)
    assert.are.equal(first, market_events.salt_at(a, 3600 * 11 + 3599))
    assert.is_nil(market_events.salt_at(a, 3600 * 10))
    assert.is_nil(market_events.salt_at(nil, 3600 * 11))
  end)

  it("forgets a minute's salt after the slots go round", function()
    local state = { rng = 5, events = {} }
    for minute = 0, 40 do market_events.draw_salt(state, minute * 3600, minute) end
    assert.is_nil(market_events.salt_at(state, 3 * 3600))
    assert.is_truthy(market_events.salt_at(state, 40 * 3600))
  end)
end)

describe("market_events.LIMITS", function()
  it("bounds the settings", function()
    local limits = market_events.LIMITS
    assert.is_true(limits.min_frequency == 0 and limits.max_frequency > 1)
    assert.is_true(limits.min_magnitude > 0 and limits.max_magnitude > 1)
  end)
end)
