local orders = require("scripts.core.orders")

local function item(name, count, quality)
  return { signal = { name = name, quality = quality }, count = count }
end

describe("orders.requests", function()
  it("keeps positive normal-quality item signals, sorted, and reads the budget signal", function()
    local requests, budget = orders.requests({
      item("iron-plate", 100), item("coal", 50), item("stone", -5), item("copper-plate", 10, "rare"),
      { signal = { type = "fluid", name = "water" }, count = 1000 },
      { signal = { type = "virtual", name = "gb-credits" }, count = 500 },
      { signal = { type = "item", name = "wood", quality = "normal" }, count = 3 },
    }, "gb-credits")
    assert.are.same({
      { name = "coal", units = 50 }, { name = "iron-plate", units = 100 }, { name = "wood", units = 3 },
    }, requests)
    assert.are.equal(500, budget)
  end)

  it("reads nothing from an empty or missing network", function()
    assert.are.same({ {}, 0 }, { orders.requests(nil, "gb-credits") })
  end)
end)

describe("orders.budget", function()
  it("is the budget signal when positive, else a share of the balance, never above the balance", function()
    assert.are.equal(500, orders.budget(10000, 500))
    assert.are.equal(10000 * orders.BUDGET_SHARE, orders.budget(10000, 0))
    assert.are.equal(200, orders.budget(200, 5000))
    assert.are.equal(0, orders.budget(-5, 0))
  end)
end)
