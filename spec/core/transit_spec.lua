local transit = require("scripts.core.transit")

describe("transit", function()
  it("takes longer and risks more the farther the planet, within the cap", function()
    local near, far = transit.terms(1), transit.terms(4)
    assert.are.equal(transit.TICKS_PER_DISTANCE, near.delay_ticks)
    assert.are.equal(4 * transit.TICKS_PER_DISTANCE, far.delay_ticks)
    assert.are.near(0.02, near.max_loss, 1e-12)
    assert.are.near(0.08, far.max_loss, 1e-12)
    assert.are.equal(transit.MAX_LOSS, transit.terms(1000).max_loss)
  end)

  it("draws a loss within the terms, the same for the same seed", function()
    for seed = 1, 50 do
      local share = transit.loss_share(3, seed)
      assert.is_true(share > 0 and share <= transit.terms(3).max_loss)
      assert.are.equal(share, transit.loss_share(3, seed))
    end
    assert.are_not.equal(transit.loss_share(3, 1), transit.loss_share(3, 2))
  end)

  it("delivers whole units, rounded down", function()
    assert.are.equal(97, transit.arriving(100, 0.025))
    assert.are.equal(100, transit.arriving(100, 0))
    assert.are.equal(0, transit.arriving(1, 0.01))
  end)
end)
