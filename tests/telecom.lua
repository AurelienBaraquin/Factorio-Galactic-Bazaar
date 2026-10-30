-- In-game tests of telecommunications (scripts/telecom.lua, ADR-0012): freshness of the prices a
-- force sees, and history and trends at level 2.
local market = require("scripts.market")
local market_gui = require("scripts.market_gui")
local telecom = require("scripts.telecom")
local core = require("scripts.core.telecom")

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local GEAR = "iron-gear-wheel"

local function research(level)
  for index, name in ipairs(telecom.TECHNOLOGIES) do
    force().technologies[name].researched = index <= level -- luacheck: ignore 122
  end
end

describe("telecommunications", function()
  before_each(function()
    state().feed = {}
    state().markets["item/" .. GEAR] = nil
  end)
  after_each(function()
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
    hub.energy = hub.electric_buffer_size
    market_gui.open(player, hub)
    local data = storage.players[player.index]
    data.selected = data.matches[1]
    market_gui.on_refresh_tick({ tick = (player.index % market_gui.SLOTS) * market_gui.SLOT_TICKS })
    assert.is_false(data.elements.trend_header.visible)
    assert.is_false(data.elements.history.visible)
    research(2)
    market_gui.on_refresh_tick({ tick = (player.index % market_gui.SLOTS) * market_gui.SLOT_TICKS })
    assert.is_true(data.elements.trend_header.visible)
    assert.is_true(data.elements.history.visible)
    market_gui.close(player.index)
    hub.destroy()
  end)
end)
