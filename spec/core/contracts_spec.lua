local contracts = require("scripts.core.contracts")

local GEAR = "item/iron-gear-wheel"

local function spec(overrides)
  local base = {
    kind = "incoming", counterparty = "Nauvis Prime",
    provides = { { kind = "item", name = "iron-plate", count = 100 } },
    requires = { { kind = "item", name = "iron-gear-wheel", count = 50 } },
    reward = 500, deposit = 100, penalty = 200, duration_ticks = 3600, accept_ticks = 600,
  }
  for k, v in pairs(overrides or {}) do base[k] = v end
  return base
end

local function active(overrides)
  local contract = contracts.new(spec(overrides), 0)
  contracts.accept(contract, 0)
  return contract
end

describe("contracts.new", function()
  it("makes an offer from a valid spec, copying its goods", function()
    local source = spec()
    local contract = contracts.new(source, 10)
    source.requires[1].count = 1
    assert.are.equal(contracts.OFFERED, contract.state)
    assert.are.equal(610, contract.accept_by)
    assert.are.same({ [GEAR] = 50 }, contracts.remaining(contract))
  end)

  it("refuses invalid specs", function()
    for _, bad in ipairs({
      { requires = {} }, { reward = -1 }, { deposit = 0 / 0 }, { penalty = 1e13 }, { duration_ticks = 0 },
      { accept_ticks = 0 / 0 }, { accept_ticks = math.huge },
      { requires = { { kind = "energy", name = "x", count = 1 } } },
      { requires = { { kind = "item", name = "x", count = 0 } } },
      { requires = { { kind = "item", name = "x", count = math.huge } } },
      { requires = { { kind = "item", name = "x", count = 10 }, { kind = "item", name = "x", count = 5 } } },
    }) do
      local contract, reason = contracts.new(spec(bad), 0)
      assert.is_nil(contract)
      assert.is_string(reason)
    end
    local no_window = spec()
    no_window.accept_ticks = nil
    assert.is_nil(contracts.new(no_window, 0))
  end)

  it("keys goods by quality, so a quality is a distinct requirement", function()
    local contract = contracts.new(spec({ requires = {
      { kind = "item", name = "iron-gear-wheel", count = 5 },
      { kind = "item", name = "iron-gear-wheel", quality = "rare", count = 5 },
    } }), 0)
    assert.are.same({ [GEAR] = 5, [GEAR .. "@rare"] = 5 }, contracts.remaining(contract))
  end)
end)

