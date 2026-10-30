local orders = require("scripts.core.orders")

local function item(name, count, quality)
  return { signal = { name = name, quality = quality }, count = count }
end

local function virtual(name, count)
  return { signal = { type = "virtual", name = name }, count = count }
end

describe("orders.requests", function()
  it("keeps positive normal-quality item signals and fluid signals, sorted, and reads the budget signal", function()
    local requests, budget, refused = orders.requests({
      item("iron-plate", 100), item("coal", 50), item("stone", -5), item("copper-plate", 10, "rare"),
      { signal = { type = "fluid", name = "water" }, count = 1000 },
      virtual("gb-budget", 500),
      { signal = { type = "item", name = "wood", quality = "normal" }, count = 3 },
    }, "gb-budget", "gb-credits")
    assert.are.same({
      { kind = "fluid", name = "water", units = 1000 }, { kind = "item", name = "coal", units = 50 },
      { kind = "item", name = "iron-plate", units = 100 }, { kind = "item", name = "wood", units = 3 },
    }, requests)
    assert.are.equal(500, budget)
    assert.is_false(refused)
  end)

  it("flags an input that carries the refused signal", function()
    local _, _, refused = orders.requests({ item("coal", 50), virtual("gb-credits", 1000) }, "gb-budget", "gb-credits")
    assert.is_true(refused)
  end)

  it("reads nothing from an empty or missing network", function()
    assert.are.same({ {}, 0, false }, { orders.requests(nil, "gb-budget", "gb-credits") })
  end)
end)

describe("orders.allowance", function()
  it("is the budget left for the force this period, within the balance", function()
    assert.are.equal(500, orders.allowance(500, 0, 10000))
    assert.are.equal(200, orders.allowance(500, 300, 10000))
    assert.are.equal(0, orders.allowance(500, 600, 10000))
    assert.are.equal(100, orders.allowance(500, 0, 100))
  end)

  it("is zero without a positive budget, so a zero or negative budget pauses buying", function()
    assert.are.equal(0, orders.allowance(0, 0, 10000))
    assert.are.equal(0, orders.allowance(-1, 0, 10000))
  end)
end)
