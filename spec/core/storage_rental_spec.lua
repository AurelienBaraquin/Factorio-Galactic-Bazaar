local contract_offers = require("scripts.core.contract_offers")
local contracts = require("scripts.core.contracts")
local storage_rental = require("scripts.core.storage_rental")

describe("storage_rental.vault", function()
  it("charges every period for the slots, holds one period as its guarantee and moves no goods", function()
    local spec = storage_rental.vault("Ceres Deep Vaults", 50)
    local charge = 50 * storage_rental.SLOT_RENT * storage_rental.VAULT_MARKUP
    assert.are.same({ "storage", "Ceres Deep Vaults", charge, charge, 0, 0 },
      { spec.kind, spec.counterparty, spec.charge, spec.deposit, spec.penalty, spec.reward })
    assert.are.same({ {}, {} }, { spec.provides, spec.requires })
    assert.are.same({ storage_rental.TERM_TICKS, storage_rental.PERIOD_TICKS },
      { spec.duration_ticks, spec.installment_ticks })
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("costs more than a warehouse of the same size earns", function()
    assert.is_true(storage_rental.vault_charge(10) > 10 * storage_rental.SLOT_RENT)
  end)

  it("picks its counterparty from the draw", function()
    local list = storage_rental.VAULT_OPERATORS
    assert.are.equal(list[1], storage_rental.vault_operator(0))
    assert.are.equal(list[#list], storage_rental.vault_operator(0.999999))
  end)
end)

describe("storage_rental.stacks", function()
  it("counts each item's stacks, a part stack as a whole one", function()
    local sizes = { ["iron-plate"] = 100, ["iron-gear-wheel"] = 100 }
    assert.are.equal(0, storage_rental.stacks({}, sizes))
    assert.are.equal(3, storage_rental.stacks({ ["iron-plate"] = 101, ["iron-gear-wheel"] = 100 }, sizes))
  end)
end)

describe("storage_rental.room", function()
  local sizes = { ["iron-plate"] = 100, ["iron-gear-wheel"] = 50, ["rail"] = 100 }

  it("fits an item into the slots other items leave, filling its own part stack", function()
    assert.are.equal(500, storage_rental.room({}, sizes, 5, "iron-plate"))
    assert.are.equal(150, storage_rental.room({ ["iron-plate"] = 350 }, sizes, 5, "iron-plate"))
    assert.are.equal(150, storage_rental.room({ ["iron-plate"] = 101 }, sizes, 5, "iron-gear-wheel"))
  end)

  it("has no room left in full slots", function()
    assert.are.equal(0, storage_rental.room({ ["iron-plate"] = 500 }, sizes, 5, "iron-plate"))
    assert.are.equal(0, storage_rental.room({ ["iron-plate"] = 401, ["rail"] = 1 }, sizes, 5, "iron-gear-wheel"))
  end)
end)

describe("storage_rental.room_in", function()
  it("agrees with room from a vault's stacks used, the item's own stacks and units", function()
    local sizes = { ["iron-plate"] = 100, ["iron-gear-wheel"] = 50 }
    local goods = { ["iron-plate"] = 350, ["iron-gear-wheel"] = 101 }
    for _, name in ipairs({ "iron-plate", "iron-gear-wheel" }) do
      local own = math.ceil(goods[name] / sizes[name])
      assert.are.equal(storage_rental.room(goods, sizes, 10, name),
        storage_rental.room_in(storage_rental.stacks(goods, sizes), own, goods[name], sizes[name], 10))
    end
    assert.are.equal(0, storage_rental.room_in(12, 0, 0, 100, 10))
  end)
end)

describe("storage_rental.warehouse_penalty", function()
  it("covers buying the goods back at the market, with a margin, never below the offer's penalty", function()
    assert.are.near(1100, storage_rental.warehouse_penalty(500, 1000), 1e-9)
    assert.are.equal(2000, storage_rental.warehouse_penalty(2000, 1000))
  end)

  it("doubles the offer's penalty, with the margin, when the market cannot sell that many", function()
    assert.are.near(500 * storage_rental.UNQUOTED_FACTOR * storage_rental.BUY_MARGIN,
      storage_rental.warehouse_penalty(500, nil), 1e-9)
  end)

  it("stays within the contract model's bound", function()
    assert.are.equal(contracts.MAX_CREDITS, storage_rental.warehouse_penalty(1, 1e13))
  end)
end)

describe("storage_rental.warehouse", function()
  local draw = 0.5

  it("stores goods worth the target value, pays rent per stack and period at the end, holds their value", function()
    local spec = storage_rental.warehouse("iron-plate", 2, 100, 48, draw, 1)
    local units = math.ceil(contract_offers.TARGET_VALUE / 2)
    local stacks = math.ceil(units / 100)
    assert.are.same({ { kind = "item", name = "iron-plate", count = units } }, spec.provides)
    assert.are.same(spec.provides, spec.requires)
    assert.are.near(storage_rental.SLOT_RENT * stacks * storage_rental.periods(), spec.reward, 1e-9)
    assert.is_true(spec.deposit + spec.penalty > 2 * units)
    assert.is_nil(spec.installment_ticks)
    assert.are.same({ "warehouse", storage_rental.TERM_TICKS, true }, { spec.kind, spec.duration_ticks, spec.custody })
    assert.is_truthy(contracts.new(spec, 0))
  end)

  it("never fills more than its share of the warehouse", function()
    local spec = storage_rental.warehouse("iron-plate", 0.01, 100, 48, draw, 3)
    assert.are.equal(math.floor(48 * storage_rental.FILL_SHARE) * 100, spec.provides[1].count)
  end)

  it("stores at least one unit of a costly item and follows the reputation scale", function()
    assert.are.equal(1, storage_rental.warehouse("rocket-part", 1e6, 1, 48, draw, 1).provides[1].count)
    local small = storage_rental.warehouse("iron-plate", 2, 100, 48, draw, 0.5).provides[1].count
    local large = storage_rental.warehouse("iron-plate", 2, 100, 48, draw, 2).provides[1].count
    assert.is_true(large > small)
  end)

  it("makes no offer without a value or a slot to fill", function()
    assert.is_nil(storage_rental.warehouse("iron-plate", nil, 100, 48, draw, 1))
    assert.is_nil(storage_rental.warehouse("iron-plate", 0, 100, 48, draw, 1))
    assert.is_nil(storage_rental.warehouse("iron-plate", 2, 100, 1, draw, 1))
  end)
end)
