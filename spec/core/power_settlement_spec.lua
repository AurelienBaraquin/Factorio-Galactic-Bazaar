local settlement = require("scripts.core.power_settlement")

local MJ = 1e6

describe("power_settlement.export", function()
  it("sells everything the market takes, and keeps the rest pro rata", function()
    assert.are.same({ 20, 0 }, { settlement.export(20 * MJ, 100, MJ) })
    local units, kept = settlement.export(20 * MJ, 5, MJ)
    assert.are.equal(5, units)
    assert.are.equal(0.75, kept)
  end)

  it("sells nothing from empty buffers or at the price floor", function()
    assert.are.same({ 0, 1 }, { settlement.export(0, 100, MJ) })
    assert.are.same({ 0, 1 }, { settlement.export(20 * MJ, 0, MJ) })
  end)
end)

describe("power_settlement.wanted_units", function()
  it("asks for what the buffers lack, within the market's supply", function()
    assert.are.same({ 30, 30 * MJ }, { settlement.wanted_units({ 10 * MJ, 20 * MJ }, 1e9, MJ) })
    assert.are.equal(12, settlement.wanted_units({ 10 * MJ, 20 * MJ }, 12, MJ))
    assert.is_nil(settlement.wanted_units({ 0, 0 }, 1e9, MJ))
  end)
end)

describe("power_settlement.affordable", function()
  it("keeps the cost within the funds when the price rises with the units", function()
    local function cost(units) return 100 * (math.exp(units / 50) - 1) end
    local units = settlement.affordable(200, cost(200), 300)
    assert.is_true(units > 0 and cost(units) <= 300)
    assert.are.equal(200, settlement.affordable(200, 10, 300))
    assert.are.equal(0, settlement.affordable(200, 10, 0))
  end)

  it("affords nothing when the funds are negative (balance beyond the overdraft limit)", function()
    assert.are.equal(0, settlement.affordable(200, 10, -5))
    assert.are.equal(0, settlement.affordable(200, 0, -5))
  end)
end)

describe("power_settlement.shares", function()
  it("shares a limited purchase in proportion to what each buffer lacks", function()
    local shares = settlement.shares({ 10 * MJ, 30 * MJ }, 40 * MJ, 20, MJ)
    assert.are.same({ 5 * MJ, 15 * MJ }, shares)
  end)
end)
