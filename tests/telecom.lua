-- In-game tests of telecommunications (scripts/telecom.lua, ADR-0012): freshness of the prices a
-- force sees, and history and trends at level 2.
local market = require("scripts.market")
local market_gui = require("scripts.market_gui")
local telecom = require("scripts.telecom")
local core = require("scripts.core.telecom")
local price_signals = require("scripts.price_signals")
local value_overrides = require("scripts.value_overrides")

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local GEAR = "iron-gear-wheel"

local function research(level)
  for index, name in ipairs(telecom.TECHNOLOGIES) do
    force().technologies[name].researched = index <= level -- luacheck: ignore 122
  end
end

local created

describe("telecommunications", function()
  before_each(function()
    created = {}
    state().feed = {}
    state().markets["item/" .. GEAR] = nil
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    research(0)
    state().feed = {}
    state().markets["item/" .. GEAR] = nil
  end)

  test("set how old the prices a force sees may be, by research level", function()
    for level = 0, 2 do
      research(level)
      assert.are.equal(level, telecom.level(force()))
      assert.are.equal(core.period(level), telecom.period(force()))
    end
    research(1)
    assert.is_false(telecom.shows_history(force()))
    research(2)
    assert.is_true(telecom.shows_history(force()))
  end)

  test("show the price seen at the start of the period, while trades use the live price", function()
    local seen = telecom.quote(force().index, "item", GEAR).sell
    market.sell(force().index, "item", GEAR, 20000)
    assert.are.equal(seen, telecom.quote(force().index, "item", GEAR).sell)
    assert.is_true(market.quote(force().index, "item", GEAR).sell < seen)
    state().feed["item/" .. GEAR].tick = game.tick - telecom.period(force())
    assert.is_true(telecom.quote(force().index, "item", GEAR).sell < seen)
  end)

  test("unlock the trend column and the history line at level 2", function()
    local player = game.get_player(1)
    local hub = player.surface.create_entity({ name = "gb-hub", position = { player.position.x + 3, player.position.y },
      force = "player", raise_built = true })
    created = { hub }
    hub.energy = hub.electric_buffer_size
    market_gui.open(player, hub)
    local data = storage.players[player.index]
    data.selected = GEAR
    market.quote(force().index, "item", GEAR)
    state().markets["item/" .. GEAR].history = { 1, 2, 3 }
    local refresh = { tick = (player.index % market_gui.SLOTS) * market_gui.SLOT_TICKS }
    market_gui.on_refresh_tick(refresh)
    local header, history = data.elements.trend_header, data.elements.history
    local visible = { header.caption, history.visible }
    research(2)
    state().feed = {}
    market_gui.on_refresh_tick(refresh)
    local unlocked = { type(header.caption), history.visible }
    market_gui.close(player.index)
    assert.are.same({ "", false }, visible)
    assert.are.same({ "table", true }, unlocked)
  end)

  test("keep the market window's columns in place below level 2", function()
    local player = game.get_player(1)
    local hub = player.surface.create_entity({ name = "gb-hub", position = { player.position.x + 3, player.position.y },
      force = "player", raise_built = true })
    hub.energy = hub.electric_buffer_size
    market_gui.open(player, hub)
    local data = storage.players[player.index]
    for _, row in ipairs(data.elements.rows) do
      if row.name.visible then
        assert.is_true(row.trend.visible)
        assert.are.equal("", row.trend.caption)
      end
    end
    assert.is_true(data.elements.trend_header.visible)
    market_gui.close(player.index)
    hub.destroy()
  end)

  test("forget the prices seen when base values are rebuilt", function()
    telecom.quote(force().index, "item", GEAR)
    assert.is_truthy(state().feed)
    value_overrides.rebuild()
    assert.is_nil(state().feed)
  end)

  test("take price combinator snapshots on the force's period", function()
    for level = 0, 2 do
      research(level)
      storage.price_signals.snapshots[force().index] = { tick = game.tick - core.period(level) + 1, version = 1,
        buy = {}, sell = {} }
      storage.price_signals.builders = {}
      local combinator = game.surfaces[1].create_entity({ name = "gb-sell-price-combinator", position = { 3, 130 },
        force = "player", raise_built = true })
      local hub = game.surfaces[1].create_entity({ name = "gb-hub", position = { 0, 130 }, force = "player",
        raise_built = true })
      hub.energy = hub.electric_buffer_size
      for _ = 1, #storage.price_signals.order do price_signals.on_pass_tick() end
      assert.is_nil(storage.price_signals.builders[force().index], "level " .. level)
      storage.price_signals.snapshots[force().index].tick = game.tick - core.period(level)
      for _ = 1, #storage.price_signals.order do price_signals.on_pass_tick() end
      assert.is_truthy(storage.price_signals.builders[force().index], "level " .. level)
      local unit_number = combinator.unit_number
      combinator.destroy()
      hub.destroy()
      price_signals.forget(unit_number)
    end
    storage.price_signals.snapshots = {}
    storage.price_signals.builders = {}
  end)

  test("measures price combinators at level 2 with 30 combinators and prices moving", function()
    research(2)
    local surface = game.surfaces[1]
    local hub = surface.create_entity({ name = "gb-hub", position = { 0, 140 }, force = "player", raise_built = true })
    hub.energy = hub.electric_buffer_size
    local placed = { hub }
    for i = 0, 29 do
      placed[#placed + 1] = surface.create_entity({ name = "gb-sell-price-combinator",
        position = { -7 + (i % 8) * 2, 134 + math.floor(i / 8) * 3 }, force = "player", raise_built = true })
    end
    local passes = 200
    local profiler = helpers.create_profiler()
    for pass = 1, passes do
      if pass % 20 == 0 then market.sell(force().index, "item", GEAR, 500) end
      price_signals.on_pass_tick()
    end
    profiler.stop()
    profiler.divide(passes * price_signals.PASS_TICKS)
    log({ "", "[galactic-bazaar] price combinators at telecommunications 2 (30 combinators), per tick: ", profiler })
    for _, entity in ipairs(placed) do
      local unit_number = entity.unit_number
      entity.destroy()
      price_signals.forget(unit_number)
    end
    storage.price_signals.snapshots = {}
    storage.price_signals.builders = {}
  end)

  test("keep the feed across a save and reload", function()
    storage.gb_test_feed = telecom.quote(force().index, "item", GEAR).sell
  end).after_reload_mods(function()
    assert.are.equal(storage.gb_test_feed, storage.forces[game.forces.player.index].feed["item/iron-gear-wheel"].sell)
    storage.gb_test_feed = nil
  end)
end)
