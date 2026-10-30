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
    storage.gb_test_contracts = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
    }
    state().balance = 1000
  end)
  after_each(function()
    local saved = storage.gb_test_contracts
    if saved then
      state().balance, state().reputation = saved.balance, saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      storage.gb_test_contracts = nil
    end
    state().contracts.open = {}
  end)

  test("hold deposit and penalty on acceptance, and give them back with the reward once fulfilled", function()
    local id = contracts.offer(force_index(), spec())
    assert.is_true(contracts.accept(force_index(), id))
    assert.are.equal(700, state().balance)
    assert.are.equal(5, contracts.deliver(force_index(), id, "item/iron-gear-wheel", 7))
    local reputation = state().reputation
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(1500, state().balance)
    assert.are.equal(reputation + 1, state().reputation)
    assert.is_nil(state().contracts.open[id])
    assert.are.equal(core.FULFILLED, state().contracts.history[#state().contracts.history].state)
  end)

  test("keep the reputation within its bounds", function()
    state().reputation = 20
    local id = contracts.offer(force_index(), spec())
    contracts.accept(force_index(), id)
    contracts.deliver(force_index(), id, "item/iron-gear-wheel", 5)
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(20, state().reputation)
  end)

  test("refuse an acceptance the force cannot guarantee, changing nothing", function()
    state().balance = 250
    local id = contracts.offer(force_index(), spec())
    assert.are.same({ false, "insufficient-funds" }, { contracts.accept(force_index(), id) })
    assert.are.equal(core.OFFERED, contracts.get(force_index(), id).state)
    assert.are.equal(250, state().balance)
  end)

  test("fail a late contract: the guarantee is kept even if the force spent everything else", function()
    local id = contracts.offer(force_index(), spec())
    contracts.accept(force_index(), id)
    state().balance = 0
    local reputation = state().reputation
    contracts.on_settle_tick({ tick = game.tick + 601 })
    assert.are.equal(0, state().balance)
    assert.are.equal(reputation - 1, state().reputation)
    assert.is_nil(state().contracts.open[id])
    local journal = state().journal
    assert.are.equal("contract-failed", journal[#journal].kind)
  end)

  test("let an offer be declined", function()
    local id = contracts.offer(force_index(), spec())
    assert.is_true(contracts.decline(force_index(), id))
    assert.is_nil(contracts.get(force_index(), id))
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
    source_state.reputation = 5
    state().reputation = 2
    local id = contracts.offer(source.index, spec())
    contracts.accept(source.index, id)
    game.merge_forces(source, "player")
    after_ticks(1, function()
      local carried = contracts.get(force_index(), id)
      assert.are.equal(core.ACTIVE, carried and carried.state)
      assert.are.equal(2, state().reputation)
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
