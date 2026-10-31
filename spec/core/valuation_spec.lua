local valuation = require("scripts.core.valuation")

local function recipe(name, cost, inputs, outputs)
  return { name = name, cost = cost, inputs = inputs or {}, outputs = outputs }
end

local function near(expected, actual)
  return math.abs(expected - actual) <= 1e-9 * math.max(1, math.abs(expected))
end

local function compute(recipes, fallback, natural, keys, fixed)
  return valuation.compute({ recipes = recipes, fallback = fallback or {}, natural = natural or {} }, keys, fixed)
end

describe("valuation.compute", function()
  it("adds input values and recipe cost along a chain", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("plate", 0.32, { ore = 1 }, { plate = 1 }),
      recipe("gear", 0.05, { plate = 2 }, { gear = 1 }),
    }).values
    assert.is_true(near(1.32, values.plate))
    assert.is_true(near(2.69, values.gear))
  end)

  it("keeps the cheapest of several recipes", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("slow", 5, { ore = 1 }, { plate = 1 }),
      recipe("fast", 1, { ore = 2 }, { plate = 4 }),
    }).values
    assert.is_true(near(0.75, values.plate))
  end)

  it("finds a cheaper bulk path through a more expensive intermediate, like coal liquefaction", function()
    local values = compute({
      recipe("mine/crude", 1, {}, { crude = 10 }),
      recipe("oil", 0, { crude = 100 }, { heavy = 25, light = 45 }),
      recipe("mine/coal", 1, {}, { coal = 1 }),
      recipe("liquefaction", 0, { coal = 10 }, { heavy = 1000 }),
    }).values
    assert.is_true(near(0.01, values.heavy))
  end)

  it("gives a rare by-product a higher value per unit than a common one", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("processing", 0, { ore = 10 }, { common = 0.99, rare = 0.01 }),
    }).values
    assert.is_true(values.rare > 50 * values.common)
    assert.is_true(near(10, values.common * 0.99 + values.rare * 0.01))
  end)

  it("lets a second recipe anchor a by-product's value, like Kovarex for uranium-235", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("processing", 0, { ore = 10 }, { u238 = 0.993, u235 = 0.007 }),
      recipe("kovarex", 6, { u238 = 3 }, { u235 = 1 }),
    }).values
    assert.is_true(near(3 * values.u238 + 6, values.u235))
    assert.is_true(near(5 / 0.993, values.u238))
  end)

  it("is not pulled down by a loop through the key itself, like cutting and welding a plate", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("smelt", 0.32, { ore = 1 }, { plate = 1 }),
      recipe("cut", 0.01, { plate = 1 }, { strip = 1, scrap = 1 }),
      recipe("weld", 0.01, { strip = 1 }, { plate = 1 }),
    }).values
    assert.is_true(near(1.32, values.plate))
    assert.is_true(near(0.665, values.strip))
  end)

  it("is not pulled down by filling and emptying a barrel", function()
    local values = compute({
      recipe("pump/water", 0.001, {}, { water = 1 }),
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("barrel", 0.1, { ore = 1 }, { barrel = 1 }),
      recipe("fill", 0.02, { barrel = 1, water = 50 }, { filled = 1 }),
      recipe("empty", 0.02, { filled = 1 }, { barrel = 1, water = 50 }),
    }).values
    assert.is_true(near(0.001, values.water))
    assert.is_true(near(1.1, values.barrel))
  end)

  it("prices from fallback sources only what the main graph cannot, splitting over all outputs", function()
    local values = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("crushing", 0.1, { chunk = 1 }, { ore = 20 }),
      recipe("tap", 2, {}, { resin = 1, sap = 1 }),
    }, {
      recipe("mine/asteroid", 0.2, {}, { chunk = 1 }),
    }).values
    assert.are.equal(1, values.ore)
    assert.is_true(near(0.2, values.chunk))
    assert.is_true(near(1, values.sap))
  end)

  it("lets a process beat scavenging: natural sources come after the fallback", function()
    local values = compute({
      recipe("mine/scrap", 0.5, {}, { scrap = 1 }),
    }, {
      recipe("scrap-recycling", 0.02, { scrap = 1 }, { gear = 1, holmium = 0.01 }),
    }, {
      recipe("mine/ruin", 0.5, {}, { holmium = 5, stone = 10 }),
    }).values
    assert.is_true(near(0.26 / 0.01, values.holmium))
    assert.is_true(near(0.025, values.stone))
  end)

  it("never values anything below the minimum, even for free recipes", function()
    local values = compute({ recipe("free", 0, {}, { thing = 1 }) }).values
    assert.are.equal(valuation.MIN_VALUE, values.thing)
  end)

  it("lists every wanted key it cannot price, sorted", function()
    local result = compute({
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("needs-steam", 1, { steam = 1, ore = 1 }, { turbine = 1 }),
    }, nil, nil, { "ore", "pistol" })
    assert.are.same({ "pistol", "steam", "turbine" }, result.unpriced)
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

  describe("records the source of each value", function()
    -- The value a source record gives back: its cost plus its inputs, shared over its outputs.
    local function value_of(source)
      local total = source.cost
      for _, input in ipairs(source.inputs) do total = total + input.amount * input.value end
      return math.max(total / source.share / source.amount, valuation.MIN_VALUE)
    end

    it("names the recipe that set a value, with the input values it used", function()
      local result = compute({
        recipe("mine/ore", 1, {}, { ore = 1 }),
        recipe("plate", 0.32, { ore = 1 }, { plate = 1 }),
        recipe("gear", 0.05, { plate = 2 }, { gear = 1 }),
      })
      local gear = result.sources.gear
      assert.are.same({ recipe = "gear", cost = 0.05, share = 1, amount = 1 },
        { recipe = gear.recipe, cost = gear.cost, share = gear.share, amount = gear.amount })
      assert.are.equal(1, #gear.inputs)
      assert.are.same({ "plate", 2 }, { gear.inputs[1].key, gear.inputs[1].amount })
      assert.is_true(near(result.values.plate, gear.inputs[1].value))
      assert.are.same({}, result.sources.ore.inputs)
    end)

    it("keeps the recipe of the cheapest offer, with its outputs and amount", function()
      local result = compute({
        recipe("mine/ore", 1, {}, { ore = 1 }),
        recipe("slow", 5, { ore = 1 }, { plate = 1 }),
        recipe("fast", 1, { ore = 2 }, { plate = 4, slag = 1 }),
      })
      local plate = result.sources.plate
      assert.are.same({ "fast", 2, 4 }, { plate.recipe, plate.share, plate.amount })
      assert.is_true(near(result.values.plate, value_of(plate)))
    end)

    it("keeps the source that set the value when a loop or a by-product offers another", function()
      local result = compute({
        recipe("mine/ore", 1, {}, { ore = 1 }),
        recipe("smelt", 0.32, { ore = 1 }, { plate = 1 }),
        recipe("cut", 0.01, { plate = 1 }, { strip = 1, scrap = 1 }),
        recipe("weld", 0.01, { strip = 1 }, { plate = 1 }),
        recipe("processing", 0, { ore = 10 }, { u238 = 0.993, u235 = 0.007 }),
        recipe("kovarex", 6, { u238 = 3 }, { u235 = 1 }),
      })
      assert.are.same({ "smelt", "kovarex" }, { result.sources.plate.recipe, result.sources.u235.recipe })
    end)

    it("gives back every value it computed, in every tier, and none for fixed values", function()
      local result = compute({
        recipe("mine/ore", 1, {}, { ore = 1 }),
        recipe("oil", 1, { ore = 3 }, { heavy = 25, light = 45, gas = 55 }),
        recipe("cracking", 0.2, { heavy = 40 }, { light = 30 }),
        recipe("crushing", 0.1, { chunk = 1 }, { ore = 20 }),
        recipe("free", 0, {}, { thing = 1 }),
      }, {
        recipe("mine/asteroid", 0.2, {}, { chunk = 1 }),
      }, {
        recipe("tree", 0.5, {}, { wood = 1 }),
      }, nil, { gas = { value = 3 } })
      for key, value in pairs(result.values) do
        if key == "gas" then
          assert.is_nil(result.sources.gas)
        else
          assert.is_true(near(value, value_of(result.sources[key])), key)
        end
      end
      assert.are.same({ "mine/asteroid", "tree" }, { result.sources.chunk.recipe, result.sources.wood.recipe })
    end)
  end)

  describe("with fixed values", function()
    local chain = {
      recipe("mine/ore", 1, {}, { ore = 1 }),
      recipe("plate", 0.32, { ore = 1 }, { plate = 1 }),
      recipe("gear", 0.05, { plate = 2 }, { gear = 1 }),
    }

    it("keeps a fixed value and propagates it to the products", function()
      local values = compute(chain, nil, nil, nil, { plate = { value = 10 } }).values
      assert.are.equal(10, values.plate)
      assert.is_true(near(20.05, values.gear))
      assert.are.equal(1, values.ore)
    end)

    it("is not lowered by a cheaper recipe", function()
      local values = compute(chain, nil, nil, nil, { gear = { value = 0.5 } }).values
      assert.are.equal(0.5, values.gear)
    end)

    it("keeps a fixed key of a later tier from undercutting an earlier chain", function()
      local recipes = {
        recipe("mine/ore", 1, {}, { ore = 1 }),
        recipe("smelt", 100, { ore = 1 }, { plate = 1 }),
        recipe("from-wood", 0, { wood = 1 }, { plate = 1 }),
      }
      local natural = { recipe("tree", 0.5, {}, { wood = 1 }) }
      local first = compute(recipes, nil, natural)
      assert.are.equal(valuation.NATURAL, first.tiers.wood)
      assert.are.equal(valuation.MAIN, first.tiers.plate)
      local fixed_wood = { wood = { value = first.values.wood, tier = first.tiers.wood } }
      local same = compute(recipes, nil, natural, nil, fixed_wood)
      assert.are.equal(first.values.plate, same.values.plate)
      local as_main = compute(recipes, nil, natural, nil, { wood = { value = first.values.wood } })
      assert.is_true(as_main.values.plate < first.values.plate)
    end)

    it("prices a key that no recipe can make", function()
      local result = compute(chain, nil, nil, { "ore", "plate", "gear", "relic" }, { relic = { value = 7 } })
      assert.are.equal(7, result.values.relic)
      assert.are.same({}, result.unpriced)
    end)
  end)
end)
