local account = require("scripts.core.account")

local function new_account(balance)
  local state = {}
  account.init(state)
  state.balance = balance or 0
  return state
end

describe("account.apply", function()
  it("credits and debits, recording each entry with its amount and resulting balance", function()
    local state = new_account()
    assert.is_true(account.apply(state, 100, { tick = 1, kind = "sell" }))
    assert.is_true(account.apply(state, -30, { tick = 2, kind = "buy" }))
    assert.are.equal(70, state.balance)
    assert.are.same({ tick = 2, kind = "buy", amount = -30, balance = 70 }, state.journal[2])
  end)

  it("refuses to go below zero and leaves the state untouched", function()
    local state = new_account(10)
    local ok, reason = account.apply(state, -10.5, { tick = 1 })
    assert.is_false(ok)
    assert.are.equal("insufficient-funds", reason)
    assert.are.equal(10, state.balance)
    assert.are.same({}, state.journal)
  end)

  it("refuses NaN and infinite amounts", function()
    local state = new_account(10)
    for _, amount in ipairs({ 0 / 0, math.huge, -math.huge }) do
      local ok, reason = account.apply(state, amount, {})
      assert.is_false(ok)
      assert.are.equal("invalid-amount", reason)
    end
    assert.are.equal(10, state.balance)
  end)

  it("keeps only the newest entries", function()
    local state = new_account()
    for tick = 1, account.JOURNAL_SIZE + 5 do account.apply(state, 1, { tick = tick }) end
    assert.are.equal(account.JOURNAL_SIZE, #state.journal)
    assert.are.equal(6, state.journal[1].tick)
    assert.are.equal(account.JOURNAL_SIZE + 5, state.balance)
  end)
end)

describe("account.merge", function()
  it("adds balances and joins journals in tick order", function()
    local destination = new_account(5)
    destination.journal = { { tick = 1 }, { tick = 4 } }
    local source = new_account(7)
    source.journal = { { tick = 2 }, { tick = 3 } }
    account.merge(destination, source)
    assert.are.equal(12, destination.balance)
    assert.are.same({ { tick = 1 }, { tick = 2 }, { tick = 3 }, { tick = 4 } }, destination.journal)
  end)
end)
