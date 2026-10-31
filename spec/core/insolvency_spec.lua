local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")
local insolvency = require("scripts.core.insolvency")
local loans = require("scripts.core.loans")
local reputation = require("scripts.core.reputation")

-- A force state with `balance` and `arrears`, its account, book and insolvency fields set.
local function new_state(balance, arrears)
  local state = { balance = balance or 0, arrears = arrears or 0 }
  account.init(state)
  contracts.init_book(state)
  insolvency.init(state)
  return state
end

local function names(events)
  local list = {}
  for _, event in ipairs(events) do list[#list + 1] = event.name end
  return list
end

-- The balance at which a force has `available` funds, overdraft included.
local function funds(state, available) return available - account.overdraft_limit(state) end

describe("insolvency.check", function()
  it("leaves a force within its overdraft and owing no arrears alone", function()
    local state = new_state(-account.BASE_OVERDRAFT_LIMIT)
    assert.are.same({}, insolvency.check(state, 60))
    assert.is_nil(state.insolvent_since)
  end)

  it("makes a force insolvent once its balance is beyond the overdraft limit", function()
    local state = new_state()
    state.balance = funds(state, -1)
    assert.are.same({ "insolvent" }, names(insolvency.check(state, 120)))
    assert.are.equal(120, state.insolvent_since)
    assert.is_true(insolvency.insolvent(state))
    assert.are.same({}, insolvency.check(state, 180))
    assert.are.equal(120, state.insolvent_since)
  end)

  it("makes a force insolvent when it owes arrears its available funds cannot cover", function()
    local state = new_state(0, 50000)
    assert.are.same({ "insolvent" }, names(insolvency.check(state, 60)))
  end)

  it("leaves a force alone whose available funds cover its arrears", function()
    local state = new_state(0, 500)
    assert.are.same({}, insolvency.check(state, 60))
  end)

  it("sees a dip beyond the limit between two checks, through the low-water mark", function()
    local state = new_state(0)
    insolvency.check(state, 60)
    assert.is_true(account.apply(state, -account.overdraft_limit(state), { tick = 61 }))
    state.balance = state.balance - 1 -- interest beyond the limit
    state.solvency_low = math.min(state.solvency_low, state.balance)
    assert.is_true(account.apply(state, 5000, { tick = 62 }))
    assert.are.same({ "insolvent" }, names(insolvency.check(state, 120)))
  end)

  -- Checks `state` every CHECK_TICKS from `from` to `to`; returns the names of every event.
  local function run(state, from, to)
    local all = {}
    for tick = from, to, insolvency.CHECK_TICKS do
      for _, name in ipairs(names(insolvency.check(state, tick))) do all[#all + 1] = name end
    end
    return all
  end

  it("ends insolvency only once the funds stayed above the recovery margin for an interest period", function()
    local state = new_state()
    state.balance = funds(state, -100)
    insolvency.check(state, 60)
    assert.is_true(account.apply(state, 100, { tick = 70 }))
    assert.are.same({}, insolvency.check(state, 120))
    -- A whole period at exactly the limit is not enough: a recovery needs the margin. Reaching it just
    -- before the check is not enough either: the period's lowest point was still short.
    assert.is_true(account.apply(state, insolvency.recovery_margin(state), { tick = 179 }))
    assert.are.same({}, insolvency.check(state, 180))
    assert.are.same({}, run(state, 240, 240 + insolvency.RECOVERY_TICKS - 60))
    assert.are.same({ "recovered" }, names(insolvency.check(state, 240 + insolvency.RECOVERY_TICKS)))
    assert.is_nil(state.insolvent_since)
    assert.is_nil(state.recovering_since)
  end)

  it("restarts the recovery of a force that dips under the margin, telling it nothing until it holds", function()
    local state = new_state()
    state.balance = funds(state, -100)
    insolvency.check(state, 60)
    state.balance = funds(state, insolvency.recovery_margin(state))
    assert.are.same({}, run(state, 120, 1800))
    -- Interest takes it under the margin once, then income brings it back.
    state.balance = state.balance - 50
    assert.are.same({}, insolvency.check(state, 1860))
    assert.is_nil(state.recovering_since)
    state.balance = state.balance + 50
    -- The period ending at 1920 still saw the dip: the recovery restarts at 1980.
    assert.are.same({}, run(state, 1920, 1980 + insolvency.RECOVERY_TICKS - 60))
    assert.are.same({ "recovered" }, names(insolvency.check(state, 1980 + insolvency.RECOVERY_TICKS)))
  end)

  it("does not let a brief recovery at the check tick restart the clock", function()
    local state = new_state()
    state.balance = funds(state, -100)
    insolvency.check(state, 60)
    for tick = 120, 60 + insolvency.GRACE_TICKS - 60, 60 do
      -- Income at the check, gone again before the next one.
      assert.is_true(account.apply(state, 10000, { tick = tick - 1 }))
      insolvency.check(state, tick)
      -- Spent again down to the limit, then pushed beyond it by interest.
      assert.is_true(account.apply(state, -9900, { tick = tick + 1 }))
      state.balance, state.solvency_low = state.balance - 100, state.balance - 100
    end
    assert.are.equal(60, state.insolvent_since)
    assert.are.same({ "bankrupt" }, names(insolvency.check(state, 60 + insolvency.GRACE_TICKS)))
  end)

  it("starts the grace period, never a bankruptcy, when the limit drops under an existing debt", function()
    local state = new_state(-5000)
    assert.are.same({}, insolvency.check(state, 60))
    local real_limit = account.overdraft_limit
    account.overdraft_limit = function() return 2000 end
    local events = insolvency.check(state, 120)
    local later = insolvency.check(state, 120 + insolvency.GRACE_TICKS - 60)
    account.overdraft_limit = real_limit
    assert.are.same({ "insolvent" }, names(events))
    assert.are.equal(120, state.insolvent_since)
    assert.are.same({}, later)
    local from = 180 + insolvency.GRACE_TICKS
    assert.are.same({ "recovered" }, run(state, from, from + insolvency.RECOVERY_TICKS))
  end)

  it("keeps an insolvent force with arrears insolvent until they are paid", function()
    local state = new_state(0, 50000)
    insolvency.check(state, 60)
    state.balance = 100000
    assert.are.same({}, insolvency.check(state, 120))
    assert.is_nil(state.recovering_since)
    state.arrears = 0
    assert.are.same({ "recovered" }, run(state, 180, 180 + insolvency.RECOVERY_TICKS))
  end)

  it("bankrupts a force still insolvent at the end of the grace period, not one tick earlier", function()
    local state = new_state()
    state.balance = funds(state, -1)
    insolvency.check(state, 60)
    assert.are.same({}, insolvency.check(state, 60 + insolvency.GRACE_TICKS - 1))
    local events = insolvency.check(state, 60 + insolvency.GRACE_TICKS)
    assert.are.same({ "bankrupt" }, names(events))
  end)
end)

describe("insolvency.bankrupt", function()
  local function book(state)
    local offered = contracts.new({
      kind = "incoming", counterparty = "c", provides = {}, requires = { { kind = "item", name = "gear", count = 5 } },
      reward = 10, deposit = 5, penalty = 5, duration_ticks = 600, accept_ticks = 600,
    }, 0)
    contracts.file(state, offered, 1)
    local loan = contracts.new(loans.spec(5000, 0), 0)
    contracts.accept(loan, 0)
    contracts.file(state, loan, 2)
    return offered, loan
  end

  local function entries(state, kind)
    local found = {}
    for _, entry in ipairs(state.journal) do
      if entry.kind == kind then found[#found + 1] = entry end
    end
    return found
  end

  local SURCHARGED = 1 + insolvency.RESTRUCTURING_SURCHARGE

  it("ends contracts and moves everything owed, loans included, into a frozen debt with a surcharge", function()
    local state = new_state(-12000, 3000)
    state.reputation = 7
    local offered, loan = book(state)
    local loan_left = contracts.payoff(loan)
    local outcome = insolvency.bankrupt(state, 1000)
    assert.are.equal(contracts.DECLINED, offered.state)
    assert.are.equal(contracts.FAILED, loan.state)
    assert.is_nil(next(state.contracts.open))
    assert.are.equal(2, #state.contracts.history)
    assert.are.equal(0, state.balance)
    assert.are.equal(0, state.arrears)
    assert.are.equal(0, state.overdraft_low)
    assert.are.equal(0, state.solvency_low)
    assert.are.equal(reputation.MIN, state.reputation)
    local owed = 12000 + 3000 + loan_left
    assert.is_true(math.abs(owed * SURCHARGED - outcome.debt) < 1e-6)
    assert.are.equal(outcome.debt, state.bankruptcy_debt)
    assert.are.same({ 1, 2 }, outcome.contracts)
    local restructured = entries(state, insolvency.RESTRUCTURED_KIND)[1]
    assert.are.same({ 12000, owed, outcome.debt }, { restructured.amount, restructured.owed, restructured.debt })
    assert.are.same({ income = 12000, spending = 0, count = 1 }, state.ledger.total.bankruptcy)
    assert.are.same({ income = 0, spending = 0, count = 1 }, state.ledger.total.loans)
    assert.is_true(math.abs(owed * insolvency.RESTRUCTURING_SURCHARGE - restructured.surcharge) < 1e-6)
    local failed = entries(state, "contract-failed")
    assert.are.same({ 1, 0, "contract/2", "loan" },
      { #failed, failed[1].amount, failed[1].key, failed[1].contract_kind })
  end)

  it("takes the debt from a positive balance at once, never into the overdraft", function()
    local state = new_state(250, 100)
    insolvency.bankrupt(state, 1000)
    assert.are.equal(250 - 100 * SURCHARGED, state.balance)
    assert.are.equal(0, state.bankruptcy_debt)
    local other = new_state(250, 1000)
    insolvency.bankrupt(other, 1000)
    assert.are.equal(0, other.balance)
    assert.are.equal(1000 * SURCHARGED - 250, other.bankruptcy_debt)
  end)

  it("keeps the debt frozen and takes it from later income, holding credit until it is repaid", function()
    local state = new_state(-20000)
    insolvency.bankrupt(state, 1000)
    local after_ban = 1000 + insolvency.BAN_TICKS
    local debt = 20000 * SURCHARGED
    assert.are.same({}, insolvency.check(state, after_ban))
    assert.are.equal(debt, state.bankruptcy_debt)
    assert.are.equal(0, account.charge_interest(state, after_ban))
    assert.is_true(insolvency.credit_banned(state))
    -- A sale goes to the debt at once, before any check.
    assert.is_true(account.apply(state, 5000, { tick = after_ban + 1, kind = "sell" }))
    assert.are.same({ 0, debt - 5000 }, { state.balance, state.bankruptcy_debt })
    assert.are.equal(insolvency.DEBT_KIND, state.journal[#state.journal].kind)
    assert.are.same({}, insolvency.check(state, after_ban + 60))
    assert.is_true(account.apply(state, debt - 5000 + 1000, { tick = after_ban + 61, kind = "sell" }))
    assert.are.same({ 1000, 0 }, { state.balance, state.bankruptcy_debt })
    assert.are.same({ "credit-restored" }, names(insolvency.check(state, after_ban + 120)))
    assert.are.same({ 1000, 0 }, { state.balance, state.bankruptcy_debt })
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state))
  end)

  it("refuses credit for a ban that doubles with each bankruptcy, up to a bound", function()
    local state = new_state()
    local outcome = insolvency.bankrupt(state, 1000)
    assert.are.equal(1, state.bankruptcies)
    assert.are.equal(insolvency.BAN_TICKS, outcome.ban_ticks)
    assert.are.equal(1000 + insolvency.BAN_TICKS, state.credit_ban_until)
    assert.is_true(insolvency.credit_banned(state))
    assert.is_nil(state.insolvent_since)
    assert.are.equal(2 * insolvency.BAN_TICKS, insolvency.bankrupt(state, 2000).ban_ticks)
    for _ = 1, 5 do insolvency.bankrupt(state, 3000) end
    assert.are.equal(insolvency.ban_ticks(4), insolvency.bankrupt(state, 4000).ban_ticks)
    assert.are.equal(8 * insolvency.BAN_TICKS, insolvency.ban_ticks(4))
  end)

  it("takes the overdraft away during the ban, so the debt cannot be drawn again", function()
    local state = new_state(-12000)
    insolvency.bankrupt(state, 1000)
    assert.are.equal(0, account.overdraft_limit(state))
    assert.are.same({ false, "insufficient-funds" }, { account.apply(state, -1, { tick = 1001 }) })
    assert.are.equal(0, account.charge_interest(state, 1001))
  end)

  it("takes the researched overdraft away too, whatever the reputation", function()
    local state = new_state()
    state.overdraft_level, state.reputation = #account.OVERDRAFT_LEVEL_LIMITS, reputation.MAX
    state.credit_ban_until = 5000
    assert.are.equal(0, account.overdraft_limit(state))
  end)

  it("gives back a researched overdraft shrunk by the minimum reputation, without a new insolvency", function()
    local state = new_state(-30000)
    state.overdraft_level, state.reputation = #account.OVERDRAFT_LEVEL_LIMITS, reputation.MAX
    insolvency.bankrupt(state, 1000)
    state.balance = state.bankruptcy_debt
    local events = insolvency.check(state, 1000 + insolvency.BAN_TICKS)
    assert.are.same({ "credit-restored" }, names(events))
    local top = account.OVERDRAFT_LEVEL_LIMITS[#account.OVERDRAFT_LEVEL_LIMITS]
    local scale = reputation.contract_scale(reputation.MIN)
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT + (top - account.BASE_OVERDRAFT_LIMIT) * scale,
      account.overdraft_limit(state))
    assert.are.same({}, insolvency.check(state, 1060 + insolvency.BAN_TICKS))
  end)

  it("gives credit back when the ban ends with no debt left", function()
    local state = new_state()
    insolvency.bankrupt(state, 1000)
    assert.are.same({}, insolvency.check(state, 1000 + insolvency.BAN_TICKS - 1))
    assert.are.same({ "credit-restored" }, names(insolvency.check(state, 1000 + insolvency.BAN_TICKS)))
    assert.is_false(insolvency.credit_banned(state))
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state))
  end)
end)

describe("insolvency.check_all", function()
  it("checks every force in index order and reports each event with its force", function()
    local forces = { [3] = new_state(-50000), [1] = new_state(-50000), [2] = new_state(0) }
    local events = insolvency.check_all(forces, 60)
    assert.are.equal(2, #events)
    assert.are.equal(1, events[1].force_index)
    assert.are.equal(3, events[2].force_index)
    assert.are.equal("insolvent", events[2].event.name)
  end)
end)

describe("insolvency.remaining", function()
  it("tells the ticks left before bankruptcy and before credit returns", function()
    local state = new_state(-50000)
    assert.is_nil(insolvency.grace_left(state, 0))
    insolvency.check(state, 60)
    assert.are.equal(insolvency.GRACE_TICKS - 40, insolvency.grace_left(state, 100))
    assert.are.equal(0, insolvency.grace_left(state, 60 + 2 * insolvency.GRACE_TICKS))
    assert.is_nil(insolvency.ban_left(state, 100))
    insolvency.bankrupt(state, 1000)
    assert.are.equal(insolvency.BAN_TICKS - 500, insolvency.ban_left(state, 1500))
  end)

  it("names the balance a force must reach to recover", function()
    local state = new_state()
    assert.are.equal(insolvency.recovery_margin(state) - account.overdraft_limit(state),
      insolvency.recovery_balance(state))
    assert.is_true(insolvency.recovery_balance(state) < 0)
  end)
end)

describe("insolvency.merge", function()
  it("keeps the stricter state: the earliest insolvency, the latest ban, the most bankruptcies", function()
    local destination, source = new_state(), new_state()
    source.insolvent_since, source.credit_ban_until, source.bankruptcies = 100, 9000, 2
    destination.insolvent_since, destination.credit_ban_until, destination.bankruptcies = 500, 12000, 1
    source.bankruptcy_debt, destination.bankruptcy_debt, destination.recovering_since = 300, 200, 400
    insolvency.merge(destination, source)
    assert.are.equal(100, destination.insolvent_since)
    assert.are.equal(12000, destination.credit_ban_until)
    assert.are.equal(2, destination.bankruptcies)
    assert.are.equal(500, destination.bankruptcy_debt)
    assert.is_nil(destination.recovering_since)
  end)

  it("does not restart the clock of an insolvent force merged into a fresh one", function()
    local destination, source = new_state(), new_state()
    source.insolvent_since = 100
    insolvency.merge(destination, source)
    assert.are.equal(100, destination.insolvent_since)
  end)
end)

describe("insolvency.init", function()
  it("gives an old state no bankruptcies and no insolvency", function()
    local state = { balance = 0 }
    insolvency.init(state)
    assert.are.equal(0, state.bankruptcies)
    assert.are.equal(0, state.bankruptcy_debt)
    assert.is_nil(state.insolvent_since)
    assert.is_nil(state.credit_ban_until)
  end)
end)