describe("contract lifecycle", function()
  it("holds deposit and penalty as the guarantee on acceptance, and sets the deadline", function()
    local contract = contracts.new(spec(), 0)
    assert.are.equal(300, contracts.accept(contract, 100))
    assert.are.equal(contracts.ACTIVE, contract.state)
    assert.are.equal(3700, contract.due_tick)
    assert.are.same({ nil, "not-offered" }, { contracts.accept(contract, 101) })
  end)

  it("refuses a late acceptance, expires an offer nobody took, and lets an offer be declined", function()
    local contract = contracts.new(spec(), 0)
    assert.are.same({ nil, "expired" }, { contracts.accept(contract, 601) })
    assert.is_nil(contracts.settle(contract, 600))
    assert.are.same({ state = contracts.EXPIRED, credits = 0, reputation = 0 }, contracts.settle(contract, 601))
    local offer = contracts.new(spec(), 0)
    assert.is_true(contracts.decline(offer, 5))
    assert.are.equal(contracts.DECLINED, offer.state)
    assert.is_false(contracts.decline(offer, 6))
  end)

  it("pays installments for what was delivered, and the rest of the reward on fulfilment", function()
    local contract = contracts.new(spec({ installment_ticks = 100 }), 0)
    contracts.accept(contract, 0)
    assert.is_nil(contracts.installment(contract, 99))
    contracts.deliver(contract, GEAR, 10, 50)
    assert.are.equal(100, contracts.installment(contract, 100))
    assert.is_nil(contracts.installment(contract, 150))
    assert.is_nil(contracts.installment(contract, 200))
    contracts.deliver(contract, GEAR, 40, 250)
    local outcome = contracts.settle(contract, 260)
    assert.are.same({ state = contracts.FULFILLED, credits = 400 + 300, reputation = 1 }, outcome)
  end)

  it("keeps paid installments when a contract fails, and refuses a bad period", function()
    local contract = contracts.new(spec({ installment_ticks = 100 }), 0)
    contracts.accept(contract, 0)
    contracts.deliver(contract, GEAR, 25, 10)
    assert.are.equal(250, contracts.installment(contract, 100))
    assert.are.same({ state = contracts.FAILED, credits = 0, reputation = -1 }, contracts.settle(contract, 3601))
    assert.is_nil(contracts.new(spec({ installment_ticks = 0 }), 0))
    assert.is_nil(contracts.installment(contracts.new(spec(), 0), 1e9))
  end)

  it("charges a service every period, and gives the guarantee back at the end of its term", function()
    local contract = contracts.new(spec({ requires = {}, charge = 40, installment_ticks = 100, reward = 0 }), 0)
    assert.is_truthy(contract)
    contracts.accept(contract, 0)
    assert.is_nil(contracts.installment(contract, 99))
    assert.are.equal(-40, contracts.installment(contract, 100))
    assert.is_nil(contracts.settle(contract, 3601))
    while contracts.installment(contract, 3601) do end
    assert.is_nil(contracts.settle(contract, 3600))
    assert.are.same({ state = contracts.FULFILLED, credits = 300, reputation = 0 }, contracts.settle(contract, 3601))
  end)

  it("charges every period up to the deadline when settlement runs late", function()
    local terms = { requires = {}, charge = 40, installment_ticks = 600, duration_ticks = 3600 }
    local contract = contracts.new(spec(terms), 7)
    contracts.accept(contract, 7)
    local charges, outcome = 0, nil
    for tick = 60, 7200, 60 do
      outcome = contracts.settle(contract, tick)
      if outcome then break end
      if contracts.installment(contract, tick) then charges = charges + 1 end
    end
    assert.are.equal(6, charges)
    assert.are.equal(contracts.FULFILLED, outcome.state)
  end)

  it("defaults a service on an unpaid charge or an abandon, and validates the charge", function()
    local contract = contracts.new(spec({ requires = {}, charge = 40, installment_ticks = 100 }), 0)
    contracts.accept(contract, 0)
    assert.are.same({ state = contracts.FAILED, credits = 0, reputation = -1 }, contracts.default(contract, 50))
    assert.is_nil(contracts.default(contract, 51))
    local abandoned = contracts.new(spec({ requires = {}, charge = 40, installment_ticks = 100 }), 0)
    contracts.accept(abandoned, 0)
    assert.are.equal(contracts.FAILED, contracts.abandon(abandoned, 10).state)
    assert.is_nil(contracts.new(spec({ requires = {}, charge = 40 }), 0))
    assert.is_nil(contracts.new(spec({ requires = {}, charge = 0, installment_ticks = 100 }), 0))
    assert.is_nil(contracts.new(spec({ requires = {} }), 0))
  end)

  it("validates a loan's advance: positive, bounded, and only with a charge", function()
    local loan = { requires = {}, charge = 100, installment_ticks = 100, reward = 0, deposit = 0, penalty = 0 }
    loan.advance = 1000
    assert.are.equal(1000, contracts.new(spec(loan), 0).advance)
    for _, bad in ipairs({ 0, -5, 0 / 0, 1e13 }) do
      loan.advance = bad
      assert.is_nil(contracts.new(spec(loan), 0))
    end
    assert.is_nil(contracts.new(spec({ advance = 1000 }), 0))
  end)

  it("counts a loan's installments still to repay, and repays them at once instead of abandoning", function()
    local terms = { requires = {}, charge = 110, installment_ticks = 100, duration_ticks = 1000, advance = 1000,
      reward = 0, deposit = 0, penalty = 0 }
    local loan = contracts.new(spec(terms), 0)
    assert.are.equal(0, contracts.payoff(loan))
    contracts.accept(loan, 0)
    assert.are.equal(1100, contracts.payoff(loan))
    contracts.installment(loan, 100)
    contracts.installment(loan, 200)
    assert.are.equal(880, contracts.payoff(loan))
    assert.is_nil(contracts.abandon(loan, 250))
    assert.are.equal(contracts.ACTIVE, loan.state)
    assert.are.equal(8, contracts.periods_left(loan))
    assert.are.same({ state = contracts.FULFILLED, credits = 0, reputation = 0 }, contracts.repay(loan, 250))
    assert.is_nil(contracts.repay(loan, 251))
    assert.is_nil(contracts.repay(active(), 0))
  end)

  it("never voids a loan, whose debt would vanish with it", function()
    local terms = { requires = {}, charge = 110, installment_ticks = 100, duration_ticks = 1000, advance = 1000,
      reward = 0, deposit = 0, penalty = 0 }
    local loan = contracts.new(spec(terms), 0)
    contracts.accept(loan, 0)
    assert.is_nil(contracts.void(loan, 10))
    assert.are.equal(contracts.ACTIVE, loan.state)
    assert.are.equal(1100, contracts.payoff(loan))
  end)

  it("defaults a loan with the unpaid installment and every one left as arrears", function()
    local terms = { requires = {}, charge = 110, installment_ticks = 100, duration_ticks = 1000, advance = 1000,
      reward = 0, deposit = 0, penalty = 0 }
    local loan = contracts.new(spec(terms), 0)
    contracts.accept(loan, 0)
    contracts.installment(loan, 100)
    assert.are.same({ state = contracts.FAILED, credits = 0, reputation = -1, arrears = 110 + 990 },
      contracts.default(loan, 100, 110))
    local service = contracts.new(spec({ requires = {}, charge = 40, installment_ticks = 100 }), 0)
    contracts.accept(service, 0)
    assert.is_nil(contracts.default(service, 100, 40).arrears)
  end)

  it("voids an active contract with its whole guarantee back and no reputation, and nothing else", function()
    local contract = active()
    assert.are.same({ state = contracts.VOIDED, credits = 300, reputation = 0 }, contracts.void(contract, 10))
    assert.are.equal(10, contract.settled_tick)
    assert.is_nil(contracts.void(contract, 11))
    assert.is_nil(contracts.void(contracts.new(spec(), 0), 0))
  end)

  it("takes deliveries up to what is owed and gives back reward plus guarantee when complete", function()
    local contract = active()
    assert.are.equal(30, contracts.deliver(contract, GEAR, 30, 10))
    assert.are.equal(0, contracts.deliver(contract, "item/copper-plate", 10, 10))
    assert.is_nil(contracts.settle(contract, 100))
    assert.are.equal(20, contracts.deliver(contract, GEAR, 99, 20))
    assert.are.same({ state = contracts.FULFILLED, credits = 800, reputation = 1 }, contracts.settle(contract, 200))
    assert.are.equal(0, contracts.deliver(contract, GEAR, 1, 300))
  end)

  it("refuses deliveries after the deadline, even before the next settlement", function()
    local contract = active()
    contracts.deliver(contract, GEAR, 49, 100)
    assert.are.equal(0, contracts.deliver(contract, GEAR, 1, 3601))
    assert.are.same({ state = contracts.FAILED, credits = 0, reputation = -1 }, contracts.settle(contract, 3601))
  end)

  it("counts a fluid amount within rounding as delivered", function()
    local contract = active({ requires = { { kind = "fluid", name = "water", count = 1 } } })
    for _ = 1, 10 do contracts.deliver(contract, "fluid/water", 0.1, 10) end
    assert.is_true(contracts.complete(contract))
  end)

  it("fails an abandoned contract at once, unless it is already complete", function()
    local contract = active()
    assert.are.equal(contracts.FAILED, contracts.abandon(contract, 10).state)
    assert.is_nil(contracts.abandon(contract, 11))
    local complete = active()
    contracts.deliver(complete, GEAR, 50, 10)
    assert.are.equal(contracts.FULFILLED, contracts.abandon(complete, 20).state)
  end)

  it("gives no reputation for fulfilling a custody contract, and still takes one for failing it", function()
    local kept = active({ custody = true })
    assert.is_true(kept.custody)
    contracts.deliver(kept, GEAR, 50, 10)
    assert.are.same({ state = contracts.FULFILLED, credits = 800, reputation = 0 }, contracts.settle(kept, 20))
    local lost = active({ custody = true })
    assert.are.equal(-1, contracts.settle(lost, 3601).reputation)
  end)

  it("gives no reputation for fulfilling a passive contract, and still takes one for failing it", function()
    local kept = active({ passive = true })
    assert.is_true(kept.passive)
    contracts.deliver(kept, GEAR, 50, 10)
    assert.are.equal(0, contracts.settle(kept, 20).reputation)
    local lost = active({ passive = true })
    assert.are.equal(-1, contracts.settle(lost, 3601).reputation)
  end)

  it("treats a rental offered before rentals were passive as passive", function()
    local old = active({ kind = "rental" })
    assert.is_nil(old.passive)
    contracts.deliver(old, GEAR, 50, 10)
    assert.are.equal(0, contracts.settle(old, 20).reputation)
  end)
end)

describe("contract books", function()
  it("file contracts under the given ids and keep a bounded history", function()
    local state = {}
    contracts.init_book(state)
    for i = 1, contracts.HISTORY_SIZE + 5 do
      contracts.file(state, contracts.new(spec(), 0), i)
      contracts.close(state, i)
    end
    assert.are.equal(contracts.HISTORY_SIZE, #state.contracts.history)
    assert.are.equal(6, state.contracts.history[1].id)
  end)

  it("carry a merged force's open contracts over under the same ids, and carry only a reputation debt", function()
    local destination, source = {}, {}
    contracts.init_book(destination)
    contracts.init_book(source)
    contracts.file(destination, contracts.new(spec(), 0), 1)
    local carried = contracts.new(spec(), 0)
    contracts.file(source, carried, 7)
    destination.reputation, source.reputation = 2, -3
    contracts.merge_books(destination, source)
    assert.are.equal(carried, destination.contracts.open[7])
    assert.are.equal(-1, destination.reputation)
  end)
end)
