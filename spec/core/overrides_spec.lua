local overrides = require("scripts.core.overrides")
local valuation = require("scripts.core.valuation")

describe("overrides checks", function()
  it("accept numbers in range and explain the rest", function()
    assert.is_nil(overrides.check_value(2.5))
    assert.is_nil(overrides.check_factor(1))
    for _, bad in ipairs({ 0, -1, 0 / 0, math.huge, 1e300, 1e-9, "3", false }) do
      assert.is_string(overrides.check_value(bad))
    end
    assert.is_string(overrides.check_value(nil))
    assert.is_string(overrides.check_factor(nil))
    assert.is_string(overrides.check_factor(1e7))
  end)

  it("accept only entries with exactly one valid value or factor", function()
    assert.is_true(overrides.is_valid({ value = 3 }))
    assert.is_true(overrides.is_valid({ factor = 2 }))
    for _, bad in ipairs({ {}, { value = 3, factor = 2 }, { value = -1 }, { factor = 0 }, 5 }) do
      assert.is_false(overrides.is_valid(bad))
    end
  end)
end)

describe("overrides.fixed", function()
  local entries = { ["item/plate"] = { value = 10 }, ["item/gear"] = { factor = 2 } }

  it("fixes values from the main tier, divided by the multiplier, and needs a first pass for factors", function()
    assert.are.same({ ["item/plate"] = { value = 5, tier = valuation.MAIN } }, overrides.fixed(entries, 2))
    assert.is_true(overrides.has_factors(entries))
    assert.is_false(overrides.has_factors({ ["item/plate"] = { value = 1 } }))
  end)

  it("scales the first pass value of a key and keeps its tier", function()
    local first = { values = { ["item/gear"] = 3 }, tiers = { ["item/gear"] = valuation.NATURAL } }
    local fixed = overrides.fixed(entries, 1, first)
    assert.are.same({ value = 6, tier = valuation.NATURAL }, fixed["item/gear"])
  end)

  it("skips a factor whose key has no value", function()
    local fixed = overrides.fixed(entries, 1, { values = {}, tiers = {} })
    assert.is_nil(fixed["item/gear"])
  end)
end)

describe("overrides.apply_multiplier", function()
  it("scales every value except fixed ones, which stay exact, and keeps the floor", function()
    local values = { ["item/plate"] = 10 / 3, ["item/ore"] = 1, ["item/dust"] = 1e-6 }
    local scaled = overrides.apply_multiplier(values, { ["item/plate"] = { value = 10 } }, 0.01)
    assert.are.equal(10, scaled["item/plate"])
    assert.are.equal(0.01, scaled["item/ore"])
    assert.are.equal(valuation.MIN_VALUE, scaled["item/dust"])
    assert.are.equal(1, values["item/ore"])
  end)
end)
