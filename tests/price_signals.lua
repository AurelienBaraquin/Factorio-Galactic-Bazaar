-- In-game tests of the price signal combinators (scripts/price_signals.lua, ADR-0010): prices and
-- balance on the circuit network, scaling, hub requirement and refresh.
local market = require("scripts.market")
local price_signals = require("scripts.price_signals")
local signals = require("scripts.core.signals")

local surface, created
local function place(name, x, y, force)
  local entity = surface.create_entity({
    name = name, position = { x, y or 90 }, force = force or "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local W = defines.wire_connector_id
local GEAR = { type = "item", name = "iron-gear-wheel", quality = "normal" }
local CREDITS = { type = "virtual", name = price_signals.BALANCE_SIGNAL, quality = "normal" }

-- Runs passes until no snapshot is being built, then once more over every combinator; returns the
-- number of passes.
local function update_all()
  local passes = 0
  repeat
    price_signals.on_pass_tick()
    passes = passes + 1
  until next(storage.price_signals.builders) == nil
  for _ = 1, #storage.price_signals.order do price_signals.on_pass_tick() end
  return passes + #storage.price_signals.order
end

-- A pole wired to the combinator, to read what the network sees.
local function reader(combinator)
  local pole = place("small-electric-pole", combinator.position.x + 2, combinator.position.y)
  combinator.get_wire_connector(W.circuit_red, true).connect_to(pole.get_wire_connector(W.circuit_red, true))
  return pole
end

describe("price signal combinators", function()
  local saved_balance, hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 12345.4
    storage.price_signals.snapshots = {}
    storage.price_signals.builders = {}
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    if saved_balance then player_state().balance = saved_balance end
    storage.price_signals.snapshots = {}
    storage.price_signals.builders = {}
  end)

  test("are unlocked by the market signals technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-market-signals"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-buy-price-combinator"] and unlocks["gb-sell-price-combinator"])
  end)

  test("emit buy and sell prices in milli-credits and the balance in credits", function()
    local buy = place("gb-buy-price-combinator", 3, 88)
    local sell = place("gb-sell-price-combinator", 3, 92)
    local buy_pole, sell_pole = reader(buy), reader(sell)
    update_all()
    local quote = market.quote(game.forces.player.index, "item", "iron-gear-wheel")
    after_ticks(2, function()
      local buy_net = buy_pole.get_circuit_network(W.circuit_red)
      local sell_net = sell_pole.get_circuit_network(W.circuit_red)
      assert.are.equal(signals.price(quote.buy), buy_net.get_signal(GEAR))
      assert.are.equal(signals.price(quote.sell), sell_net.get_signal(GEAR))
      assert.are.equal(12345, buy_net.get_signal(CREDITS))
      assert.is_true(sell_net.get_signal({ type = "fluid", name = "water", quality = "normal" }) > 0)
    end)
  end)

  test("cannot be opened by players, and stay silent without a powered hub", function()
    local combinator = place("gb-sell-price-combinator", 3)
    assert.is_false(combinator.operable)
    hub.energy = 0
    update_all()
    assert.is_false(combinator.get_control_behavior().enabled)
  end)

  test("refresh after the update period, and only rewrite when the snapshot changed", function()
    local combinator = place("gb-sell-price-combinator", 3)
    update_all()
    local module = storage.price_signals.modules[combinator.unit_number]
    local version = module.written
    update_all()
    assert.are.equal(version, module.written)
    storage.price_signals.snapshots[game.forces.player.index].tick = game.tick - price_signals.UPDATE_TICKS
    update_all()
    update_all()
    assert.are.equal(version + 1, module.written)
  end)

  test("keep visiting every combinator after one is removed", function()
    local first = place("gb-sell-price-combinator", 3, 86)
    local second = place("gb-buy-price-combinator", 3, 94)
    price_signals.forget(first.unit_number)
    first.destroy()
    update_all()
    assert.is_true(second.get_control_behavior().enabled)
  end)

  test("measures a pass while a force's snapshot is rebuilt", function()
    place("gb-sell-price-combinator", 3)
    update_all()
    storage.price_signals.snapshots[game.forces.player.index].tick = game.tick - price_signals.UPDATE_TICKS
    price_signals.on_pass_tick()
    local profiler = helpers.create_profiler()
    local passes = update_all()
    profiler.stop()
    profiler.divide(passes)
    log({ "", "[galactic-bazaar] price signal pass during a snapshot rebuild (average of ", passes, "): ", profiler })
  end)

  test("keep their combinators across a save and reload", function()
    storage.gb_test_signals = { combinator = place("gb-sell-price-combinator", 3).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local module = storage.price_signals.modules[storage.gb_test_signals.combinator]
    assert.are.equal("sell", module.side)
    module.entity.destroy()
    storage.hubs[storage.gb_test_signals.hub].entity.destroy()
    storage.gb_test_signals = nil
  end)
end)
