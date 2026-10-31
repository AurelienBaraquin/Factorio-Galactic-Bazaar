local account = require("scripts.core.account")

local function new_account(balance)
  local state = { balance = balance }
  account.init(state)
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

  it("debits into the overdraft, down to the limit", function()
    local state = new_account(10)
    local limit = account.overdraft_limit(state)
    assert.is_true(account.apply(state, -(10 + limit), { tick = 1 }))
    assert.are.equal(-limit, state.balance)
  end)

  it("refuses to go below the overdraft limit and leaves the state untouched", function()
    local state = new_account(10)
    local ok, reason = account.apply(state, -(10.5 + account.overdraft_limit(state)), { tick = 1 })
    assert.is_false(ok)
    assert.are.equal("insufficient-funds", reason)
    assert.are.equal(10, state.balance)
    assert.are.same({}, state.journal)
  end)

  it("accepts a credit on a balance already beyond the limit", function()
    local state = new_account(-account.overdraft_limit({}) - 50)
    assert.is_true(account.apply(state, 20, { tick = 1 }))
    assert.are.equal(-account.overdraft_limit({}) - 30, state.balance)
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

describe("account.apply with recurring entries", function()
  local function entry(kind, tick, quantity)
    return { tick = tick, kind = kind, key = "energy/electricity", quantity = quantity, merge_ticks = 3600 }
  end

  it("merges into a recent entry of the same kind and key, keeping totals and the last balance", function()
    local state = { balance = 100, journal = {} }
    account.apply(state, 5, entry("sell", 0, 10))
    account.apply(state, -3, entry("buy", 300, 6))
    account.apply(state, 5, entry("sell", 300, 10))
    assert.are.equal(2, #state.journal)
    local sells = state.journal[2]
    assert.are.same({ 10, 20, 300, 107 }, { sells.amount, sells.quantity, sells.tick, sells.balance })
    assert.are.equal(107, state.balance)
  end)

  it("starts a new entry once the period is over", function()
    local state = { balance = 100, journal = {} }
    account.apply(state, 5, entry("sell", 0, 10))
    account.apply(state, 5, entry("sell", 3600, 10))
    assert.are.equal(2, #state.journal)
  end)

  it("keeps merging any number of recurring transactions, and keeps the journal in tick order", function()
    local state = { balance = 1000, journal = {} }
    for period = 0, 5 do
      for i = 1, 20 do
        local recurring = { tick = period * 600, kind = "buy", key = "item/" .. i, quantity = 1, merge_ticks = 3600 }
        account.apply(state, 1, recurring)
      end
    end
    assert.are.equal(20, #state.journal)
    assert.are.equal(6, state.journal[1].quantity)
    for i = 2, #state.journal do assert.is_true(state.journal[i - 1].tick <= state.journal[i].tick) end
  end)

  it("never merges an entry without merge_ticks", function()
    local state = { balance = 100, journal = {} }
    account.apply(state, 5, { tick = 0, kind = "sell", key = "energy/electricity" })
    account.apply(state, 5, { tick = 1, kind = "sell", key = "energy/electricity" })
    assert.are.equal(2, #state.journal)
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

describe("account overdraft", function()
  it("has a base limit", function()
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(new_account()))
    assert.is_true(account.BASE_OVERDRAFT_LIMIT > 0)
  end)

  it("makes the balance plus the limit available", function()
    local limit = account.BASE_OVERDRAFT_LIMIT
    assert.are.equal(250 + limit, account.available(new_account(250)))
    assert.are.equal(limit - 400, account.available(new_account(-400)))
    assert.are.equal(-30, account.available(new_account(-limit - 30)))
  end)

  it("tells how much of the overdraft is left", function()
    local limit = account.BASE_OVERDRAFT_LIMIT
    assert.are.equal(limit, account.overdraft_left(new_account(250)))
    assert.are.equal(limit - 400, account.overdraft_left(new_account(-400)))
    assert.are.equal(0, account.overdraft_left(new_account(-limit - 30)))
  end)
end)

describe("account.charge_interest", function()
  it("charges nothing on a balance at or above zero", function()
    for _, balance in ipairs({ 0, 120 }) do
      local state = new_account(balance)
      assert.are.equal(0, account.charge_interest(state, 3600))
      assert.are.equal(balance, state.balance)
      assert.are.same({}, state.journal)
    end
  end)

  it("charges the rate on a negative balance and journals it with its own kind", function()
    local state = new_account(-2000)
    local charged = account.charge_interest(state, 3600)
    assert.are.equal(2000 * account.INTEREST_RATE, charged)
    assert.are.equal(-2000 - charged, state.balance)
    local entry = state.journal[1]
    assert.are.same({ "overdraft-interest", -charged, 3600, state.balance },
      { entry.kind, entry.amount, entry.tick, entry.balance })
  end)

  it("may push the balance beyond the limit", function()
    local limit = account.BASE_OVERDRAFT_LIMIT
    local state = new_account(-limit)
    account.charge_interest(state, 3600)
    assert.is_true(state.balance < -limit)
    account.charge_interest(state, 7200)
    assert.is_true(state.balance < -limit * (1 + account.INTEREST_RATE))
  end)

  it("merges recurring interest into one journal entry over a while", function()
    local state = new_account(-1000)
    account.charge_interest(state, 3600)
    account.charge_interest(state, 7200)
    assert.are.equal(1, #state.journal)
    assert.is_true(math.abs(state.balance + 1000 - state.journal[1].amount) < 1e-9)
  end)
end)

describe("account.charge_interest over a period", function()
  it("charges the period's lowest balance, so a debt repaid before the minute still pays", function()
    local state = new_account(100)
    account.apply(state, -5000, { tick = 10 })
    account.apply(state, 5000, { tick = 20 })
    local charged = account.charge_interest(state, 3600)
    assert.is_true(math.abs(charged - 4900 * account.INTEREST_RATE) < 1e-9)
    assert.are.equal(0, account.charge_interest(state, 7200))
  end)

  it("charges at most the limit's interest, so a dormant debt grows linearly and stays finite", function()
    local limit = account.BASE_OVERDRAFT_LIMIT
    local state = new_account(-1e6)
    assert.are.equal(limit * account.INTEREST_RATE, account.charge_interest(state, 3600))
    state = new_account(-limit)
    local periods = 100000
    for period = 1, periods do account.charge_interest(state, period * 3600) end
    local expected = -limit - periods * limit * account.INTEREST_RATE
    assert.is_true(math.abs(state.balance - expected) < 1e-3)
  end)

  it("skips interest below a hundredth of a credit", function()
    local state = new_account(-0.5)
    assert.are.equal(0, account.charge_interest(state, 3600))
    assert.are.same({}, state.journal)
  end)

  it("gives a state saved before the overdraft its lowest balance", function()
    local state = { balance = -20, journal = {} }
    account.init(state)
    assert.are.equal(-20, state.overdraft_low)
  end)
end)

describe("account.merge of the lowest balances", function()
  it("adds the two lowest balances of the period", function()
    local destination, source = new_account(10), new_account(5)
    destination.overdraft_low, source.overdraft_low = -40, -60
    account.merge(destination, source)
    assert.are.equal(-100, destination.overdraft_low)
  end)
end)
