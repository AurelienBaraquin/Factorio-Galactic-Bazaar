-- In-game tests of the per-force market (scripts/market.lua): quotes, atomic trades, persistence.
local market = require("scripts.market")

local function player_state() return storage.forces[game.forces.player.index] end

describe("market", function()
  local saved_balance
  before_each(function()
    saved_balance = player_state().balance
    player_state().markets["item/iron-gear-wheel"] = nil
  end)
  after_each(function()
    player_state().balance = saved_balance
    player_state().markets["item/iron-gear-wheel"] = nil
  end)

  test("quotes a tradeable item around its base value, buy above sell", function()
    local quote = market.quote(game.forces.player.index, "item", "iron-gear-wheel")
    local base = storage.base_values["item/iron-gear-wheel"]
    assert.are.equal(base, quote.mid)
    assert.is_true(quote.buy > quote.mid and quote.sell < quote.mid)
  end)

  test("has no quote for something without a base value", function()
    assert.is_nil(market.quote(game.forces.player.index, "item", "depleted-uranium-fuel-cell"))
    local ok, reason = market.buy(game.forces.player.index, "item", "depleted-uranium-fuel-cell", 1)
    assert.is_false(ok)
    assert.are.equal("not-tradeable", reason)
  end)

  test("refuses a purchase the force cannot pay, changing nothing", function()
    player_state().balance = 0
    local before = market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid
    local ok, reason = market.buy(game.forces.player.index, "item", "iron-gear-wheel", 10)
    assert.is_false(ok)
    assert.are.equal("insufficient-funds", reason)
    assert.are.equal(0, player_state().balance)
    assert.are.equal(before, market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid)
  end)

  test("debits the account and raises the price on a purchase", function()
    player_state().balance = 1e6
    local before = market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid
    local ok, cost = market.buy(game.forces.player.index, "item", "iron-gear-wheel", 1000)
    assert.is_true(ok)
    assert.is_true(math.abs(player_state().balance - (1e6 - cost)) < 1e-6)
    assert.is_true(market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid > before)
    assert.are.equal("buy", player_state().journal[#player_state().journal].kind)
  end)

  test("credits the account and lowers the price on a sale", function()
    player_state().balance = 0
    local before = market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid
    local ok, revenue = market.sell(game.forces.player.index, "item", "iron-gear-wheel", 1000)
    assert.is_true(ok and revenue > 0)
    assert.is_true(math.abs(player_state().balance - revenue) < 1e-6)
    assert.is_true(market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid < before)
  end)

  test("catches up every key after a long absence within the budget", function()
    local force_index = game.forces.player.index
    local markets = player_state().markets
    local keys = {}
    for key in pairs(storage.base_values) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
      local kind, name = key:match("^(%a+)/(.+)$")
      market.quote(force_index, kind, name)
      markets[key].tick = game.tick - 1000 * 3600
    end
    local profiler = helpers.create_profiler()
    for _, key in ipairs(keys) do
      local kind, name = key:match("^(%a+)/(.+)$")
      market.quote(force_index, kind, name)
    end
    profiler.stop()
    log({ "", "[galactic-bazaar] full market catch-up of ", #keys, " keys: ", profiler })
    for _, key in ipairs(keys) do
      assert.are.equal(30, #markets[key].history)
      markets[key] = nil
    end
  end)

  test("keeps the market moved by a trade across a save and reload", function()
    market.sell(game.forces.player.index, "item", "iron-gear-wheel", 5000)
    storage.gb_test_mid = market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid
  end).after_reload_mods(function()
    assert.are.equal(storage.gb_test_mid, market.quote(game.forces.player.index, "item", "iron-gear-wheel").mid)
    storage.gb_test_mid = nil
  end)
end)
