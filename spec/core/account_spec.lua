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
    local sells = state.journal[1]
    assert.are.same({ 10, 20, 300, 107 }, { sells.amount, sells.quantity, sells.tick, sells.balance })
    assert.are.equal(107, state.balance)
  end)

  it("starts a new entry once the period is over or the entry is too old", function()
    local state = { balance = 100, journal = {} }
    account.apply(state, 5, entry("sell", 0, 10))
    account.apply(state, 5, entry("sell", 3600, 10))
    assert.are.equal(2, #state.journal)
    for _ = 1, account.MERGE_WINDOW do account.apply(state, 1, { tick = 3700, kind = "sell", key = "item/x" }) end
    account.apply(state, 5, entry("sell", 3800, 10))
    assert.are.equal(3 + account.MERGE_WINDOW, #state.journal)
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
