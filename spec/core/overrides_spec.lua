local overrides = require("scripts.core.overrides")

describe("overrides.check_number", function()
  it("accepts positive finite numbers and explains the rest", function()
    assert.is_nil(overrides.check_number(2.5))
    for _, bad in ipairs({ 0, -1, 0 / 0, math.huge, "3" }) do
      assert.is_string(overrides.check_number(bad))
    end
  end)
end)

describe("overrides.fixed", function()
  local entries = { ["item/plate"] = { value = 10 }, ["item/gear"] = { factor = 2 } }

  it("divides fixed values by the multiplier and ignores factors without a first pass", function()
    assert.are.same({ ["item/plate"] = 5 }, overrides.fixed(entries, 2))
    assert.is_true(overrides.has_factors(entries))
    assert.is_false(overrides.has_factors({ ["item/plate"] = { value = 1 } }))
  end)

  it("scales the first pass value of a key by its factor", function()
    local fixed = overrides.fixed(entries, 1, { ["item/gear"] = 3 })
    assert.are.same({ ["item/plate"] = 10, ["item/gear"] = 6 }, fixed)
  end)

  it("skips a factor whose key has no value", function()
    assert.are.same({ ["item/plate"] = 10 }, overrides.fixed(entries, 1, {}))
  end)
end)

describe("overrides.apply_multiplier", function()
  it("scales every value except fixed ones, which stay exact", function()
    local values = { ["item/plate"] = 10 / 3, ["item/ore"] = 1 }
    local scaled = overrides.apply_multiplier(values, { ["item/plate"] = { value = 10 } }, 3)
    assert.are.equal(10, scaled["item/plate"])
    assert.are.equal(3, scaled["item/ore"])
    assert.are.equal(1, values["item/ore"])
  end)
end)
