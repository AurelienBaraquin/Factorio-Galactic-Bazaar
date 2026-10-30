-- In-game tests of the contract engine's runtime side (scripts/contracts.lua, ADR-0015): offers,
-- deposits, settlement through the force's account, reputation, force merge and persistence.
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")

local function force_index() return game.forces.player.index end
local function state() return storage.forces[force_index()] end

local function spec(overrides)
  local base = {
    kind = "incoming", counterparty = "Test",
    provides = { { kind = "item", name = "iron-plate", count = 10 } },
    requires = { { kind = "item", name = "iron-gear-wheel", count = 5 } },
    reward = 500, deposit = 100, penalty = 200, duration_ticks = 600, accept_ticks = 600,
  }
  for k, v in pairs(overrides or {}) do base[k] = v end
  return base
end

describe("contracts", function()
  before_each(function()
    storage.gb_test_contracts = { balance = state().balance, reputation = state().reputation }
    state().balance = 1000
  end)
  after_each(function()
    local saved = storage.gb_test_contracts
    if saved then
      state().balance, state().reputation = saved.balance, saved.reputation
      storage.gb_test_contracts = nil
    end
    state().contracts.open = {}
  end)

  test("hold the deposit on acceptance, and pay reward and deposit once fulfilled", function()
    local id = contracts.offer(force_index(), spec())
    assert.is_true(contracts.accept(force_index(), id))
    assert.are.equal(900, state().balance)
    assert.are.equal(5, contracts.deliver(force_index(), id, "item/iron-gear-wheel", 7))
    local reputation = state().reputation
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(1500, state().balance)
    assert.are.equal(reputation + 1, state().reputation)
    assert.is_nil(state().contracts.open[id])
    assert.are.equal(core.FULFILLED, state().contracts.history[#state().contracts.history].state)
  end)

  test("refuse an acceptance the force cannot pay for, changing nothing", function()
    state().balance = 50
    local id = contracts.offer(force_index(), spec())
    assert.are.same({ false, "insufficient-funds" }, { contracts.accept(force_index(), id) })
    assert.are.equal(core.OFFERED, contracts.get(force_index(), id).state)
    assert.are.equal(50, state().balance)
  end)

  test("fail a late contract: the deposit is lost and the penalty taken, at most the balance", function()
    local id = contracts.offer(force_index(), spec())
    contracts.accept(force_index(), id)
    state().balance = 150
    local reputation = state().reputation
    contracts.on_settle_tick({ tick = game.tick + 601 })
    assert.are.equal(0, state().balance)
    assert.are.equal(reputation - 1, state().reputation)
    assert.is_nil(state().contracts.open[id])
  end)

  test("expire an offer nobody accepted, and fail an abandoned contract", function()
    local offer = contracts.offer(force_index(), spec())
    contracts.on_settle_tick({ tick = game.tick + 601 })
    assert.is_nil(contracts.get(force_index(), offer))
    local id = contracts.offer(force_index(), spec())
    contracts.accept(force_index(), id)
    assert.are.equal(core.FAILED, contracts.abandon(force_index(), id).state)
  end)

  test("carry a merged force's open contracts over", function()
    local source = game.create_force("gb-test-contracts")
    local source_state = storage.forces[source.index]
    source_state.balance = 1000
    local id = contracts.offer(source.index, spec())
    contracts.accept(source.index, id)
    game.merge_forces(source, "player")
    after_ticks(1, function()
      local carried = 0
      for _, contract in pairs(state().contracts.open) do
        if contract.state == core.ACTIVE then carried = carried + 1 end
      end
      assert.are.equal(1, carried)
    end)
  end)

  test("keep the book across a save and reload", function()
    storage.gb_test_contract_id = contracts.offer(force_index(), spec())
  end).after_reload_mods(function()
    local contract = storage.forces[game.forces.player.index].contracts.open[storage.gb_test_contract_id]
    storage.gb_test_contract_id = nil
    assert.are.equal(core.OFFERED, contract.state)
  end)
end)
