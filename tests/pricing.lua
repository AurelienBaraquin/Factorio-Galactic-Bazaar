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

  test("are computed quickly, leaving few tradeable keys unpriced", function()
    local profiler = helpers.create_profiler()
    local graph = recipe_graph.build(raw_graph.extract())
    local result = valuation.compute(graph, graph.keys)
    profiler.stop()
    log({ "", "[galactic-bazaar] graph and base values computed in ", profiler, "; unpriced: ",
      table.concat(result.unpriced, ", ") })
    assert.is_true(#result.unpriced <= 3, table.concat(result.unpriced, ", "))
  end)

  test("follow production: products are worth more than their main ingredients", function()
    assert.is_true(pricing.base_value("item", "iron-plate") > pricing.base_value("item", "iron-ore"))
    assert.is_true(pricing.base_value("item", "iron-gear-wheel") > pricing.base_value("item", "iron-ore"))
    assert.is_true(pricing.base_value("item", "processing-unit") > pricing.base_value("item", "electronic-circuit"))
    assert.is_true(pricing.base_value("item", "uranium-235") > pricing.base_value("item", "uranium-238"))
    assert.is_true(pricing.base_value("fluid", "water") < pricing.base_value("fluid", "crude-oil"))
    assert.is_true(pricing.base_value("item", "space-science-pack") > 0)
  end)

  test("price holmium ore through scrap recycling, not ruins, with Space Age", function()
    if not script.active_mods["space-age"] then return end
    local scrap = pricing.base_value("item", "scrap")
    assert.is_true(pricing.base_value("item", "holmium-ore") > scrap)
  end)

  test("are kept in storage across a save and reload", function()
    storage.gb_test_iron_plate = pricing.base_value("item", "iron-plate")
  end).after_reload_mods(function()
    assert.are.equal(storage.gb_test_iron_plate, pricing.base_value("item", "iron-plate"))
    storage.gb_test_iron_plate = nil
  end)
end)
