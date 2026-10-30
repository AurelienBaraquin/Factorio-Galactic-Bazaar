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

  it("carry a merged force's open contracts over under the same ids, and add up reputations", function()
    local destination, source = {}, {}
    contracts.init_book(destination)
    contracts.init_book(source)
    contracts.file(destination, contracts.new(spec(), 0), 1)
    local carried = contracts.new(spec(), 0)
    contracts.file(source, carried, 7)
    destination.reputation, source.reputation = 2, 3
    contracts.merge_books(destination, source)
    assert.are.equal(carried, destination.contracts.open[7])
    assert.are.equal(5, destination.reputation)
  end)
end)
