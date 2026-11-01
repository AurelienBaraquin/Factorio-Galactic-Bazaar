-- In-game tests of market events (scripts/market_events.lua, scripts/core/market_events.lua, #120,
-- ADR-0025): an event's shift moves every force's quotes, trades, liquidity and history through the
-- displacement, quality and fluid markets included, adds up with another event of the same goods,
-- survives a rebase of base values, and a trade at the bound keeps the force's own displacement; the
-- pass draws an event when due and moves it, never with electricity, not at frequency 0, and tells only
-- the forces that researched the Galactic Bazaar; a settings change leaves a drawn event as it is; the
-- state is created lazily, drops goods that lost their value, and survives a reload; the item detail
-- and the Events tab show events without their exact course; and the cost of the pass and of reads.
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local core = require("scripts.core.market_events")
local market = require("scripts.market")
local market_events = require("scripts.market_events")
local market_model = require("scripts.core.market")
local pricing = require("scripts.pricing")

local GEAR, PLATE, OIL = "iron-gear-wheel", "iron-plate", "crude-oil"
local GEAR_KEY, PLATE_KEY, OIL_KEY = "item/" .. GEAR, "item/" .. PLATE, "fluid/" .. OIL
local PARAMS = market_events.PARAMS
local MARKET = market_model.DEFAULTS
local FAR = 1e9

local player

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local function bazaar_research() return force().technologies[bazaar_gui.TECHNOLOGY] end

local function near(expected, actual, tolerance)
  return math.abs(expected - actual) <= (tolerance or 1e-9) * math.max(1, math.abs(expected))
end

-- Adds an event of `kind` on `keys` moving towards `goal` (in its own direction), started `age` ticks
-- ago, lasting at most `duration` ticks (announced, starting in -age ticks, when age is negative);
-- returns it.
local function add_event(kind, keys, goal, age, duration)
  local events = storage.market_events
  local start = game.tick - age
  local event = { id = events.next_id, kind = kind, keys = keys, direction = PARAMS.kinds[kind].direction,
    magnitude = 1, goal = goal, segment_tick = start, segment_shift = 0, trail = { { start, 0 } },
    start_tick = start, end_tick = start + duration, announce_tick = age < 0 and game.tick or nil,
    told = age < 0 and "announced" or "active" }
  events.next_id = events.next_id + 1
  table.insert(events.events, event)
  core.reindex(events)
  return event
end

local function reset_markets()
  for _, force_state in pairs(storage.forces) do
    force_state.feed = {}
    for _, key in ipairs({ GEAR_KEY, PLATE_KEY, OIL_KEY }) do force_state.markets[key] = nil end
    for key in pairs(force_state.markets) do
      if key:find(GEAR_KEY .. "@", 1, true) == 1 then force_state.markets[key] = nil end
    end
  end
end

