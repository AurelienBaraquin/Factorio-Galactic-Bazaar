-- In-game tests of the base values computed from the real prototypes (scripts/pricing.lua).
-- Run in vanilla and with Space Age.
local raw_graph = require("scripts.recipe_graph")
local recipe_graph = require("scripts.core.recipe_graph")
local valuation = require("scripts.core.valuation")
local pricing = require("scripts.pricing")

describe("base values", function()
  test("are finite and positive for every priced item and fluid", function()
    local count = 0
    for key, value in pairs(storage.base_values) do
      assert.is_true(value == value and value > 0 and value < math.huge, key)
      count = count + 1
    end
    assert.is_true(count > 150)
  end)

  test("converge, and leave at most a handful of keys unpriced", function()
    local profiler = helpers.create_profiler()
    local result = valuation.compute(recipe_graph.build(raw_graph.extract()))
    profiler.stop()
    log({ "", "[galactic-bazaar] base values computed in ", profiler, ", ", result.iterations, " iterations" })
    assert.is_true(result.converged)
    assert.is_true(#result.unpriced <= 3, table.concat(result.unpriced, ", "))
  end)

  test("follow production: products are worth more than their main ingredients", function()
    assert.is_true(pricing.base_value("item", "iron-plate") > pricing.base_value("item", "iron-ore"))
    assert.is_true(pricing.base_value("item", "iron-gear-wheel") > pricing.base_value("item", "iron-ore"))
    assert.is_true(pricing.base_value("item", "processing-unit") > pricing.base_value("item", "electronic-circuit"))
    assert.is_true(pricing.base_value("item", "uranium-235") > pricing.base_value("item", "uranium-238"))
    assert.is_true(pricing.base_value("fluid", "water") < pricing.base_value("fluid", "crude-oil"))
  end)

  test("are kept in storage across a save and reload", function()
    storage.gb_test_iron_plate = pricing.base_value("item", "iron-plate")
  end).after_reload_mods(function()
    assert.are.equal(storage.gb_test_iron_plate, pricing.base_value("item", "iron-plate"))
    storage.gb_test_iron_plate = nil
  end)
end)
