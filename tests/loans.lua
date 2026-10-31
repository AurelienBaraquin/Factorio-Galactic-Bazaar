-- In-game tests of loans (scripts/loans.lua, #96, ADR-0020): borrowing a tier, repayment over the
-- term at the contract settlement, the rate and cap by reputation, repaying instead of abandoning,
-- default and arrears, force merge, the contracts window's credit line and persistence.
local contracts = require("scripts.contracts")
local contracts_gui = require("scripts.contracts_gui")
local core = require("scripts.core.contracts")
local forces = require("scripts.forces")
local loans = require("scripts.loans")
local loans_core = require("scripts.core.loans")

local function force_index() return game.forces.player.index end
local function state() return storage.forces[force_index()] end
local function near(expected, actual) return math.abs(expected - actual) < 1e-6 end

-- Runs the contract settlement and the arrears collection at `tick`.
local function settle(tick)
  contracts.on_settle_tick({ tick = tick })
  loans.on_collect_tick({ tick = tick })
end

-- The element of `root` whose tags hold `action` and, when given, `key` = `value`.
local function find(root, action, key, value)
  local tags = root.tags
  if tags.gb_action == action and (key == nil or tags[key] == value) then return root end
  for _, child in ipairs(root.children) do
    local found = find(child, action, key, value)
    if found then return found end
  end
end

-- Places a trading hub `dx` tiles east of the test player; destroyed after each test.
local function place_hub(dx)
  local player = game.get_player(1)
  local hub = player.surface.create_entity({ name = "gb-hub", force = "player", raise_built = true,
    position = { player.position.x + dx, player.position.y } })
  storage.gb_test_loan_hubs = storage.gb_test_loan_hubs or {}
  table.insert(storage.gb_test_loan_hubs, hub)
  return hub
end

describe("loans", function()
  before_each(function()
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_loans = {
      balance = state().balance, reputation = state().reputation, arrears = state().arrears,
      history = #state().contracts.history,
    }
    state().balance, state().reputation, state().arrears = 0, 0, 0
    state().contracts.open = {}
  end)
  after_each(function()
    contracts_gui.close(1)
    for _, hub in ipairs(storage.gb_test_loan_hubs or {}) do
      if hub.valid then hub.destroy() end
    end
    storage.gb_test_loan_hubs = nil
    local saved = storage.gb_test_loans
    if saved then
      state().balance, state().reputation, state().arrears = saved.balance, saved.reputation, saved.arrears
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      storage.gb_test_loans = nil
    end
    state().contracts.open = {}
  end)

  test("pay the principal at once and take principal plus interest back over the term", function()
    state().balance = 1000
    local id = loans.borrow(force_index(), 1)
    local loan = contracts.get(force_index(), id)
    assert.are.equal(core.ACTIVE, loan.state)
    assert.are.equal(6000, state().balance)
    assert.are.equal("contract-advance", state().journal[#state().journal].kind)
    local start = game.tick
    for tick = start + 60, start + loans_core.TERM_TICKS + 120, 60 do settle(tick) end
    assert.is_true(near(500, state().balance))
    assert.is_nil(contracts.get(force_index(), id))
    assert.are.equal(core.FULFILLED, state().contracts.history[#state().contracts.history].state)
    assert.are.equal(0, state().reputation)
  end)

  test("lend cheaper and more to a better reputation", function()
    local plain = contracts.get(force_index(), loans.borrow(force_index(), 1))
    state().contracts.open = {}
    state().reputation = 20
    local trusted = contracts.get(force_index(), loans.borrow(force_index(), 1))
    assert.is_true(trusted.charge < plain.charge)
    assert.is_truthy(loans.borrow(force_index(), 3))
  end)

  test("refuse a loan above the debt cap or beyond the contracts window, changing nothing", function()
    assert.are.same({ nil, "debt-cap" }, { loans.borrow(force_index(), 3) })
    assert.is_truthy(loans.borrow(force_index(), 2))
    assert.is_truthy(loans.borrow(force_index(), 2))
    assert.are.same({ nil, "debt-cap" }, { loans.borrow(force_index(), 2) })
    assert.are.equal(40000, state().balance)
    state().reputation = 20
    for _ = 1, contracts.MAX_LISTED - #contracts.listed(force_index()) do loans.borrow(force_index(), 1) end
    assert.are.same({ nil, "too-many-contracts" }, { loans.borrow(force_index(), 1) })
    assert.are.same({ nil, "invalid-amount" }, { loans.borrow(force_index(), 9) })
  end)

  test("repay a loan in full instead of abandoning it, never for free", function()
    local id = loans.borrow(force_index(), 1)
    state().balance = 1000
    assert.are.same({ nil, "insufficient-funds" }, { contracts.abandon(force_index(), id) })
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
    assert.are.equal(1000, state().balance)
    state().balance = 6000
    assert.are.equal(core.FULFILLED, contracts.abandon(force_index(), id).state)
    assert.is_true(near(500, state().balance))
    assert.is_nil(contracts.get(force_index(), id))
    local repaid
    for _, entry in ipairs(state().journal) do
      if entry.kind == "contract-repaid" and entry.key == "contract/" .. id then repaid = entry end
    end
    assert.is_true(near(-5500, repaid.amount))
  end)

  test("never void a loan, whose debt would vanish with it", function()
    local id = loans.borrow(force_index(), 1)
    assert.is_nil(contracts.void(force_index(), id))
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
  end)

  test("default a loan whose installment is not paid: what is left stays owed as arrears", function()
    local id = loans.borrow(force_index(), 1)
    local charge = contracts.get(force_index(), id).charge
    state().balance = 0
    settle(game.tick + loans_core.PERIOD_TICKS)
    assert.is_nil(contracts.get(force_index(), id))
    assert.are.equal(core.FAILED, state().contracts.history[#state().contracts.history].state)
    assert.are.equal(-1, state().reputation)
    assert.is_true(near(charge * loans_core.periods(), state().arrears))
    assert.are.same({ nil, "in-arrears" }, { loans.borrow(force_index(), 1) })
    state().balance = 1000
    settle(game.tick + loans_core.PERIOD_TICKS + 60)
    assert.are.equal(0, state().balance)
    assert.is_true(near(5500 - 1000, state().arrears))
    assert.are.equal("loan-arrears", state().journal[#state().journal].kind)
  end)

  test("carry a merged force's loans and arrears over to the destination", function()
    local source = game.create_force("gb-test-loans")
    local source_state = storage.forces[source.index]
    local id = loans.borrow(source.index, 1)
    source_state.arrears = 300
    game.merge_forces(source, "player")
    after_ticks(1, function()
      local carried = contracts.get(force_index(), id)
      assert.are.equal(core.ACTIVE, carried and carried.state)
      assert.are.equal(300, state().arrears)
      assert.are.equal(5000, state().balance)
      assert.are.same({ nil, "in-arrears" }, { loans.borrow(force_index(), 1) })
    end)
  end)

  test("refuse a destination a loan once a merged force's loans take it over its cap", function()
    local source = game.create_force("gb-test-loans-cap")
    storage.forces[source.index].reputation = 10
    loans.borrow(source.index, 3)
    assert.is_truthy(loans.borrow(force_index(), 2))
    game.merge_forces(source, "player")
    after_ticks(1, function()
      local debt, cap = loans.debt(force_index())
      assert.is_true(debt > cap)
      assert.are.same({ nil, "debt-cap" }, { loans.borrow(force_index(), 1) })
    end)
  end)

  test("survive a state saved before loans until its arrears are added on configuration change", function()
    state().arrears = nil
    contracts_gui.open(game.get_player(1), place_hub(3).unit_number)
    loans.on_collect_tick({ tick = game.tick })
    contracts_gui.on_refresh_tick()
    assert.are.equal(0, (loans.debt(force_index())))
    forces.init()
    assert.are.equal(0, state().arrears)
  end)

  test("borrow and repay from the contracts window, which shows the debt", function()
    local player = game.get_player(1)
    contracts_gui.open(player, place_hub(3).unit_number)
    local window = player.gui.screen.gb_contracts
    assert.is_false(find(window, "loan-borrow", "tier", 3).enabled)
    contracts_gui.on_gui_click({ element = find(window, "loan-borrow", "tier", 1), player_index = 1 })
    assert.are.equal(5000, state().balance)
    local loan = contracts.listed(force_index())[1]
    assert.are.equal("loan", loan.kind)
    state().balance = 6000
    contracts_gui.on_gui_click({ element = find(window, "contract-abandon", "id", loan.id), player_index = 1 })
    assert.is_nil(contracts.get(force_index(), loan.id))
  end)

  test("borrow and repay only through a hub of the force within reach", function()
    local player = game.get_player(1)
    local far = place_hub(30)
    contracts_gui.open(player, far.unit_number)
    contracts_gui.on_gui_click({ element = find(player.gui.screen.gb_contracts, "loan-borrow", "tier", 1),
      player_index = 1 })
    assert.are.equal(0, state().balance)
    assert.is_nil(player.gui.screen.gb_contracts)
    local id = loans.borrow(force_index(), 1)
    contracts_gui.open(player, far.unit_number)
    contracts_gui.on_gui_click({ element = find(player.gui.screen.gb_contracts, "contract-abandon", "id", id),
      player_index = 1 })
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
    assert.is_nil(player.gui.screen.gb_contracts)
  end)

  test("keep loans and arrears across a save and reload", function()
    storage.gb_test_loan_id = loans.borrow(force_index(), 1)
    state().arrears = 42
  end).after_reload_mods(function()
    local saved = storage.forces[game.forces.player.index]
    local loan = saved.contracts.open[storage.gb_test_loan_id]
    storage.gb_test_loan_id = nil
    assert.are.equal(core.ACTIVE, loan.state)
    assert.are.equal(42, saved.arrears)
  end)
end)