-- The custom alerts of `target` (a player) whose message starts with "gb-notify.market-event".
local function event_alerts(target)
  local found = {}
  for _, by_type in pairs(target.get_alerts({ type = defines.alert_type.custom })) do
    for _, list in pairs(by_type) do
      for _, alert in ipairs(list) do
        local message = alert.message and alert.message[1]
        if type(message) == "string" and message:find("gb-notify.market-event", 1, true) == 1 then
          found[#found + 1] = alert
        end
      end
    end
  end
  return found
end

local function set_setting(name, value) settings.global[name] = { value = value } end -- luacheck: ignore 122

-- The mid price of `key` without market events: from the entry's own displacement.
local function plain_mid(force_index, kind, name)
  local value = pricing.base_value(kind, name)
  local own = storage.forces[force_index].markets[kind .. "/" .. name].displacement
  return market_model.mid_price(value, own, MARKET)
end

describe("market events", function()
  local hub
  before_each(function()
    player = game.get_player(1)
    -- In storage, so that the reload test can restore them.
    storage.gb_test_market_events = {
      saved = storage.market_events, balance = state().balance, researched = bazaar_research().researched,
      frequency = settings.global[market_events.FREQUENCY_SETTING].value,
      magnitude = settings.global[market_events.MAGNITUDE_SETTING].value,
    }
    storage.market_events = core.new_state(1, game.tick, 1, PARAMS)
    storage.market_events.next_tick = game.tick + FAR
    bazaar_research().researched = true -- luacheck: ignore 122
    test_helpers.set_balance(state(), 1e7)
    reset_markets()
    player.remove_alert({ type = defines.alert_type.custom })
    hub = player.surface.create_entity({ name = "gb-hub", position = { player.position.x + 3, player.position.y },
      force = "player", raise_built = true })
    hub.energy = hub.electric_buffer_size
    storage.gb_test_market_events.hub = hub
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    bazaar_gui.close(player.index)
    local saved = storage.gb_test_market_events
    if saved then
      if saved.hub and saved.hub.valid then saved.hub.destroy() end
      storage.market_events = saved.saved
      test_helpers.set_balance(state(), saved.balance)
      bazaar_research().researched = saved.researched -- luacheck: ignore 122
      set_setting(market_events.FREQUENCY_SETTING, saved.frequency)
      set_setting(market_events.MAGNITUDE_SETTING, saved.magnitude)
    end
    storage.gb_test_market_events = nil
    reset_markets()
    player.remove_alert({ type = defines.alert_type.custom })
  end)

  test("a shortage raises every force's prices of its goods through the displacement, and cuts supply", function()
    local supply = market.buyable(force().index, "item", GEAR)
    local before = market.quote(force().index, "item", GEAR)
    local event = add_event("shortage", { GEAR_KEY }, 1, 7200, 36000)
    local quote = market.quote(force().index, "item", GEAR)
    local value = pricing.base_value("item", GEAR)
    local shift = core.depths(event, game.tick, market_events.HALF_LIFE_TICKS) * market_model.depth(value, MARKET)
    assert.is_true(shift < 0)
    assert.is_true(near(market_model.mid_price(value, state().markets[GEAR_KEY].displacement + shift, MARKET),
      quote.mid))
    assert.is_true(quote.buy > before.buy)
    -- Sellers keep the plain sell price: an event never makes a price better.
    local own = state().markets[GEAR_KEY].displacement
    assert.is_true(near(market_model.sell_price(value, own, MARKET), quote.sell))
    assert.is_true(near(market_model.buy_price(value, own + shift, MARKET), quote.buy))
    assert.is_true(near(supply + shift, market.buyable(force().index, "item", GEAR), 1e-6))
    local plate = market.quote(force().index, "item", PLATE)
    assert.is_true(near(plain_mid(force().index, "item", PLATE), plate.mid))
    local enemy = game.forces.enemy.index
    local enemy_quote = market.quote(enemy, "item", GEAR)
    assert.is_true(near(market_model.mid_price(value, storage.forces[enemy].markets[GEAR_KEY].displacement + shift,
      MARKET), enemy_quote.mid))
  end)

  test("a trade during an event moves only the entry's own displacement", function()
    add_event("surplus", { GEAR_KEY }, 1, 7200, 36000)
    market.quote(force().index, "item", GEAR)
    local own = state().markets[GEAR_KEY].displacement
    local preview = market.preview(force().index, "item", GEAR, "buy", 10)
    local ok, cost = market.buy(force().index, "item", GEAR, 10)
    assert.is_true(ok)
    assert.is_true(near(preview, cost))
    assert.is_true(near(own - 10, state().markets[GEAR_KEY].displacement))
  end)

  test("a round trip through an event loses: bought before a shortage, sold at its height", function()
    local ok, cost = market.buy(force().index, "item", GEAR, 100)
    assert.is_true(ok)
    add_event("shortage", { GEAR_KEY }, 1.5, 4 * 36000, 10 * 36000)
    assert.is_true(market_events.depths(GEAR_KEY, game.tick) < -1)
    local sold, revenue = market.sell(force().index, "item", GEAR, 100)
    assert.is_true(sold)
    assert.is_true(revenue <= cost * (1 + 1e-9))
  end)

  test("a trade at the bound during an event keeps the force's own displacement", function()
    local value = pricing.base_value("item", GEAR)
    local depth = market_model.depth(value, MARKET)
    local bound = MARKET.max_depths * depth
    market.quote(force().index, "item", GEAR)
    -- The force's own surplus near the bound, and a surplus event pushing past it.
    state().markets[GEAR_KEY].displacement = bound - depth
    local event = add_event("surplus", { GEAR_KEY }, 5, 4 * 36000, 10 * 36000)
    assert.is_true(core.depths(event, game.tick, market_events.HALF_LIFE_TICKS) > 1)
    local ok = market.buy(force().index, "item", GEAR, 10)
    assert.is_true(ok)
    assert.is_true(near(bound - depth - 10, state().markets[GEAR_KEY].displacement))
  end)

  test("an event reaches every quality of its item, and fluids", function()
    if storage.quality_levels and storage.quality_levels.rare then
      local plain = market.quote(force().index, "item", GEAR, "rare")
      state().markets[GEAR_KEY .. "@rare"] = nil
      add_event("shortage", { GEAR_KEY }, 1, 7200, 36000)
      assert.is_true(market.quote(force().index, "item", GEAR, "rare").mid > plain.mid * 1.01)
    end
    if pricing.base_value("fluid", OIL) then
      add_event("surplus", { OIL_KEY }, 1, 7200, 36000)
      local quote = market.quote(force().index, "fluid", OIL)
      assert.is_true(quote.mid < plain_mid(force().index, "fluid", OIL) * 0.99)
    end
  end)

  test("a fading event and a new one on the same goods add up", function()
    local fading = add_event("shortage", { GEAR_KEY }, 1, 36000, 18000)
    local fresh = add_event("surplus", { GEAR_KEY }, 0.5, 7200, 36000)
    local tick = game.tick
    local half_life = market_events.HALF_LIFE_TICKS
    assert.are.equal("ended", core.phase(fading, tick))
    local total = core.depths(fading, tick, half_life) + core.depths(fresh, tick, half_life)
    assert.is_true(near(total, market_events.depths(GEAR_KEY, tick)))
    local quote = market.quote(force().index, "item", GEAR)
    assert.is_true(near(plain_mid(force().index, "item", GEAR) * math.exp(-total), quote.mid))
  end)

  test("a rebase of base values keeps the event's shift on top of the rebased displacement", function()
    market.quote(force().index, "item", GEAR)
    state().markets[GEAR_KEY].displacement = 100
    add_event("shortage", { GEAR_KEY }, 1, 7200, 36000)
    local value = pricing.base_value("item", GEAR)
    local old_values = {}
    for key, old in pairs(storage.base_values) do old_values[key] = old end
    old_values[GEAR_KEY] = value / 2
    market.rebase_all(old_values, storage.quality_levels)
    local own = state().markets[GEAR_KEY].displacement
    assert.is_true(near(50, own, 1e-6))
    local shift = market_events.depths(GEAR_KEY, game.tick)
    assert.is_true(shift < 0)
    assert.is_true(near(market_model.mid_price(value, own, MARKET) * math.exp(-shift),
      market.quote(force().index, "item", GEAR).mid))
  end)

  test("the price history includes the event's shift", function()
    add_event("shortage", { GEAR_KEY }, 2, 4 * 3600, 36000)
    local entry = { displacement = 0, tick = game.tick - 3 * 3600, rng = 1, history = {} }
    state().markets[GEAR_KEY] = entry
    market.quote(force().index, "item", GEAR)
    assert.are.equal(3, #entry.history)
    assert.is_true(entry.history[3] > pricing.base_value("item", GEAR) * 1.05)
  end)

  test("the pass draws an event when due, moves it, and tells the forces that researched the bazaar", function()
    local events = storage.market_events
    events.next_tick = game.tick
    market_events.on_pass_tick({ tick = game.tick })
    assert.are.equal(1, #events.events)
    local drawn = events.events[1]
    for _, key in ipairs(drawn.keys) do
      assert.is_truthy(storage.base_values[key], key)
      assert.is_nil(key:find("^energy/"), key)
    end
    assert.is_true(events.next_tick > game.tick)
    assert.are.equal(1, #event_alerts(player))
    assert.are.equal(drawn.announce_tick and "announced" or "active", drawn.told)
    -- Once active, a later pass moves its course.
    -- Its start: an unannounced event gets its first goal at the pass it starts.
    drawn.start_tick, drawn.segment_tick, drawn.trail = game.tick - 600, game.tick - 600, { { game.tick - 600, 0 } }
    drawn.end_tick, drawn.announce_tick, drawn.goal = game.tick + 36000, nil, nil
    market_events.on_pass_tick({ tick = game.tick })
    assert.is_true(drawn.goal > 0)
    assert.are.equal(game.tick, drawn.segment_tick)
    -- Many draws never touch electricity.
    for _ = 1, 30 do
      events.events, events.next_tick = {}, game.tick
      core.reindex(events)
      market_events.on_pass_tick({ tick = game.tick })
      for _, event in ipairs(events.events) do
        for _, key in ipairs(event.keys) do assert.is_nil(key:find("^energy/"), key) end
      end
    end
  end)

  test("tells nothing to a force that has not researched the Galactic Bazaar", function()
    bazaar_research().researched = false -- luacheck: ignore 122
    add_event("shortage", { GEAR_KEY }, 1, 0, 36000).told = nil
    market_events.on_pass_tick({ tick = game.tick })
    assert.are.equal(0, #event_alerts(player))
    bazaar_research().researched = true -- luacheck: ignore 122
    add_event("surplus", { PLATE_KEY }, 1, 0, 36000).told = nil
    market_events.on_pass_tick({ tick = game.tick })
    assert.are.equal(1, #event_alerts(player))
  end)

  test("salts the NPC drift with a figure drawn each minute", function()
    market_events.on_pass_tick({ tick = game.tick })
    local minute = math.floor(game.tick / 3600)
    local salt = core.salt_at(storage.market_events, (minute + 1) * 3600)
    assert.is_true(salt ~= nil and salt >= 0 and salt < 1)
    assert.are.equal(salt, market_events.salt_at((minute + 1) * 3600 + 100))
  end)

  test("draws nothing at frequency 0", function()
    set_setting(market_events.FREQUENCY_SETTING, 0)
    storage.market_events.next_tick = game.tick
    market_events.on_pass_tick({ tick = game.tick })
    assert.are.same({}, storage.market_events.events)
    assert.are.equal(game.tick + PARAMS.interval_ticks, storage.market_events.next_tick)
  end)

  test("a settings change leaves a drawn event and the scheduled draw as they are", function()
    local events = storage.market_events
    events.next_tick = game.tick
    market_events.on_pass_tick({ tick = game.tick })
    local drawn = events.events[1]
    local scheduled, magnitude, low, high = events.next_tick, drawn.magnitude, drawn.start_tick, drawn.end_tick
    set_setting(market_events.MAGNITUDE_SETTING, 3)
    set_setting(market_events.FREQUENCY_SETTING, 4)
    market_events.on_pass_tick({ tick = game.tick })
    assert.are.same({ scheduled, magnitude, low, high }, { events.next_tick, drawn.magnitude, drawn.start_tick,
      drawn.end_tick })
  end)

  test("creates its state when a save lacks it, and its candidates once", function()
    storage.market_events = nil
    market_events.on_pass_tick({ tick = game.tick })
    local first = storage.market_events
    assert.is_truthy(first)
    local expected = core.new_state(game.default_map_gen_settings.seed * 31 + 17, 0, 1, PARAMS)
    assert.are.equal(expected.next_tick, first.next_tick - game.tick)
    first.next_tick = game.tick
    market_events.on_pass_tick({ tick = game.tick })
    assert.is_truthy(first.candidates)
    assert.is_true(#first.candidates.keys > 100)
    assert.is_true(market.quote(force().index, "item", GEAR) ~= nil)
  end)

  test("drops goods that lost their value on configuration change", function()
    add_event("crisis", { GEAR_KEY, "item/gb-no-such-item" }, 0.5, 0, 36000)
    add_event("shortage", { "item/gb-no-such-item" }, 0.5, 0, 36000)
    market_events.init()
    assert.are.equal(1, #storage.market_events.events)
    assert.are.same({ GEAR_KEY }, storage.market_events.events[1].keys)
    assert.is_nil(storage.market_events.by_key["item/gb-no-such-item"])
  end)

  test("the item detail shows what events add to the price, without their course", function()
    bazaar_gui.open(player, "market", hub)
    local view = bazaar_gui.view(player.index, "market")
    view.selected = GEAR_KEY
    bazaar_gui.refresh(player)
    local cell = view.elements.info.figures.event
    assert.are.equal("gb-detail.event-none", cell.caption[1])
    assert.are.equal("gb-detail.figure-event-rule", cell.tooltip[1])
    add_event("shortage", { GEAR_KEY }, 1, 7200, 36000)
    add_event("surplus", { GEAR_KEY }, 0.1, 600, 36000)
    bazaar_gui.refresh(player)
    assert.are.equal("gb-detail.event-value", cell.caption[1])
    local effect = (math.exp(-market_events.depths(GEAR_KEY, game.tick)) - 1) * 100
    assert.are.equal(string.format("%+.0f", effect), cell.caption[2])
    assert.are.same({ "gb-events.kind-shortage" }, cell.caption[3])
    -- Captions keep their numbers as text.
    assert.are.same({ "gb-events.phase-active", "8" }, cell.caption[4])
    assert.are.same({ "gb-detail.event-others", "1" }, cell.caption[5])
  end)

  test("the Events tab lists events with their status and possible effect, every cell explained", function()
    bazaar_gui.open(player, "overview")
    test_helpers.select_tab(player, "events")
    local view = bazaar_gui.view(player.index, "events")
    assert.is_true(view.elements.empty.visible)
    assert.is_false(view.elements.rows[1].kind.visible)
    add_event("surplus", { PLATE_KEY }, 0.5, 7200, 3600)
    add_event("shortage", { GEAR_KEY }, 1, -600, 36000)
    bazaar_gui.refresh(player)
    local rows = view.elements.rows
    assert.is_false(view.elements.empty.visible)
    -- The forecast first, then the one over and fading.
    assert.are.same({ "gb-events.kind-shortage" }, rows[1].kind.caption)
    -- What to do comes first.
    assert.are.same({ "gb-events.advice-shortage" }, rows[1].kind.tooltip[2])
    assert.are.equal("gb-events.phase-announced", rows[1].status.caption[1])
    assert.are.equal("gb-events.effect-range", rows[1].range.caption[1])
    assert.are.equal("gb-events.phase-ended", rows[2].status.caption[1])
    assert.are.equal("gb-events.effect-range", rows[2].range.caption[1])
    assert.is_true(tonumber(rows[2].now.caption[2]) < 0)
    for _, row in ipairs({ rows[1], rows[2] }) do
      for column, cell in pairs(row) do assert.is_truthy(cell.tooltip and cell.tooltip[1], column) end
    end
    assert.are.equal("gb-events.summary", view.elements.summary.caption[1])
    assert.are.equal("gb-events.summary-tooltip", view.elements.summary.tooltip[1])
  end)

  test("keeps the events and their effect through a reload", function()
    add_event("shortage", { GEAR_KEY }, 1, 7200, 36000)
    market.quote(force().index, "item", GEAR)
  end).after_reload_mods(function()
    local reloaded = game.forces.player.index
    local quote = market.quote(reloaded, "item", GEAR)
    assert.are.equal(1, #storage.market_events.events)
    assert.are.equal(storage.market_events.events[1], storage.market_events.by_key[GEAR_KEY][1])
    assert.is_true(market_events.depths(GEAR_KEY, game.tick) < 0)
    assert.is_true(quote.mid > plain_mid(reloaded, "item", GEAR))
  end)

  test("measures the pass and market reads with events", function()
    local events = storage.market_events
    local runs = 10
    -- A draw with the candidates cached.
    market_events.on_values_rebuilt()
    local draw = helpers.create_profiler()
    for _ = 1, runs do
      events.events, events.next_tick = {}, game.tick
      market_events.on_pass_tick({ tick = game.tick })
    end
    draw.stop()
    draw.divide(runs)
    -- A due draw blocked by max_open, and one with events off: nothing is read.
    events.events = {}
    for i = 1, PARAMS.max_open do add_event("shortage", { "item/gb-test-" .. i }, 0.1, 0, FAR) end
    local blocked = helpers.create_profiler()
    for _ = 1, runs do
      events.next_tick = game.tick
      market_events.on_pass_tick({ tick = game.tick })
    end
    blocked.stop()
    blocked.divide(runs)
    set_setting(market_events.FREQUENCY_SETTING, 0)
    events.events = {}
    core.reindex(events)
    local off = helpers.create_profiler()
    for _ = 1, runs do
      events.next_tick = game.tick
      market_events.on_pass_tick({ tick = game.tick })
    end
    off.stop()
    off.divide(runs)
    -- A price snapshot: 40 quotes, without events, then with 20 events on other goods.
    local names = {}
    for i = 1, 40 do names[i] = storage.tradeable_items[i] end
    local function snapshot()
      local profiler = helpers.create_profiler()
      for _ = 1, runs do
        for _, name in ipairs(names) do market.quote(force().index, "item", name) end
      end
      profiler.stop()
      profiler.divide(runs)
      return profiler
    end
    local bare = snapshot()
    for i = 1, 20 do add_event("crisis", { "item/gb-test-" .. i }, 0.3, 3600, 36000) end
    local busy = snapshot()
    -- 40 full catch-ups (30 NPC steps each), with the salts of every minute and without any.
    local function catch_ups(salted)
      local saved_salts = events.salts
      if salted then
        for minute = math.floor(game.tick / 3600) - 32, math.floor(game.tick / 3600) do
          core.draw_salt(events, minute * 3600, minute)
        end
      else
        events.salts = nil
      end
      local profiler = helpers.create_profiler(true)
      for _ = 1, runs do
        for _, name in ipairs(names) do
          state().markets["item/" .. name] = { displacement = 0, tick = game.tick - 30 * 3600, rng = 7, history = {} }
        end
        profiler.restart()
        for _, name in ipairs(names) do market.quote(force().index, "item", name) end
        profiler.stop()
      end
      profiler.divide(runs)
      events.salts = saved_salts
      for _, name in ipairs(names) do state().markets["item/" .. name] = nil end
      return profiler
    end
    local unsalted, salted = catch_ups(false), catch_ups(true)
    log({ "", "[galactic-bazaar] 40 catch-ups of 30 NPC steps, unsalted: ", unsalted })
    log({ "", "[galactic-bazaar] 40 catch-ups of 30 NPC steps, salted: ", salted })
    log({ "", "[galactic-bazaar] market events pass with a draw (average of ", runs, "): ", draw })
    log({ "", "[galactic-bazaar] market events pass, draw blocked by max_open: ", blocked })
    log({ "", "[galactic-bazaar] market events pass, frequency 0: ", off })
    log({ "", "[galactic-bazaar] 40 quotes without events: ", bare })
    log({ "", "[galactic-bazaar] 40 quotes with 20 events on other goods: ", busy })
  end)
end)
