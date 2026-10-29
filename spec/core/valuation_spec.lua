local valuation = require("scripts.core.valuation")

local function recipe(name, cost, inputs, outputs)
  return { name = name, cost = cost, inputs = inputs or {}, outputs = outputs }
end

local function near(expected, actual)
  return math.abs(expected - actual) <= 1e-9 * math.max(1, math.abs(expected))
end

local function compute(recipes, fallback)
  return valuation.compute({ recipes = recipes, fallback = fallback or {} })
end

describe("valuation.compute", function()
  it("adds input values and recipe cost along a chain", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("plate", 0.32, { ore = 1 }, { plate = 1 }),
      recipe("gear", 0.05, { plate = 2 }, { gear = 1 }),
    })
    assert.is_true(near(1.32, result.values.plate))
    assert.is_true(near(2.69, result.values.gear))
    assert.is_true(result.converged)
  end)

  it("keeps the cheapest of several recipes", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("slow", 5, { ore = 1 }, { plate = 1 }),
      recipe("fast", 1, { ore = 2 }, { plate = 4 }),
    })
    assert.is_true(near(0.75, result.values.plate))
  end)

  it("gives a rare by-product a higher value per unit than a common one", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("processing", 0, { ore = 10 }, { common = 0.99, rare = 0.01 }),
    })
    assert.is_true(result.values.rare > 50 * result.values.common)
    assert.is_true(near(10, result.values.common * 0.99 + result.values.rare * 0.01))
  end)

  it("lets a second recipe anchor a by-product's value, like Kovarex for uranium-235", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("processing", 0, { ore = 10 }, { u238 = 0.993, u235 = 0.007 }),
      recipe("kovarex", 6, { u238 = 3 }, { u235 = 1 }),
    })
    local v238, v235 = result.values.u238, result.values.u235
    assert.is_true(near(3 * v238 + 6, v235))
    assert.is_true(v238 < 10 / 0.993)
    assert.is_true(v235 > 3 * v238)
  end)

  it("is not lowered by a cycle that costs something", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("smelt", 0.3, { ore = 1 }, { plate = 1 }),
      recipe("press", 0.1, { plate = 1 }, { sheet = 1 }),
      recipe("unpress", 0.1, { sheet = 1 }, { plate = 1 }),
    })
    assert.is_true(near(1.3, result.values.plate))
    assert.is_true(near(1.4, result.values.sheet))
  end)

  it("prices from fallback sources only what the main graph cannot", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("crushing", 0.1, { chunk = 1 }, { ore = 20 }),
    }, {
      recipe("mine/asteroid", 0.2, {}, { chunk = 1 }),
      recipe("mine/tree", 0.5, {}, { wood = 4 }),
    })
    assert.are.equal(1, result.values.ore)
    assert.is_true(near(0.2, result.values.chunk))
    assert.is_true(near(0.125, result.values.wood))
  end)

  it("never values anything below the minimum, even for free recipes", function()
    local result = compute({ recipe("free", 0, {}, { thing = 1 }) })
    assert.are.equal(valuation.MIN_VALUE, result.values.thing)
  end)

  it("lists keys it cannot price, sorted", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("needs-steam", 1, { steam = 1, ore = 1 }, { turbine = 1 }),
      recipe("reprocessing", 1, { depleted = 1 }, { ore = 1 }),
    })
    assert.are.same({ "depleted", "steam", "turbine" }, result.unpriced)
  end)

  it("gives the same values whatever the recipe order", function()
    local recipes = {
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("oil", 1, { ore = 3 }, { heavy = 25, light = 45, gas = 55 }),
      recipe("cracking", 0.2, { heavy = 40 }, { light = 30 }),
    }
    local forward = compute(recipes).values
    local backward = compute({ recipes[3], recipes[2], recipes[1] }).values
    assert.are.same(forward, backward)
  end)
end)
