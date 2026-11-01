local item_detail = require("scripts.core.item_detail")
local market = require("scripts.core.market")
local npc_market = require("scripts.core.npc_market")
local recipe_graph = require("scripts.core.recipe_graph")
local valuation = require("scripts.core.valuation")

local PARAMS = market.DEFAULTS
local NPC = npc_market.DEFAULTS

local function near(expected, actual)
  return math.abs(expected - actual) <= 1e-9 * math.max(1, math.abs(expected))
end

describe("item_detail.market", function()
  it("gives the prices of a balanced market at its base value", function()
    local figures = item_detail.market(10, 0, PARAMS, NPC)
    assert.are.same({ 10, 10, 0, 0 }, { figures.base_value, figures.mid, figures.displacement, figures.gap })
    assert.is_true(near(10.5, figures.buy))
    assert.is_true(near(9.5, figures.sell))
    assert.are.equal(PARAMS.spread, figures.spread)
    assert.is_true(near(1, figures.spread_credits))
  end)

  it("measures how far a shortage takes the price from the base value, in percent, units and depths", function()
    local depth = market.depth(10, PARAMS)
    local figures = item_detail.market(10, -depth / 2, PARAMS, NPC)
    assert.are.equal(depth, figures.depth)
    assert.is_true(near(-0.5, figures.depths))
    assert.is_true(near(math.exp(0.5) - 1, figures.gap))
    assert.is_true(near(market.mid_price(10, -depth / 2, PARAMS), figures.mid))
    assert.is_true(near(market.buy_price(10, -depth / 2, PARAMS), figures.buy))
    assert.is_true(figures.gap > 0)
  end)

  it("gives the liquidity left on each side before the bounds", function()
    local depth = market.depth(10, PARAMS)
    local figures = item_detail.market(10, 300, PARAMS, NPC)
    assert.are.same({ market.max_buy(10, 300, PARAMS), market.max_sell(10, 300, PARAMS) },
      { figures.max_buy, figures.max_sell })
    assert.are.equal(PARAMS.max_depths * depth, figures.bound_units)
    assert.is_true(near(10 * math.exp(PARAMS.max_depths), figures.ceiling))
    assert.is_true(near(10 * math.exp(-PARAMS.max_depths), figures.floor))
  end)

  it("describes the NPC drift per step and the reversion towards the base value", function()
    local depth = market.depth(10, PARAMS)
    local figures = item_detail.market(10, depth, PARAMS, NPC)
    assert.are.same({ NPC.step_ticks, PARAMS.half_life_ticks }, { figures.step_ticks, figures.half_life_ticks })
    assert.is_true(near(NPC.volatility * depth, figures.drift_units))
    assert.is_true(near(math.exp(NPC.volatility) - 1, figures.drift_up))
    assert.is_true(near(1 - math.exp(-NPC.volatility), figures.drift_down))
    assert.is_true(near(10 * math.exp(-0.5), figures.reverted_mid))
  end)
end)

describe("item_detail under a market event", function()
  it("gives the capped buy and sell prices and the impact of an order on them", function()
    local depth = market.depth(10, PARAMS)
    local shift = -2 * depth
    local figures = item_detail.market(10, 100 + shift, PARAMS, NPC, shift)
    assert.is_true(near(market.shifted_buy_price(10, 100, shift, PARAMS), figures.buy))
    assert.is_true(near(market.shifted_sell_price(10, 100, shift, PARAMS), figures.sell))
    assert.is_true(near(market.mid_price(10, 100 + shift, PARAMS), figures.mid))
    local impact = item_detail.impact(10, 100 + shift, 50, PARAMS, shift)
    assert.is_true(near(market.quote_shifted_buy(10, 100, shift, 50, PARAMS), impact.buy.total))
    assert.is_true(near(market.quote_shifted_sell(10, 100, shift, 50, PARAMS), impact.sell.total))
    assert.is_true(near(market.shifted_buy_price(10, 50, shift, PARAMS), impact.buy.next_price))
  end)

  it("finds the shifted displacement back from a seen buy price, the surplus part added back", function()
    local depth = market.depth(10, PARAMS)
    for _, shift in ipairs({ -depth, 0, 0.01 * depth, 3 * depth }) do
      local buy = market.shifted_buy_price(10, 250, shift, PARAMS)
      assert.is_true(math.abs(250 + shift - item_detail.displacement_from_buy(10, buy, PARAMS, shift)) < 1e-6)
    end
  end)
end)

