local contract_offers = require("scripts.core.contract_offers")
local contracts = require("scripts.core.contracts")
local market = require("scripts.core.market")

local gear = {
  energy = 0.5,
  ingredients = { { kind = "item", name = "iron-plate", count = 2 } },
  products = { { kind = "item", name = "iron-gear-wheel", count = 1 } },
}
local values = { ["item/iron-plate"] = 1.32, ["item/iron-gear-wheel"] = 2.69 }

describe("contract_offers.offer", function()
  it("sizes a batch to the target value and prices work, deposit and penalty", function()
    local spec = contract_offers.offer(gear, values, 0.5)
    local batch = math.ceil(contract_offers.TARGET_VALUE / 2.69)
    assert.are.same({ { kind = "item", name = "iron-plate", count = 2 * batch } }, spec.provides)
    assert.are.same({ { kind = "item", name = "iron-gear-wheel", count = batch } }, spec.requires)
    local margin = contract_offers.SPREAD_SHARE * market.DEFAULTS.spread / 2 * (2.69 + 2 * 1.32)
    assert.are.near((2.69 - 2 * 1.32 + margin) * batch, spec.reward, 1e-9)
    assert.is_true(spec.deposit + spec.penalty > 1.32 * 2 * batch)
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("makes failing cost more than the ingredients are worth", function()
    local spec = contract_offers.offer(gear, values, 0.1)
    local provided = 0
    for _, goods in ipairs(spec.provides) do provided = provided + values["item/" .. goods.name] * goods.count end
    assert.is_true(spec.deposit + spec.penalty > provided)
  end)

  it("pays at most the labour share of the products' value", function()
    local rich = { ["item/iron-plate"] = 1, ["item/iron-gear-wheel"] = 10 }
    local slow = { energy = 100, ingredients = gear.ingredients, products = gear.products }
    local spec = contract_offers.offer(slow, rich, 0.5)
    assert.are.near(contract_offers.LABOR_SHARE * 10 * contract_offers.TARGET_VALUE / 10, spec.reward, 1e-9)
  end)

  it("pays at most the work: a rate per second of crafting at speed 1", function()
    local rich = { ["item/iron-plate"] = 1, ["item/iron-gear-wheel"] = 10 }
    local spec = contract_offers.offer(gear, rich, 0.5)
    local batch = spec.requires[1].count
    assert.are.near(contract_offers.REWARD_PER_CRAFT_SECOND * 0.5 * batch, spec.reward, 1e-9)
    assert.is_true(contract_offers.REWARD_PER_CRAFT_SECOND >= 2 * contract_offers.RENT_PER_SECOND)
  end)

  it("keeps a share of the spread as a margin: the reward never reaches the round trip's loss at base "
    .. "prices", function()
    assert.is_true(contract_offers.SPREAD_SHARE > 0 and contract_offers.SPREAD_SHARE < 1)
    local half_spread = market.DEFAULTS.spread / 2
    for _, plate in ipairs({ 0.5, 1, 1.3, 1.34, 2, 4.9 }) do
      for _, energy in ipairs({ 0.1, 0.5, 5, 100 }) do
        local recipe = { energy = energy, ingredients = gear.ingredients, products = gear.products }
        local spec = contract_offers.offer(recipe, { ["item/iron-plate"] = plate, ["item/iron-gear-wheel"] = 10 }, 0.5)
        local batch = spec.requires[1].count
        local p, i = 10 * batch, 2 * plate * batch
        local margin = (1 - contract_offers.SPREAD_SHARE) * half_spread * (p + i)
        assert.is_true(spec.reward <= p - i + half_spread * (p + i) - margin + 1e-9)
      end
    end
  end)

  it("pays the value crafting adds and a share of the spread, less than buying the products and selling the "
    .. "ingredients loses on a balanced market", function()
    local spec = contract_offers.offer(gear, values, 0.5)
    local provided = 1.32 * spec.provides[1].count
    local required = 2.69 * spec.requires[1].count
    local half_spread = market.DEFAULTS.spread / 2
    local loss = (1 + half_spread) * required - (1 - half_spread) * provided
    assert.is_true(spec.reward > required - provided)
    assert.is_true(spec.reward < loss)
  end)

  it("refuses a recipe whose ingredients are worth as much as its products", function()
    assert.is_nil(contract_offers.offer(gear, { ["item/iron-plate"] = 1.5, ["item/iron-gear-wheel"] = 3 }, 0.5))
    assert.is_nil(contract_offers.offer(gear, { ["item/iron-plate"] = 2, ["item/iron-gear-wheel"] = 3 }, 0.5))
  end)

  it("scales the batch with the force's reputation", function()
    local rich = { ["item/iron-plate"] = 1, ["item/iron-gear-wheel"] = 10 }
    local plain = contract_offers.offer(gear, rich, 0.5)
    local larger = contract_offers.offer(gear, rich, 0.5, 3)
    assert.are.equal(3 * plain.requires[1].count, larger.requires[1].count)
    assert.are.near(3 * plain.reward, larger.reward, 1e-9)
  end)

  it("refuses a recipe with a good that has no value", function()
    assert.is_nil(contract_offers.offer(gear, { ["item/iron-gear-wheel"] = 2 }, 0.5))
  end)

  it("picks a counterparty and a recipe from a draw", function()
    assert.are.equal(contract_offers.COUNTERPARTIES[1], contract_offers.offer(gear, values, 0).counterparty)
    assert.are.equal("b", contract_offers.pick({ "a", "b" }, 0.99))
    assert.is_nil(contract_offers.pick({}, 0.5))
  end)
end)

describe("contract_offers.viable", function()
  it("keeps only the recipes an offer can be made of, in their order", function()
    local dead = { name = "dead", energy = 1, ingredients = { { kind = "item", name = "iron-gear-wheel", count = 2 } },
      products = { { kind = "item", name = "iron-plate", count = 1 } } }
    local list = contract_offers.viable({ dead, gear, dead }, values)
    assert.are.same({ gear }, list)
  end)

  it("never lets a short but dead recipe take the shortage's offers", function()
    local dead = { name = "dead", energy = 1, ingredients = { { kind = "item", name = "iron-gear-wheel", count = 2 } },
      products = { { kind = "item", name = "iron-plate", count = 1 } } }
    local function depths(key) return key == "item/iron-plate" and -1 or 0 end
    local picked = contract_offers.pick_short(contract_offers.viable({ dead, gear }, values), depths, 0, 0.01)
    assert.are.equal(gear, picked)
  end)
end)

describe("contract_offers.pick_short", function()
  local candidates = {
    { name = "a", products = { { kind = "item", name = "a", count = 1 } } },
    { name = "b", products = { { kind = "item", name = "b", count = 1 } } },
    { name = "c", products = { { kind = "item", name = "c", count = 1 } } },
  }
  local shifts = { ["item/b"] = -0.5, ["item/c"] = -0.05 }
  local function depths(key) return shifts[key] or 0 end

  it("names a recipe making goods in shortage with the shortage chance", function()
    local below = contract_offers.SHORTAGE_CHANCE / 2
    for _, draw in ipairs({ 0.01, 0.5, 0.99 }) do
      assert.are.equal("b", contract_offers.pick_short(candidates, depths, below, draw).name)
    end
  end)

  it("draws among every recipe otherwise, or when no product is short enough", function()
    local above = (1 + contract_offers.SHORTAGE_CHANCE) / 2
    assert.are.equal("a", contract_offers.pick_short(candidates, depths, above, 0.01).name)
    assert.are.equal("c", contract_offers.pick_short(candidates, depths, above, 0.99).name)
    local none = function() return -contract_offers.SHORTAGE_DEPTHS / 2 end
    assert.are.equal("a", contract_offers.pick_short(candidates, none, 0, 0.01).name)
    assert.is_nil(contract_offers.pick_short({}, depths, 0, 0.5))
  end)
end)

describe("contract_offers.rental", function()
  it("promises a share of the machine's nominal crafts over the rental", function()
    local seconds = contract_offers.RENTAL_TICKS / 60
    assert.are.equal(math.floor(0.8 * 0.75 * seconds / 0.5), contract_offers.rental_crafts(0.5, 0.75))
    assert.are.equal(0, contract_offers.rental_crafts(1e9, 0.75))
  end)

  it("pays rent in installments and guarantees more than the products are worth", function()
    local spec = contract_offers.rental(gear, values, 0.5, 100)
    assert.are.same({ { kind = "item", name = "iron-plate", count = 200 } }, spec.provides)
    assert.are.same({ { kind = "item", name = "iron-gear-wheel", count = 100 } }, spec.requires)
    assert.are.near(contract_offers.RENT_PER_SECOND * 0.5 * 100, spec.reward, 1e-9)
    assert.is_true(spec.deposit + spec.penalty > 2.69 * 100)
    assert.are.equal(contract_offers.INSTALLMENT_TICKS, spec.installment_ticks)
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("pays the machine's time, whatever the recipe's products are worth", function()
    local cheap = contract_offers.rental(gear, values, 0.5, 100)
    local dear = contract_offers.rental(gear, { ["item/iron-plate"] = 1000, ["item/iron-gear-wheel"] = 5000 }, 0.5, 100)
    assert.are.equal(cheap.reward, dear.reward)
    assert.is_true(dear.deposit + dear.penalty > 5000 * 100)
  end)

  it("earns no reputation: the counterparty supplies everything, the machine only runs", function()
    assert.is_true(contract_offers.rental(gear, values, 0.5, 100).passive)
    assert.is_nil(contract_offers.offer(gear, values, 0.5).passive)
  end)

  it("guarantees the ingredients when they are worth more than the products", function()
    local spec = contract_offers.rental(gear, { ["item/iron-plate"] = 5, ["item/iron-gear-wheel"] = 2 }, 0.5, 10)
    assert.is_true(spec.deposit + spec.penalty > 5 * 2 * 10)
  end)

  it("refuses an offer without a craft or without values", function()
    assert.is_nil(contract_offers.rental(gear, values, 0.5, 0))
    assert.is_nil(contract_offers.rental(gear, { ["item/iron-gear-wheel"] = 2 }, 0.5, 10))
  end)
end)

describe("contract_offers.concession", function()
  it("ships a slot's units every period, charged at their value, guaranteed by one period", function()
    local spec = contract_offers.concession("carbo", "coal", 2, 3)
    local units = 3 * contract_offers.UNITS_PER_SLOT_MINUTE * 5
    assert.are.equal(units, contract_offers.concession_units(3))
    assert.are.equal(units * 6, spec.provides[1].count)
    assert.are.near(units * 2, spec.charge, 1e-9)
    assert.are.equal(spec.charge, spec.deposit)
    assert.is_truthy(contracts.new(spec, 0))
    assert.is_nil(contract_offers.concession("carbo", "coal", nil, 1))
  end)
end)

describe("contract_offers.outsourcing", function()
  it("ships the whole crafts a slot makes at crafting speed 1, charged at the products' value", function()
    local spec = contract_offers.outsourcing("fabrica-nova", { energy = 0.5, product = "iron-gear-wheel", amount = 1 },
      2.69, 1)
    assert.are.equal(600, contract_offers.outsourcing_units(0.5, 1, 1))
    assert.are.equal("outsourcing", spec.kind)
    assert.are.equal(600 * 6, spec.provides[1].count)
    assert.are.near(600 * 2.69 * contract_offers.OUTSOURCING_PRICE, spec.charge, 1e-9)
    assert.are.equal(15, contract_offers.outsourcing_units(20, 1, 1))
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("refuses a recipe too slow for one craft a period, or without value", function()
    assert.are.equal(0, contract_offers.outsourcing_units(301, 1, 1))
    assert.is_nil(contract_offers.outsourcing("x", { energy = 301, product = "a", amount = 1 }, 5, 1))
    assert.is_nil(contract_offers.outsourcing("x", { energy = 1, product = "a", amount = 1 }, nil, 1))
  end)
end)
