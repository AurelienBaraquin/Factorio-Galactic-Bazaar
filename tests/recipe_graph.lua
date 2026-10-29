-- In-game tests of the production graph built from the real prototypes (scripts/recipe_graph.lua +
-- scripts/core/recipe_graph.lua). Run in vanilla and with Space Age.
local raw_graph = require("scripts.recipe_graph")
local recipe_graph = require("scripts.core.recipe_graph")

local function find(list, name)
  for _, entry in ipairs(list) do
    if entry.name == name then return entry end
  end
end

local function is_finite_positive(n)
  return n == n and n > 0 and n < math.huge
end

describe("production graph", function()
  local graph
  before_all(function()
    local profiler = helpers.create_profiler()
    graph = recipe_graph.build(raw_graph.extract())
    profiler.stop()
    log({ "", "[galactic-bazaar] production graph built: ", #graph.recipes, " recipes, ", #graph.fallback,
      " fallback sources, in ", profiler })
  end)

  test("has only finite, positive amounts and non-negative costs", function()
    for _, list in ipairs({ graph.recipes, graph.fallback }) do
      for _, built in ipairs(list) do
        assert.is_true(built.cost >= 0 and built.cost < math.huge, built.name)
        for _, side in ipairs({ built.inputs, built.outputs }) do
          for key, amount in pairs(side) do
            assert.is_true(is_finite_positive(amount), built.name .. " " .. key)
          end
        end
      end
    end
  end)

  test("contains crafting, mining and pumping recipes", function()
    assert.are.same({ ["item/iron-plate"] = 1 }, find(graph.recipes, "iron-plate").outputs)
    assert.are.same({ ["item/iron-ore"] = 1 }, find(graph.recipes, "mine/iron-ore").outputs)
    assert.is_table(find(graph.recipes, "pump/water"))
    assert.is_table(find(graph.fallback, "mine/fish"))
  end)

  test("nets the Kovarex catalyst", function()
    assert.are.same({ ["item/uranium-238"] = 3 }, find(graph.recipes, "kovarex-enrichment-process").inputs)
  end)

  test("excludes every recycling recipe when the recycler is active", function()
    if not script.active_mods["recycler"] then return end
    assert.are.equal("recycling", graph.excluded["iron-gear-wheel-recycling"])
    for _, built in ipairs(graph.recipes) do
      assert.is_nil(built.name:find("%-recycling$"), built.name)
    end
  end)
end)
