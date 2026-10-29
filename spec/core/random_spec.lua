local random = require("scripts.core.random")

describe("random", function()
  it("produces the reference Park-Miller sequence", function()
    local state = random.seed(1)
    state = random.next(state)
    assert.are.equal(16807, state)
    for _ = 2, 10000 do state = random.next(state) end
    assert.are.equal(1043618065, state)
  end)

  it("draws numbers strictly between 0 and 1", function()
    local state = random.seed(42)
    for _ = 1, 1000 do
      local roll
      state, roll = random.next(state)
      assert.is_true(roll > 0 and roll < 1)
    end
  end)

  it("turns any seed into a valid state", function()
    assert.are.equal(1, random.seed(0))
    assert.are.equal(1, random.seed(2147483647))
    assert.are.equal(5, random.seed(-5.7))
  end)

  it("repeats the same sequence from the same state", function()
    local _, a = random.next(random.seed(7))
    local _, b = random.next(random.seed(7))
    assert.are.equal(a, b)
  end)
end)
