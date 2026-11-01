local contracts = require("scripts.core.contracts")
local notifications = require("scripts.core.notifications")

-- An active contract requiring 10 gears, due at `due_tick`.
local function active(due_tick)
  local contract = assert(contracts.new({
    kind = "incoming", counterparty = "test", provides = {},
    requires = { { kind = "item", name = "iron-gear-wheel", count = 10 } },
    reward = 100, deposit = 0, penalty = 50, duration_ticks = due_tick, accept_ticks = 60,
  }, 0))
  contracts.accept(contract, 0)
  return contract
end

describe("notifications", function()
  it("gives every kind a category, an icon and a period", function()
    for kind, spec in pairs(notifications.KINDS) do
      assert.is_truthy(notifications.CATEGORIES[spec.category], kind)
      assert.is_string(spec.icon.type, kind)
      assert.is_string(spec.icon.name, kind)
      assert.is_true(spec.period >= 0, kind)
    end
  end)

  it("admits a kind without a period every time, keeping nothing", function()
    local log = {}
    assert.is_true(notifications.admit(log, "contract-failed", 1, 100))
    assert.is_true(notifications.admit(log, "contract-failed", 1, 100))
    assert.is_nil(next(log))
  end)

  it("admits a kind once per period and group, then again once the period has passed", function()
    local log = {}
    local period = notifications.KINDS["delivery-landed"].period
    assert.is_true(notifications.admit(log, "delivery-landed", 7, 1000))
    assert.is_false(notifications.admit(log, "delivery-landed", 7, 1000 + period - 1))
    assert.is_true(notifications.admit(log, "delivery-landed", 8, 1000 + period - 1))
    assert.is_true(notifications.admit(log, "delivery-landed", 7, 1000 + period))
  end)

  it("throttles each kind on its own", function()
    local log = {}
    assert.is_true(notifications.admit(log, "contract-offer", "incoming", 0))
    assert.is_true(notifications.admit(log, "contract-due", "incoming", 0))
    assert.is_false(notifications.admit(log, "contract-offer", "incoming", 60))
    assert.is_true(notifications.admit(log, "contract-offer", "rental", 60))
  end)

  it("forgets groups whose period has passed, so the log stays bounded", function()
    local log = {}
    for id = 1, 50 do notifications.admit(log, "contract-due", id, id) end
    notifications.admit(log, "contract-due", 51, 51 + notifications.KINDS["contract-due"].period)
    local kept = 0
    for _ in pairs(log) do kept = kept + 1 end
    assert.are.equal(1, kept)
  end)

  it("carries the counts of throttled events to the next admitted one", function()
    local log = {}
    local period = notifications.KINDS["delivery-landed"].period
    assert.are.same({ true, 2 }, { notifications.admit(log, "delivery-landed", 7, 0, 2) })
    assert.is_false(notifications.admit(log, "delivery-landed", 7, 60, 3))
    assert.is_false(notifications.admit(log, "delivery-landed", 7, 120, 1))
    assert.are.same({ true, 5 }, { notifications.admit(log, "delivery-landed", 7, period, 1) })
    assert.are.same({ true, 4 }, { notifications.admit(log, "delivery-landed", 7, 2 * period, 4) })
  end)

  it("keeps a group with a count still to tell beyond its period", function()
    local log = {}
    local period = notifications.KINDS["delivery-landed"].period
    notifications.admit(log, "delivery-landed", 7, 0, 1)
    notifications.admit(log, "delivery-landed", 7, 60, 2)
    notifications.admit(log, "delivery-landed", 8, 10 * period, 1)
    assert.are.same({ true, 3 }, { notifications.admit(log, "delivery-landed", 7, 10 * period, 1) })
  end)

  it("merges a force's log into another: the latest tick and both counts still to tell", function()
    local destination, source = {}, {}
    notifications.admit(destination, "delivery-landed", 7, 0, 1)
    notifications.admit(destination, "delivery-landed", 7, 60, 2)
    notifications.admit(source, "delivery-landed", 7, 100, 1)
    notifications.admit(source, "delivery-landed", 7, 160, 4)
    notifications.admit(source, "contract-due", 12, 100)
    notifications.merge(destination, source)
    assert.is_false(notifications.admit(destination, "contract-due", 12, 200))
    local period = notifications.KINDS["delivery-landed"].period
    assert.is_false(notifications.admit(destination, "delivery-landed", 7, 99 + period, 0))
    assert.are.same({ true, 7 }, { notifications.admit(destination, "delivery-landed", 7, 100 + period, 1) })
  end)

  it("prints the insolvency and bankruptcy chat lines whatever the setting, and only those", function()
    local always = {}
    for kind, spec in pairs(notifications.KINDS) do
      if spec.chat_always then always[#always + 1] = kind end
    end
    table.sort(always)
    assert.are.same({ "bankrupt", "insolvent" }, always)
  end)

  it("refuses an unknown kind", function()
    assert.has_error(function() notifications.admit({}, "nope", 1, 0) end)
  end)

  describe("due_soon", function()
    it("is true for an incomplete active contract within the warning time of its deadline", function()
      local contract = active(10000)
      assert.is_false(notifications.due_soon(contract, 10000 - notifications.DUE_SOON_TICKS - 1))
      assert.is_true(notifications.due_soon(contract, 10000 - notifications.DUE_SOON_TICKS))
      assert.is_true(notifications.due_soon(contract, 10000))
      assert.is_false(notifications.due_soon(contract, 10001))
    end)

    it("is false once the contract is complete, and for offers and charges", function()
      local contract = active(10000)
      contracts.deliver(contract, "item/iron-gear-wheel", 10, 9000)
      assert.is_false(notifications.due_soon(contract, 9500))
      local offer = assert(contracts.new({
        kind = "incoming", counterparty = "test", provides = {},
        requires = { { kind = "item", name = "iron-gear-wheel", count = 10 } },
        reward = 1, deposit = 0, penalty = 0, duration_ticks = 100, accept_ticks = 100,
      }, 0))
      assert.is_false(notifications.due_soon(offer, 50))
      local lease = assert(contracts.new({
        kind = "concession", counterparty = "test", provides = {}, requires = {}, charge = 10,
        installment_ticks = 100, reward = 0, deposit = 0, penalty = 0, duration_ticks = 1000, accept_ticks = 60,
      }, 0))
      contracts.accept(lease, 0)
      assert.is_false(notifications.due_soon(lease, 900))
    end)

    it("is false for a custody contract, whose counterparty collects the goods itself", function()
      local stored = assert(contracts.new({
        kind = "warehouse", counterparty = "test", custody = true,
        provides = { { kind = "item", name = "iron-plate", count = 10 } },
        requires = { { kind = "item", name = "iron-plate", count = 10 } },
        reward = 1, deposit = 0, penalty = 0, duration_ticks = 1000, accept_ticks = 100,
      }, 0))
      contracts.accept(stored, 0)
      assert.is_false(notifications.due_soon(stored, 900))
    end)
  end)
end)
