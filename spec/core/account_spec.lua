local account = require("scripts.core.account")

local function new_account(balance)
  local state = { balance = balance }
  account.init(state)
  return state
end

describe("account.apply", function()
  it("sends a credit to a bankruptcy debt first, journaled, and keeps only the rest", function()
    local state = new_account(0)
    state.bankruptcy_debt = 300
    assert.is_true(account.apply(state, 500, { tick = 1, kind = "sell" }))
    assert.are.same({ 200, 0 }, { state.balance, state.bankruptcy_debt })
    assert.are.same({ "sell", 500 }, { state.journal[1].kind, state.journal[1].amount })
    assert.are.same({ account.DEBT_KIND, -300 }, { state.journal[2].kind, state.journal[2].amount })
    assert.are.same({ income = 0, spending = 300, count = 1 }, state.ledger.total.bankruptcy)
    assert.are.same({ income = 500, spending = 0, count = 1 }, state.ledger.total.sales)
    assert.is_true(account.apply(state, -50, { tick = 2, kind = "buy" }))
    assert.are.equal(150, state.balance)
  end)

  it("lets a credit bring a negative balance back to zero before it pays a bankruptcy debt", function()
    local state = new_account(-100)
    state.bankruptcy_debt = 300
    assert.is_true(account.apply(state, 250, { tick = 1, kind = "sell" }))
    assert.are.same({ 0, 150 }, { state.balance, state.bankruptcy_debt })
  end)

  it("credits and debits, recording each entry with its amount and resulting balance", function()
    local state = new_account()
    assert.is_true(account.apply(state, 100, { tick = 1, kind = "sell" }))
    assert.is_true(account.apply(state, -30, { tick = 2, kind = "buy" }))
    assert.are.equal(70, state.balance)
    assert.are.same({ tick = 2, kind = "buy", amount = -30, balance = 70, category = "purchases" }, state.journal[2])
  end)

  it("counts every transaction in the ledger, merged into one journal entry or not", function()
    local state = new_account()
    account.apply(state, 10, { tick = 1, kind = "sell", key = "item/a", merge_ticks = 3600 })
    account.apply(state, 15, { tick = 2, kind = "sell", key = "item/a", merge_ticks = 3600 })
    account.apply(state, -4, { tick = 3, kind = "buy", key = "item/a" })
    assert.are.equal(2, #state.journal)
    assert.are.same({ income = 25, spending = 0, count = 2 }, state.ledger.total.sales)
    assert.are.same({ income = 0, spending = 4, count = 1 }, state.ledger.minutes[0].purchases)
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
    assert.is_nil(state.ledger)
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
    assert.is_nil(state.ledger)
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

describe("account.apply finding the entry to merge into", function()
  local function sale(tick, key, merge_ticks)
    return { tick = tick, kind = "sell", key = key, quantity = 1, merge_ticks = merge_ticks or 3600 }
  end

  -- The journal as account.apply recorded it, without the statement category.
  local function fields(journal)
    local copy = {}
    for i, entry in ipairs(journal) do
      copy[i] = { entry.kind, entry.key, entry.amount, entry.quantity, entry.tick, entry.balance, entry.first_tick }
    end
    return copy
  end

  -- What the journal held before the index (#121): every entry searched for one to merge into.
  local function reference_apply(state, size, amount, entry)
    local balance = state.balance + amount
    state.balance = balance
    local journal = state.journal
    for i = #journal, 1, -1 do
      local candidate = journal[i]
      if entry.merge_ticks and candidate.merge_ticks and candidate.kind == entry.kind and candidate.key == entry.key
        and entry.tick - candidate.first_tick < entry.merge_ticks then
        local target = table.remove(journal, i)
        journal[#journal + 1] = target
        target.amount, target.quantity = target.amount + amount, (target.quantity or 0) + (entry.quantity or 0)
        target.tick, target.balance = entry.tick, balance
        return
      end
    end
    entry.amount, entry.balance = amount, balance
    entry.first_tick = entry.merge_ticks and entry.tick or nil
    journal[#journal + 1] = entry
    while #journal > size do table.remove(journal, 1) end
  end

  local saved_size
  before_each(function() saved_size = account.JOURNAL_SIZE end)
  after_each(function() account.JOURNAL_SIZE = saved_size end)

  it("merges as a search of the whole journal would, while entries come and go", function()
    account.JOURNAL_SIZE = 25
    local state, reference = new_account(0), { balance = 0, journal = {} }
    local seed, tick = 7, 0
    for _ = 1, 3000 do
      seed = (seed * 16807) % 2147483647
      tick = tick + seed % 40
      local key = "item/" .. seed % 30
      local entry = { tick = tick, kind = seed % 3 == 0 and "buy" or "sell", key = key, quantity = seed % 5,
        merge_ticks = seed % 7 ~= 0 and (seed % 2 == 0 and 600 or 300) or nil }
      local copy = {}
      for field, value in pairs(entry) do copy[field] = value end
      account.apply(state, seed % 100, entry)
      reference_apply(reference, account.JOURNAL_SIZE, seed % 100, copy)
    end
    assert.are.same(fields(reference.journal), fields(state.journal))
  end)

  it("merges into a journal saved before the index, or replaced whole", function()
    local state = new_account(0)
    state.journal = { { tick = 10, kind = "sell", key = "item/a", quantity = 1, amount = 1, balance = 1,
      first_tick = 10, merge_ticks = 3600 } }
    account.apply(state, 2, sale(20, "item/a"))
    assert.are.same({ 1, 2, 3 }, { #state.journal, state.journal[1].quantity, state.journal[1].amount })
    state.journal = { { tick = 30, kind = "sell", key = "item/a", quantity = 4, amount = 4, balance = 4,
      first_tick = 30, merge_ticks = 3600 } }
    account.apply(state, 1, sale(40, "item/a"))
    assert.are.same({ 1, 5 }, { #state.journal, state.journal[1].quantity })
  end)

  it("never merges into an entry the journal dropped", function()
    account.JOURNAL_SIZE = 3
    local state = new_account(0)
    account.apply(state, 1, sale(1, "item/a"))
    for tick = 2, 4 do account.apply(state, 1, { tick = tick, kind = "buy", key = "item/b" }) end
    account.apply(state, 1, sale(5, "item/a"))
    assert.are.same({ "buy", "buy", "sell" }, { state.journal[1].kind, state.journal[2].kind, state.journal[3].kind })
    assert.are.same({ 5, 1 }, { state.journal[3].first_tick, state.journal[3].quantity })
  end)

  it("merges into the entry that started last once two forces merged", function()
    local destination, source = new_account(0), new_account(0)
    account.apply(destination, 1, sale(100, "item/a"))
    account.apply(destination, 1, sale(3000, "item/a"))
    account.apply(source, 1, sale(2000, "item/a"))
    account.apply(source, 1, sale(2500, "item/a"))
    account.merge(destination, source)
    -- In tick order the destination's entry (started at 100) is last, but its period is over at 3700.
    account.apply(destination, 1, sale(3700, "item/a"))
    assert.are.equal(2, #destination.journal)
    assert.are.same({ 2000, 3, 3700 }, { destination.journal[2].first_tick, destination.journal[2].quantity,
      destination.journal[2].tick })
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

  it("folds the ledgers together", function()
    local destination, source = new_account(100), new_account(100)
    account.apply(destination, -10, { tick = 5, kind = "buy", key = "item/a" })
    account.apply(source, -20, { tick = 3, kind = "buy", key = "item/a" })
    account.merge(destination, source)
    assert.are.same({ 3, 30, 2 }, { destination.ledger.start_tick, destination.ledger.total.purchases.spending,
      destination.ledger.total.purchases.count })
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

describe("account overdraft research levels", function()
  local function at_level(balance, level)
    local state = new_account(balance)
    state.overdraft_level = level
    return state
  end

  it("keeps the base limit at level 0 and for a state saved before the levels", function()
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(at_level(0, 0)))
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(at_level(0, nil)))
  end)

  it("raises the limit at each level, never below the one before", function()
    local previous = account.BASE_OVERDRAFT_LIMIT
    for level, limit in ipairs(account.OVERDRAFT_LEVEL_LIMITS) do
      assert.are.equal(limit, account.overdraft_limit(at_level(0, level)))
      assert.is_true(limit > previous)
      previous = limit
    end
  end)

  it("scales a level's extra over the base by reputation, never above the full extra", function()
    local base = account.BASE_OVERDRAFT_LIMIT
    for level, limit in ipairs(account.OVERDRAFT_LEVEL_LIMITS) do
      local expected = { [-20] = base + (limit - base) * 0.5, [0] = limit, [20] = limit }
      for score, wanted in pairs(expected) do
        local state = at_level(0, level)
        state.reputation = score
        assert.are.equal(wanted, account.overdraft_limit(state))
      end
    end
  end)

  it("never scales the base limit by reputation", function()
    for _, score in ipairs({ -20, 0, 20 }) do
      local state = at_level(0, 0)
      state.reputation = score
      assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state))
    end
  end)

  it("holds the highest limit beyond the last level", function()
    local levels = #account.OVERDRAFT_LEVEL_LIMITS
    assert.are.equal(account.OVERDRAFT_LEVEL_LIMITS[levels], account.overdraft_limit(at_level(0, levels + 3)))
  end)

  it("lets a raised level spend further and pay interest on a deeper debt", function()
    local raised = account.OVERDRAFT_LEVEL_LIMITS[1]
    local state = at_level(0, 1)
    assert.are.equal(raised, account.available(state))
    assert.is_true(account.apply(state, -raised, { tick = 1 }))
    assert.are.same({ false, "insufficient-funds" }, { account.apply(state, -1, { tick = 2 }) })
    assert.are.equal(raised * account.INTEREST_RATE, account.charge_interest(state, 3600))
  end)

  it("leaves a balance beyond a lowered limit owing, with nothing more to spend", function()
    local state = at_level(-account.OVERDRAFT_LEVEL_LIMITS[1], 1)
    state.overdraft_level = 0
    assert.is_true(account.available(state) < 0)
    assert.are.equal(0, account.overdraft_left(state))
    assert.are.same({ false, "insufficient-funds" }, { account.apply(state, -1, { tick = 1 }) })
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
    assert.are.same({ income = 0, spending = charged, count = 1 }, state.ledger.minutes[1].interest)
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

describe("account.interest_due", function()
  it("is what the next charge would take, without changing the state", function()
    local state = new_account(100)
    account.apply(state, -2100, { tick = 10 })
    account.apply(state, 1500, { tick = 20 })
    local due = account.interest_due(state)
    assert.is_true(math.abs(due - 2000 * account.INTEREST_RATE) < 1e-9)
    assert.are.same({ -500, -2000, 2 }, { state.balance, state.overdraft_low, #state.journal })
    assert.are.equal(due, account.charge_interest(state, 3600))
  end)

  it("is 0 without debt in the period, or under the waived minimum", function()
    assert.are.equal(0, account.interest_due(new_account(0)))
    assert.are.equal(0, account.interest_due(new_account(-0.5)))
  end)

  it("counts the debt up to the overdraft limit", function()
    local limit = account.BASE_OVERDRAFT_LIMIT
    assert.are.equal(limit * account.INTEREST_RATE, account.interest_due(new_account(-1e6)))
  end)
end)
