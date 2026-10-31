local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")
local insolvency = require("scripts.core.insolvency")
local loans = require("scripts.core.loans")
local overview = require("scripts.core.overview")
local reputation = require("scripts.core.reputation")

local function new_state(balance)
  local state = { balance = balance, reputation = 0, contracts = { open = {} } }
  account.init(state)
  insolvency.init(state)
  loans.init(state)
  return state
end

local function contract(id, kind, state, due_tick)
  return { id = id, kind = kind, state = state, due_tick = due_tick }
end

describe("overview.figures: account", function()
  it("gives the balance, the overdraft used, left and its limit", function()
    local state = new_state(-400)
    local figures = overview.figures(state, 100)
    local limit = account.overdraft_limit(state)
    assert.are.same({ -400, 400, limit - 400, limit },
      { figures.balance, figures.overdraft_used, figures.overdraft_left, figures.overdraft_limit })
  end)

  it("uses no overdraft on a positive balance", function()
    local figures = overview.figures(new_state(250), 0)
    assert.are.same({ 0, account.overdraft_limit(new_state(0)) }, { figures.overdraft_used, figures.overdraft_left })
  end)

  it("estimates the next interest charge and the ticks until it", function()
    local state = new_state(-2000)
    local figures = overview.figures(state, 3600 * 4 + 600)
    assert.are.same({ account.INTEREST_RATE, account.INTEREST_TICKS },
      { figures.interest_rate, figures.interest_ticks })
    assert.are.equal(account.interest_due(state), figures.interest_due)
    assert.is_true(figures.interest_due > 0)
    assert.are.equal(3000, figures.interest_in)
    assert.are.equal(account.INTEREST_TICKS, overview.figures(state, 7200).interest_in)
  end)
end)

describe("overview.figures: reputation", function()
  it("gives the score and its effects on fees, contracts and loans", function()
    local state = new_state(0)
    state.reputation = 8
    local figures = overview.figures(state, 0)
    assert.are.same({ 8, reputation.fee_factor(8), reputation.contract_scale(8), loans.rate(8), loans.cap(8) },
      { figures.reputation, figures.fee_factor, figures.contract_scale, figures.loan_rate, figures.loan_cap })
  end)
end)

describe("overview.figures: solvency", function()
  it("is solvent with nothing owed", function()
    local solvency = overview.figures(new_state(0), 0).solvency
    assert.are.same({ name = "solvent", bankruptcies = 0, debt = 0 }, solvency)
  end)

  it("gives an insolvent force's grace left and the balance to keep to recover", function()
    local state = new_state(-20000)
    state.insolvent_since = 600
    local solvency = overview.figures(state, 1200).solvency
    assert.are.equal("insolvent", solvency.name)
    assert.are.equal(insolvency.GRACE_TICKS - 600, solvency.grace_left)
    assert.are.equal(insolvency.recovery_balance(state), solvency.recovery_balance)
    assert.is_nil(solvency.recovering_left)
  end)

  it("gives the time left before an insolvent force that keeps the margin recovers", function()
    local state = new_state(0)
    state.insolvent_since, state.recovering_since = 600, 1200
    local solvency = overview.figures(state, 1800).solvency
    assert.are.same({ "insolvent", insolvency.RECOVERY_TICKS - 600 }, { solvency.name, solvency.recovering_left })
  end)

  it("gives a bankrupt force's credit ban left, its debt and its bankruptcies", function()
    local state = new_state(0)
    state.credit_ban_until, state.bankruptcy_debt, state.bankruptcies = 5000, 1234, 2
    local solvency = overview.figures(state, 1000).solvency
    assert.are.same({ name = "banned", ban_left = 4000, debt = 1234, bankruptcies = 2 }, solvency)
  end)

  it("names insolvency first when a banned force is insolvent again, keeping the ban", function()
    local state = new_state(-10)
    state.credit_ban_until, state.insolvent_since = 5000, 900
    local solvency = overview.figures(state, 1000).solvency
    assert.are.same({ "insolvent", 4000 }, { solvency.name, solvency.ban_left })
  end)
end)

describe("overview.figures: commitments", function()
  it("counts open contracts by kind and state, and finds the nearest deadline of an active one", function()
    local state = new_state(0)
    local open = state.contracts.open
    open[1] = contract(1, "incoming", contracts.OFFERED, 900)
    open[2] = contract(2, "incoming", contracts.ACTIVE, 7000)
    open[3] = contract(3, "concession", contracts.ACTIVE, 4000)
    open[4] = contract(4, "loan", contracts.ACTIVE, 3000)
    local figures = overview.figures(state, 1000)
    assert.are.same({
      incoming = { offered = 1, active = 1 }, concession = { offered = 0, active = 1 },
      loan = { offered = 0, active = 1 },
    }, figures.commitments)
    assert.are.same({ ticks = 2000, kind = "loan" }, figures.next_due)
  end)

  it("gives the loan debt and arrears", function()
    local state = new_state(0)
    state.arrears = 300
    local figures = overview.figures(state, 0)
    assert.are.same({ 300, 300 }, { figures.loan_debt, figures.arrears })
    assert.is_nil(figures.next_due)
    assert.are.same({}, figures.commitments)
  end)

  it("reads a state without a contract book, reputation or arrears as empty", function()
    local figures = overview.figures({ balance = 5 }, 0)
    assert.are.same({ {}, 0, 0, 0 }, { figures.commitments, figures.reputation, figures.loan_debt, figures.arrears })
  end)
end)
