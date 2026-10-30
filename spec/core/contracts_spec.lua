local contracts = require("scripts.core.contracts")

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

describe("contracts.new", function()
  it("makes an offer from a valid spec", function()
    local contract = contracts.new(spec(), 10)
    assert.are.equal(contracts.OFFERED, contract.state)
    assert.are.equal(610, contract.accept_by)
    assert.are.same({ ["item/iron-gear-wheel"] = 50 }, contracts.remaining(contract))
  end)

  it("refuses invalid specs", function()
    for _, bad in ipairs({
      { requires = {} }, { reward = -1 }, { deposit = 0 / 0 }, { duration_ticks = 0 },
      { requires = { { kind = "energy", name = "x", count = 1 } } },
      { requires = { { kind = "item", name = "x", count = 0 } } },
    }) do
      local contract, reason = contracts.new(spec(bad), 0)
      assert.is_nil(contract)
      assert.is_string(reason)
    end
  end)
end)

describe("contract lifecycle", function()
  it("holds the deposit on acceptance and sets the deadline", function()
    local contract = contracts.new(spec(), 0)
    assert.are.equal(100, contracts.accept(contract, 100))
    assert.are.equal(contracts.ACTIVE, contract.state)
    assert.are.equal(3700, contract.due_tick)
    assert.are.same({ nil, "not-offered" }, { contracts.accept(contract, 101) })
  end)

  it("refuses a late acceptance, and expires an offer nobody took", function()
    local contract = contracts.new(spec(), 0)
    assert.are.same({ nil, "expired" }, { contracts.accept(contract, 601) })
    assert.is_nil(contracts.settle(contract, 600))
    assert.are.same({ state = contracts.EXPIRED, credits = 0, reputation = 0 }, contracts.settle(contract, 601))
  end)

  it("takes deliveries up to what is owed and pays reward plus deposit when complete", function()
    local contract = contracts.new(spec(), 0)
    contracts.accept(contract, 0)
    assert.are.equal(30, contracts.deliver(contract, "item/iron-gear-wheel", 30))
    assert.are.equal(0, contracts.deliver(contract, "item/copper-plate", 10))
    assert.is_nil(contracts.settle(contract, 100))
    assert.are.equal(20, contracts.deliver(contract, "item/iron-gear-wheel", 99))
    assert.are.same({ state = contracts.FULFILLED, credits = 600, reputation = 1 }, contracts.settle(contract, 200))
    assert.are.equal(0, contracts.deliver(contract, "item/iron-gear-wheel", 1))
  end)

  it("fails a contract past its deadline: the deposit is kept and the penalty due", function()
    local contract = contracts.new(spec(), 0)
    contracts.accept(contract, 0)
    contracts.deliver(contract, "item/iron-gear-wheel", 49)
    assert.is_nil(contracts.settle(contract, 3600))
    assert.are.same({ state = contracts.FAILED, credits = -200, reputation = -1 }, contracts.settle(contract, 3601))
    assert.is_nil(contracts.settle(contract, 3700))
  end)

  it("fails an abandoned contract at once", function()
    local contract = contracts.new(spec(), 0)
    contracts.accept(contract, 0)
    assert.are.equal(contracts.FAILED, contracts.abandon(contract, 10).state)
    assert.is_nil(contracts.abandon(contract, 11))
  end)
end)

describe("contract books", function()
  it("file contracts under increasing ids and keep a bounded history", function()
    local state = {}
    contracts.init_book(state)
    for i = 1, contracts.HISTORY_SIZE + 5 do
      local id = contracts.file(state, contracts.new(spec(), 0))
      assert.are.equal(i, id)
      contracts.close(state, id)
    end
    assert.are.equal(contracts.HISTORY_SIZE, #state.contracts.history)
    assert.are.equal(6, state.contracts.history[1].id)
  end)

  it("carry a merged force's open contracts and reputation over", function()
    local destination, source = {}, {}
    contracts.init_book(destination)
    contracts.init_book(source)
    contracts.file(destination, contracts.new(spec(), 0))
    contracts.file(source, contracts.new(spec(), 0))
    destination.reputation, source.reputation = 2, 3
    contracts.merge_books(destination, source)
    assert.is_truthy(destination.contracts.open[2])
    assert.are.equal(5, destination.reputation)
  end)
end)