describe("item_detail.event", function()
  it("gives the share of the mid price a market event's shift makes", function()
    local depth = market.depth(10, PARAMS)
    local shortage = item_detail.event(10, -depth / 2, PARAMS)
    assert.is_true(near(-depth / 2, shortage.units))
    assert.is_true(near(-0.5, shortage.depths))
    assert.is_true(near(math.exp(0.5) - 1, shortage.effect))
    local surplus = item_detail.event(10, depth, PARAMS)
    assert.is_true(near(math.exp(-1) - 1, surplus.effect))
    assert.are.equal(0, item_detail.event(10, 0, PARAMS).effect)
  end)
end)

describe("item_detail.displacement_from_buy", function()
  it("finds the displacement back from a buy price", function()
    for _, displacement in ipairs({ 0, -1234.5, 4321 }) do
      local buy = market.buy_price(7, displacement, PARAMS)
      assert.is_true(math.abs(displacement - item_detail.displacement_from_buy(7, buy, PARAMS)) < 1e-6)
    end
  end)
end)

describe("item_detail.impact", function()
  it("gives the average unit price and the next price after buying and after selling", function()
    local impact = item_detail.impact(10, 0, 1000, PARAMS)
    local cost, after_buy = market.quote_buy(10, 0, 1000, PARAMS)
    local revenue, after_sell = market.quote_sell(10, 0, 1000, PARAMS)
    assert.is_true(near(cost / 1000, impact.buy.average))
    assert.is_true(near(cost, impact.buy.total))
    assert.is_true(near(market.buy_price(10, after_buy, PARAMS), impact.buy.next_price))
    assert.is_true(near(revenue / 1000, impact.sell.average))
    assert.is_true(near(market.sell_price(10, after_sell, PARAMS), impact.sell.next_price))
    assert.is_true(impact.buy.average > market.buy_price(10, 0, PARAMS))
    assert.is_true(impact.sell.average < market.sell_price(10, 0, PARAMS))
  end)

  it("gives the reason instead when the quantity is beyond the liquidity of a side", function()
    local impact = item_detail.impact(10, 0, market.max_buy(10, 0, PARAMS) + 1, PARAMS)
    assert.are.same({ reason = "insufficient-liquidity" }, impact.buy)
    assert.are.same({ reason = "insufficient-liquidity" }, impact.sell)
  end)
end)

describe("item_detail.history", function()
  it("is nil below two points", function()
    assert.is_nil(item_detail.history({}))
    assert.is_nil(item_detail.history({ 3 }))
  end)

  it("gives the lowest, highest, first and last prices and the change between them", function()
    local summary = item_detail.history({ 4, 2, 6, 5 })
    assert.are.same({ 2, 6, 4, 5 }, { summary.low, summary.high, summary.first, summary.last })
    assert.is_true(near(0.25, summary.change))
  end)
end)

