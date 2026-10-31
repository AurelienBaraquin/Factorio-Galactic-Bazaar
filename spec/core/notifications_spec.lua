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
  end)
end)
