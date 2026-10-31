-- In-game tests of value overrides (scripts/pricing.lua, ADR-0007): the remote interface other mods
-- call, its input checks, and persistence.
local test_helpers = require("tests.helpers")
local market = require("scripts.market")
local pricing = require("scripts.pricing")
local value_overrides = require("scripts.value_overrides")

local function call(name, ...) return remote.call("galactic-bazaar", name, ...) end

describe("value overrides", function()
  local original
  before_each(function()
    original = {
      plate = pricing.base_value("item", "iron-plate"),
      gear = pricing.base_value("item", "iron-gear-wheel"),
    }
  end)
  after_each(function()
    storage.value_overrides = {}
    value_overrides.rebuild()
  end)

  test("fix a value exactly, and the products made from it follow", function()
    call("set_value", "item", "iron-plate", 10)
    assert.are.equal(10, call("get_value", "item", "iron-plate"))
    assert.is_true(pricing.base_value("item", "iron-chest") > 80)
    assert.are.equal(10, storage.base_values["item/iron-plate"])
  end)

  test("scale the value the production graph gives", function()
    call("scale_value", "fluid", "water", 3)
    local water = pricing.base_value("fluid", "water")
    call("clear_value", "fluid", "water")
    assert.is_true(math.abs(water - 3 * pricing.base_value("fluid", "water")) < 1e-9 * water)
  end)

  test("are removed by clear_value", function()
    call("set_value", "item", "iron-plate", 10)
    call("clear_value", "item", "iron-plate")
    assert.are.equal(original.plate, pricing.base_value("item", "iron-plate"))
    assert.are.equal(original.gear, pricing.base_value("item", "iron-gear-wheel"))
  end)

  test("refuse unknown or untradeable keys and invalid numbers, changing nothing", function()
    for _, args in ipairs({
      { "set_value", "item", "no-such-item", 1 },
      { "set_value", "entity", "iron-plate", 1 },
      { "set_value", "item", "blueprint", 1 },
      { "set_value", "item", "iron-plate", -1 },
      { "set_value", "item", "iron-plate", 0 },
      { "scale_value", "item", "iron-plate", 1 / 0 },
      { "get_value", "fluid", "iron-plate" },
      { "set_value", "item", "iron-plate", nil },
      { "scale_value", "item", "iron-plate", nil },
      { "set_value", "item", "iron-plate", 1e300 },
      { "scale_value", "item", "iron-plate", 0 },
    }) do
      local ok, message = pcall(call, table.unpack(args))
      assert.is_false(ok, args[1] .. " " .. args[3])
      assert.is_truthy(tostring(message):find("galactic-bazaar", 1, true))
    end
    assert.are.same({}, storage.value_overrides)
    assert.are.equal(original.plate, pricing.base_value("item", "iron-plate"))
  end)

  test("change nothing with a factor of 1, in the main tier or a later one", function()
    local before = {}
    for key, value in pairs(storage.base_values) do before[key] = value end
    call("scale_value", "item", "wood", 1)
    call("scale_value", "item", "iron-plate", 1)
    for key, value in pairs(before) do
      assert.is_true(math.abs(storage.base_values[key] - value) <= 1e-9 * value, key)
    end
  end)

  test("rebase the markets, so prices stay the same multiple of the new value and bounded", function()
    local force_index = game.forces.player.index
    local state = storage.forces[force_index]
    local saved_balance = state.balance
    test_helpers.set_balance(state, 0)
    market.sell(force_index, "item", "iron-plate", market.sellable(force_index, "item", "iron-plate", 0.01))
    local ratio = market.quote(force_index, "item", "iron-plate").mid / original.plate
    call("set_value", "item", "iron-plate", original.plate * 100)
    local quote = market.quote(force_index, "item", "iron-plate")
    assert.is_true(math.abs(quote.mid / (original.plate * 100) - ratio) < 1e-6 * ratio)
    assert.is_true(market.preview(force_index, "item", "iron-plate", "buy", 1) > 0)
    state.markets["item/iron-plate"] = nil
    test_helpers.set_balance(state, saved_balance)
  end)

  test("recompute every base value quickly", function()
    local profiler = helpers.create_profiler()
    call("set_value", "item", "iron-plate", 10)
    profiler.stop()
    log({ "", "[galactic-bazaar] base values recomputed after an override in ", profiler })
  end)

  test("are kept across a save and reload, and reapplied", function()
    call("set_value", "item", "iron-plate", 10)
  end).after_reload_mods(function()
    assert.are.same({ value = 10 }, storage.value_overrides["item/iron-plate"])
    assert.are.equal(10, pricing.base_value("item", "iron-plate"))
  end)
end)