describe("item_detail.breakdown", function()
  local gear = { recipe = "iron-gear-wheel", cost = 0.05, share = 1, amount = 1,
    inputs = { { key = "item/iron-plate", amount = 2, value = 1.32 } } }

  it("sums the ingredients and the crafting time cost of the recipe that set the value", function()
    local breakdown = item_detail.breakdown(gear, { value = 2.69, multiplier = 1, tier = valuation.MAIN })
    assert.are.same({ "recipe", "iron-gear-wheel", 1, 1 },
      { breakdown.kind, breakdown.name, breakdown.share, breakdown.amount })
    assert.are.same({ key = "item/iron-plate", amount = 2, value = 1.32, total = 2.64 }, breakdown.inputs[1])
    assert.is_true(near(0.05, breakdown.cost))
    assert.is_true(near(0.05 / recipe_graph.TIME_COST, breakdown.seconds))
    assert.is_true(near(2.69, breakdown.graph_value))
    assert.are.equal(2.69, breakdown.value)
    assert.are.same({ 1, 1 }, { breakdown.multiplier, breakdown.ratio })
  end)

  it("scales every figure by the value multiplier", function()
    local breakdown = item_detail.breakdown(gear, { value = 5.38, multiplier = 2 })
    assert.is_true(near(2.64, breakdown.inputs[1].value))
    assert.is_true(near(0.1, breakdown.cost))
    assert.is_true(near(0.05 / recipe_graph.TIME_COST, breakdown.seconds))
    assert.is_true(near(5.38, breakdown.graph_value))
  end)

  it("divides the cost over the outputs of the recipe and the amount it makes", function()
    local breakdown = item_detail.breakdown({ recipe = "advanced-oil-processing", cost = 0.5, share = 3,
      amount = 45, inputs = { { key = "fluid/crude-oil", amount = 100, value = 0.1 } } }, { value = 1, multiplier = 1 })
    assert.is_true(near((0.5 + 10) / 3 / 45, breakdown.graph_value))
  end)

  it("names mining, pumping, rocket launches and burning, with the mining time", function()
    local mine = item_detail.breakdown({ recipe = "mine/iron-ore", cost = 1, share = 1, amount = 1, inputs = {} },
      { value = 1, multiplier = 1 })
    assert.are.same({ "mine", "iron-ore" }, { mine.kind, mine.name })
    assert.is_true(near(1 / recipe_graph.MINING_COST, mine.seconds))
    local pump = item_detail.breakdown({ recipe = "pump/water", cost = 0.001, share = 1, amount = 1, inputs = {} },
      { value = 0.001, multiplier = 1 })
    assert.are.same({ "pump", "water" }, { pump.kind, pump.name })
    assert.is_nil(pump.seconds)
    local launch = item_detail.breakdown({ recipe = "launch/satellite", cost = 0, share = 1, amount = 1000,
      inputs = {} }, { value = 1, multiplier = 1 })
    local burn = item_detail.breakdown({ recipe = "burn/coal", cost = 0, share = 1, amount = 4, inputs = {} },
      { value = 1, multiplier = 1 })
    assert.are.same({ "launch", "satellite", "burn", "coal" }, { launch.kind, launch.name, burn.kind, burn.name })
  end)

  it("gives a value fixed by a mod as the source, without a recipe", function()
    local breakdown = item_detail.breakdown(nil, { value = 10, multiplier = 3, override = { value = 10 } })
    assert.are.same({ "fixed", 10, 10 }, { breakdown.kind, breakdown.fixed, breakdown.value })
    assert.are.same({}, breakdown.inputs)
  end)

  it("applies a mod's factor to the value of the recipe", function()
    local breakdown = item_detail.breakdown(gear, { value = 2.69 * 3, multiplier = 1, override = { factor = 3 } })
    assert.are.same({ "recipe", 3 }, { breakdown.kind, breakdown.factor })
    assert.is_true(near(2.69, breakdown.graph_value))
    assert.is_true(near(2.69 * 3, breakdown.value))
  end)

  it("multiplies the value of a quality by its ratio", function()
    local breakdown = item_detail.breakdown(gear, { value = 2.69, multiplier = 1, ratio = 9 })
    assert.are.same({ 9, 2.69 }, { breakdown.ratio, breakdown.normal_value })
    assert.is_true(near(2.69 * 9, breakdown.value))
  end)

  it("says when no source is known", function()
    assert.are.equal("unknown", item_detail.breakdown(nil, { value = 2, multiplier = 1 }).kind)
  end)
end)

describe("item_detail.quality_ladder", function()
  it("lists the qualities above normal by level, with their value ratio", function()
    local ladder = item_detail.quality_ladder({ normal = 0, rare = 2, uncommon = 1, legendary = 5, epic = 3 })
    assert.are.same({ "uncommon", "rare", "epic", "legendary" },
      { ladder[1].name, ladder[2].name, ladder[3].name, ladder[4].name })
    assert.are.same({ 3, 9, 27, 243 }, { ladder[1].ratio, ladder[2].ratio, ladder[3].ratio, ladder[4].ratio })
  end)

  it("is empty with normal quality only", function()
    assert.are.same({}, item_detail.quality_ladder({ normal = 0 }))
  end)
end)
