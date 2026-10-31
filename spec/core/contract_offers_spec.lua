local contract_offers = require("scripts.core.contract_offers")
local contracts = require("scripts.core.contracts")

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
    assert.are.near((2.69 - 2 * 1.32) * batch, spec.reward, 1e-9)
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
    local spec = contract_offers.offer(gear, rich, 0.5)
    assert.are.near(contract_offers.LABOR_SHARE * 10 * contract_offers.TARGET_VALUE / 10, spec.reward, 1e-9)
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
    assert.are.near(contract_offers.RENT_SHARE * 2.69 * 100, spec.reward, 1e-9)
    assert.is_true(spec.deposit + spec.penalty > 2.69 * 100)
    assert.are.equal(contract_offers.INSTALLMENT_TICKS, spec.installment_ticks)
    assert.is_truthy(contracts.new(spec, 0))
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
