-- In-game tests of value overrides (scripts/pricing.lua, ADR-0007): the remote interface other mods
-- call, its input checks, and persistence.
local pricing = require("scripts.pricing")

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
    pricing.init()
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
    }) do
      local ok, message = pcall(call, table.unpack(args))
      assert.is_false(ok, args[1] .. " " .. args[3])
      assert.is_truthy(tostring(message):find("galactic-bazaar", 1, true))
    end
    assert.are.same({}, storage.value_overrides)
    assert.are.equal(original.plate, pricing.base_value("item", "iron-plate"))
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
