local market = require("scripts.core.market")

local params = market.DEFAULTS
local V = 2

local function near(expected, actual, tolerance)
  return math.abs(expected - actual) <= (tolerance or 1e-9) * math.max(1, math.abs(expected))
end

describe("market prices", function()
  it("are the base value, around the spread, when the market is balanced", function()
    assert.are.equal(V, market.mid_price(V, 0, params))
    assert.is_true(near(V * 1.05, market.buy_price(V, 0, params)))
    assert.is_true(near(V * 0.95, market.sell_price(V, 0, params)))
  end)

  it("fall with a surplus and rise with a shortage, by a factor e per depth", function()
    local depth = market.depth(V, params)
    assert.is_true(near(V / math.exp(1), market.mid_price(V, depth, params)))
    assert.is_true(near(V * math.exp(1), market.mid_price(V, -depth, params)))
  end)

  it("give cheap items a deeper market in units than expensive ones", function()
    assert.is_true(market.depth(1, params) > market.depth(100, params))
    assert.are.equal(params.depth_credits, market.depth(1, params))
  end)
end)

describe("market.quote_buy", function()
  it("costs the marginal buy price for a tiny order", function()
    local cost = market.quote_buy(V, 0, 1e-3, params)
    assert.is_true(near(1e-3 * market.buy_price(V, 0, params), cost, 1e-6))
  end)

  it("costs more per unit the larger the order, and moves the displacement down", function()
    local small = market.quote_buy(V, 0, 10, params) / 10
    local cost, displacement = market.quote_buy(V, 0, 10000, params)
    assert.is_true(cost / 10000 > small)
    assert.are.equal(-10000, displacement)
  end)

  it("costs the same in one order as in two consecutive halves", function()
    local whole = market.quote_buy(V, 0, 6000, params)
    local first, after = market.quote_buy(V, 0, 3000, params)
    local second = market.quote_buy(V, after, 3000, params)
    assert.is_true(near(whole, first + second))
  end)

  it("refuses non-positive quantities and orders beyond the shortage bound", function()
    assert.is_nil(market.quote_buy(V, 0, 0, params))
    assert.is_nil(market.quote_buy(V, 0, 0 / 0, params))
    assert.is_nil(market.quote_sell(V, 0, -1, params))
    local cost, reason = market.quote_buy(V, 0, market.max_buy(V, 0, params) + 1, params)
    assert.is_nil(cost)
    assert.are.equal("insufficient-liquidity", reason)
  end)

  it("stays finite at the bound", function()
    local cost = market.quote_buy(V, 0, market.max_buy(V, 0, params), params)
    assert.is_true(cost > 0 and cost < math.huge)
  end)
end)

describe("market.quote_sell", function()
  it("pays less per unit the larger the order, and moves the displacement up", function()
    local small = market.quote_sell(V, 0, 10, params) / 10
    local revenue, displacement = market.quote_sell(V, 0, 10000, params)
    assert.is_true(revenue / 10000 < small)
    assert.are.equal(10000, displacement)
  end)

  it("refuses orders beyond the surplus bound", function()
    local revenue, reason = market.quote_sell(V, 0, market.max_sell(V, 0, params) + 1, params)
    assert.is_nil(revenue)
    assert.are.equal("insufficient-liquidity", reason)
  end)
end)

describe("market.max_sell_at_or_above", function()
  it("sells down exactly to the price floor", function()
    local floor = 0.5 * V
    local units = market.max_sell_at_or_above(V, 0, floor, params)
    assert.is_true(units > 0)
    assert.is_true(near(floor, market.sell_price(V, units, params)))
  end)

  it("sells nothing when the price is already below the floor", function()
    local depth = market.depth(V, params)
    assert.are.equal(0, market.max_sell_at_or_above(V, 2 * depth, 0.5 * V, params))
  end)

  it("is bounded by the market's surplus bound, and unbounded floors use it", function()
    assert.are.equal(market.max_sell(V, 0, params), market.max_sell_at_or_above(V, 0, 0, params))
    assert.are.equal(market.max_sell(V, 0, params), market.max_sell_at_or_above(V, 0, 1e-12, params))
  end)
end)

describe("round trips", function()
  for _, quantity in ipairs({ 1, 100, 10000, 100000 }) do
    it("always lose money when buying then selling " .. quantity .. " units at once", function()
      local cost, after_buy = market.quote_buy(V, 0, quantity, params)
      local revenue = market.quote_sell(V, after_buy, quantity, params)
      assert.is_true(revenue < cost)
      assert.is_true(near(cost * (1 - params.spread / 2) / (1 + params.spread / 2), revenue))
    end)

    it("always lose money when selling then buying back " .. quantity .. " units at once", function()
      local revenue, after_sell = market.quote_sell(V, 0, quantity, params)
      local cost = market.quote_buy(V, after_sell, quantity, params)
      assert.is_true(revenue < cost)
    end)
  end
end)

describe("market.decay", function()
  it("halves the displacement every half-life and keeps its sign", function()
    assert.are.equal(500, market.decay(1000, params.half_life_ticks, params))
    assert.are.equal(-250, market.decay(-1000, 2 * params.half_life_ticks, params))
    assert.are.equal(1000, market.decay(1000, 0, params))
  end)
end)

describe("market.rebase", function()
  it("keeps the price the same multiple of a new base value", function()
    local depth = market.depth(V, params)
    local before = market.mid_price(V, 3 * depth, params) / V
    local after_displacement = market.rebase(3 * depth, V, 100 * V, params)
    assert.is_true(near(before, market.mid_price(100 * V, after_displacement, params) / (100 * V)))
  end)

  it("stays within the bounds of the new value", function()
    local bound = params.max_depths * market.depth(V / 7, params)
    assert.is_true(near(bound, market.rebase(1e12, V, V / 7, params)))
    assert.is_true(near(-bound, market.rebase(-1e12, V, V / 7, params)))
  end)
end)
