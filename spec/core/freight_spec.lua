local freight = require("scripts.core.freight")

local tier = freight.TIERS.capsule
local STACK = 100
local PER_CAPSULE = STACK * tier.capacity_stacks

describe("freight.fee", function()
  it("is the tier's rate of the market cost", function()
    assert.are.equal(1000 * tier.fee_rate, freight.fee(1000, tier))
  end)
end)

describe("freight.schedule", function()
  it("launches a small order at once and lands it after the delay", function()
    local capsules, next_launch = freight.schedule(50, STACK, tier, 0, 0, 1000)
    assert.are.same({ { count = 50, arrival = 1000 + tier.delay_ticks } }, capsules)
    assert.are.equal(1000 + tier.launch_interval_ticks, next_launch)
  end)

  it("splits a large order into full capsules launched one interval apart", function()
    local capsules = freight.schedule(2 * PER_CAPSULE + 1, STACK, tier, 0, 0, 0)
    assert.are.equal(3, #capsules)
    assert.are.same({ PER_CAPSULE, PER_CAPSULE, 1 }, { capsules[1].count, capsules[2].count, capsules[3].count })
    assert.are.equal(tier.launch_interval_ticks, capsules[2].arrival - capsules[1].arrival)
    assert.are.equal(tier.launch_interval_ticks, capsules[3].arrival - capsules[2].arrival)
  end)

  it("waits for the hub's next free launch", function()
    local capsules, next_launch = freight.schedule(1, STACK, tier, 1, 5000, 1000)
    assert.are.equal(5000 + tier.delay_ticks, capsules[1].arrival)
    assert.are.equal(5000 + tier.launch_interval_ticks, next_launch)
  end)

  it("refuses orders beyond the queue bound and changes nothing", function()
    local max = freight.max_order(tier.max_capsules - 2, STACK, tier)
    assert.are.equal(2 * PER_CAPSULE, max)
    assert.is_truthy(freight.schedule(max, STACK, tier, tier.max_capsules - 2, 0, 0))
    local capsules, reason = freight.schedule(max + 1, STACK, tier, tier.max_capsules - 2, 0, 0)
    assert.is_nil(capsules)
    assert.are.equal("queue-full", reason)
    assert.are.equal(0, freight.max_order(tier.max_capsules + 1, STACK, tier))
  end)

  it("refuses a huge order without building its capsules", function()
    local capsules, reason = freight.schedule(1e12, STACK, tier, 0, 0, 0)
    assert.is_nil(capsules)
    assert.are.equal("queue-full", reason)
  end)

  it("fills capsules exactly at the capacity boundary", function()
    local capsules = freight.schedule(2 * PER_CAPSULE, STACK, tier, 0, 0, 0)
    assert.are.same({ PER_CAPSULE, PER_CAPSULE }, { capsules[1].count, capsules[2].count })
  end)

  it("refuses quantities that are not positive whole numbers", function()
    for _, units in ipairs({ 0, -1, 1.5, 0 / 0 }) do
      local capsules, reason = freight.schedule(units, STACK, tier, 0, 0, 0)
      assert.is_nil(capsules)
      assert.are.equal("invalid-quantity", reason)
    end
  end)
end)
