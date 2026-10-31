local contracts = require("scripts.core.contracts")
local loans = require("scripts.core.loans")

-- An active loan of `principal` taken at tick 0 with a reputation of `score`.
local function taken(principal, score)
  local contract = contracts.new(loans.spec(principal, score or 0), 0)
  contracts.accept(contract, 0)
  return contract
end

describe("loans.rate", function()
  it("falls with reputation, within its bounds", function()
    assert.are.equal(0.1, loans.rate(0))
    assert.is_true(math.abs(loans.rate(20) - 0.05) < 1e-12)
    assert.is_true(math.abs(loans.rate(-20) - 0.15) < 1e-12)
    assert.are.equal(loans.rate(20), loans.rate(35))
    assert.are.equal(loans.rate(-20), loans.rate(-35))
  end)
end)

describe("loans.cap", function()
  it("follows the contract scale of the reputation", function()
    assert.are.equal(50000, loans.cap(0))
    assert.are.equal(150000, loans.cap(20))
    assert.are.equal(25000, loans.cap(-20))
  end)
end)

describe("loans.spec", function()
  it("advances the principal and charges principal plus interest in equal installments over the term", function()
    local spec = loans.spec(20000, 0)
    assert.are.equal("loan", spec.kind)
    assert.are.equal(20000, spec.advance)
    assert.are.equal(loans.TERM_TICKS, spec.duration_ticks)
    assert.are.equal(loans.PERIOD_TICKS, spec.installment_ticks)
    assert.are.equal(0, spec.deposit + spec.penalty + spec.reward)
    assert.is_true(math.abs(spec.charge * loans.periods() - 22000) < 1e-6)
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("repays every installment of the term when settled every 60 ticks from any tick", function()
    local contract = contracts.new(loans.spec(5000, 0), 7)
    contracts.accept(contract, 7)
    local repaid, outcome = 0, nil
    for tick = 60, loans.TERM_TICKS * 2, 60 do
      outcome = contracts.settle(contract, tick)
      if outcome then break end
      local installment = contracts.installment(contract, tick)
      if installment then repaid = repaid - installment end
    end
    assert.is_true(math.abs(repaid - 5500) < 1e-6)
    assert.are.same({ state = contracts.FULFILLED, credits = 0, reputation = 0 }, outcome)
  end)
end)

describe("loans.outstanding", function()
  it("counts the principal still to repay of active loans, plus arrears", function()
    local open = { [1] = taken(12000), [2] = taken(5000), [3] = { kind = "incoming", state = contracts.ACTIVE } }
    for _ = 1, 3 do contracts.installment(open[1], open[1].next_installment) end
    assert.is_true(math.abs(loans.outstanding(open, 0) - (9000 + 5000)) < 1e-6)
    assert.is_true(math.abs(loans.outstanding(open, 700) - (9000 + 5000 + 700)) < 1e-6)
    open[2].state = contracts.FULFILLED
    assert.is_true(math.abs(loans.outstanding(open, 0) - 9000) < 1e-6)
  end)
end)

describe("loans.refusal", function()
  it("refuses a loan that would bring the debt above the cap, or while arrears are owed", function()
    assert.is_nil(loans.refusal(50000, 0, {}, 0))
    assert.are.equal("debt-cap", loans.refusal(100000, 0, {}, 0))
    assert.is_nil(loans.refusal(100000, 10, {}, 0))
    assert.are.equal("debt-cap", loans.refusal(20000, 0, { taken(20000), taken(20000) }, 0))
    assert.are.equal("in-arrears", loans.refusal(5000, 20, {}, 1))
  end)
end)

describe("loans.collect", function()
  it("takes what the balance can pay of the arrears", function()
    assert.are.equal(300, loans.collect(300, 1000))
    assert.are.equal(1000, loans.collect(3000, 1000))
    assert.are.equal(0, loans.collect(3000, -50))
    assert.are.equal(0, loans.collect(0, 1000))
  end)
end)

describe("loans.init and loans.merge", function()
  it("give a state its arrears and add a merged force's to the destination's", function()
    local destination, source = {}, { arrears = 40 }
    loans.init(destination)
    assert.are.equal(0, destination.arrears)
    destination.arrears = 2
    loans.merge(destination, source)
    assert.are.equal(42, destination.arrears)
  end)
end)
