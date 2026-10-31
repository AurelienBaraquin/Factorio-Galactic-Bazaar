-- In-game tests of the financial engineering research (scripts/finance.lua, #98): borrowing gated by
-- the credit research while existing loans are still repaid, the overdraft limit raised by each level
-- from the research events and scaled by reputation, force and technology-effect resets, the
-- self-heal at the interest tick, saves made before the levels, and persistence.
local account = require("scripts.core.account")
local contracts = require("scripts.contracts")
local contracts_gui = require("scripts.contracts_gui")
local core = require("scripts.core.contracts")
local finance = require("scripts.finance")
local forces = require("scripts.forces")
local loans = require("scripts.loans")
local loans_core = require("scripts.core.loans")

local BRANCH = { finance.CREDIT_TECHNOLOGY, finance.OVERDRAFT_TECHNOLOGIES[1], finance.OVERDRAFT_TECHNOLOGIES[2] }

local function player_force() return game.forces.player end
local function state() return storage.forces[player_force().index] end
local function technology(name) return player_force().technologies[name] end

-- The element of `root` whose tags hold `action` and `key` = `value`.
local function find(root, action, key, value)
  local tags = root.tags
  if tags.gb_action == action and tags[key] == value then return root end
  for _, child in ipairs(root.children) do
    local found = find(child, action, key, value)
    if found then return found end
  end
end

describe("financial engineering research", function()
  before_each(function()
    -- In storage, so that it survives the reload of the last test.
    local saved = { balance = state().balance, arrears = state().arrears, reputation = state().reputation,
      researched = {} }
    for _, name in ipairs(BRANCH) do
      saved.researched[name] = technology(name).researched
      technology(name).researched = false
    end
    storage.gb_test_finance = saved
    state().balance, state().arrears, state().overdraft_low, state().reputation = 0, 0, 0, 0
    state().contracts.open = {}
  end)
  after_each(function()
    contracts_gui.close(1)
    if storage.gb_test_finance_hub and storage.gb_test_finance_hub.valid then storage.gb_test_finance_hub.destroy() end
    storage.gb_test_finance_hub = nil
    local saved = storage.gb_test_finance
    if saved then
      for _, name in ipairs(BRANCH) do technology(name).researched = saved.researched[name] end
      state().balance, state().arrears, state().overdraft_low = saved.balance, saved.arrears, saved.balance
      state().reputation = saved.reputation
      storage.gb_test_finance = nil
    end
    state().contracts.open = {}
  end)

  test("refuse borrowing without the credit research, and name it on the Borrow buttons", function()
    for _, offer in ipairs(loans.offers(player_force().index)) do assert.are.equal("not-researched", offer.refusal) end
    assert.are.same({ nil, "not-researched" }, { loans.borrow(player_force().index, 1) })
    assert.are.equal(0, state().balance)
    local player = game.get_player(1)
    local hub = player.surface.create_entity({ name = "gb-hub", force = "player", raise_built = true,
      position = { player.position.x + 3, player.position.y } })
    storage.gb_test_finance_hub = hub
    contracts_gui.open(player, hub.unit_number)
    local button = find(player.gui.screen.gb_contracts, "loan-borrow", "tier", 1)
    assert.is_false(button.enabled)
    local refusal = button.tooltip[3][3]
    assert.are.equal("gb-loans.refused-not-researched", refusal[1])
    assert.are.same(prototypes.technology[finance.CREDIT_TECHNOLOGY].localised_name, refusal[2])
    technology(finance.CREDIT_TECHNOLOGY).researched = true
    assert.is_truthy(loans.borrow(player_force().index, 1))
    assert.are.equal(5000, state().balance)
  end)

  test("keep repaying loans and collecting arrears without the credit research", function()
    technology(finance.CREDIT_TECHNOLOGY).researched = true
    local id = loans.borrow(player_force().index, 1)
    technology(finance.CREDIT_TECHNOLOGY).researched = false
    local charge = contracts.get(player_force().index, id).charge
    contracts.on_settle_tick({ tick = game.tick + loans_core.PERIOD_TICKS })
    assert.are.equal(core.ACTIVE, contracts.get(player_force().index, id).state)
    assert.is_true(math.abs(5000 - charge - state().balance) < 1e-6)
    state().balance = 10000
    assert.are.equal(core.FULFILLED, contracts.abandon(player_force().index, id).state)
    state().arrears = 100
    loans.on_collect_tick({ tick = game.tick })
    assert.are.equal(0, state().arrears)
  end)

  test("raise the overdraft limit with each level, from the research events", function()
    assert.are.equal(#account.OVERDRAFT_LEVEL_LIMITS, #finance.OVERDRAFT_TECHNOLOGIES)
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state()))
    technology(finance.OVERDRAFT_TECHNOLOGIES[1]).researched = true
    assert.are.equal(1, state().overdraft_level)
    assert.are.equal(account.OVERDRAFT_LEVEL_LIMITS[1], account.overdraft_limit(state()))
    technology(finance.OVERDRAFT_TECHNOLOGIES[2]).researched = true
    assert.are.equal(account.OVERDRAFT_LEVEL_LIMITS[2], account.overdraft_limit(state()))
    state().balance = -account.OVERDRAFT_LEVEL_LIMITS[1]
    assert.is_true(account.apply(state(), -1, { tick = game.tick, kind = "gb-test" }))
    technology(finance.OVERDRAFT_TECHNOLOGIES[2]).researched = false
    assert.are.equal(1, state().overdraft_level)
    assert.are.same({ false, "insufficient-funds" }, { account.apply(state(), -1, { tick = game.tick }) })
  end)

  test("give a level only half its extra limit to a force of poor reputation", function()
    technology(finance.OVERDRAFT_TECHNOLOGIES[1]).researched = true
    state().reputation = -20
    local base = account.BASE_OVERDRAFT_LIMIT
    assert.are.equal(base + (account.OVERDRAFT_LEVEL_LIMITS[1] - base) / 2, account.overdraft_limit(state()))
  end)

  test("heal a stale level at the interest tick, before interest is charged", function()
    state().overdraft_level = 2
    state().balance, state().overdraft_low = -20000, -20000
    forces.on_interest_tick({ tick = game.tick })
    assert.are.equal(0, state().overdraft_level)
    local charged = account.BASE_OVERDRAFT_LIMIT * account.INTEREST_RATE
    assert.is_true(math.abs(-20000 - charged - state().balance) < 1e-6)
  end)

  test("refresh a force's level when its technology effects are reset, and drop it when it is reset", function()
    local force = game.create_force("gb-test-finance")
    force.technologies[finance.OVERDRAFT_TECHNOLOGIES[1]].researched = true
    assert.are.equal(1, storage.forces[force.index].overdraft_level)
    storage.forces[force.index].overdraft_level = 0
    force.reset_technology_effects()
    assert.are.equal(1, storage.forces[force.index].overdraft_level)
    force.reset()
    assert.are.equal(0, storage.forces[force.index].overdraft_level)
    game.merge_forces(force, "player")
  end)

  test("give saves made before the levels the level of their research on configuration change", function()
    state().overdraft_level = nil
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state()))
    finance.init()
    assert.are.equal(0, state().overdraft_level)
    technology(finance.OVERDRAFT_TECHNOLOGIES[1]).researched = true
    state().overdraft_level = nil
    finance.init()
    assert.are.equal(account.OVERDRAFT_LEVEL_LIMITS[1], account.overdraft_limit(state()))
  end)

  test("keep the stored level across a save and reload, without recomputing it", function()
    technology(finance.OVERDRAFT_TECHNOLOGIES[1]).researched = true
    -- A level research does not give: a recomputation on load would bring it back to 1.
    state().overdraft_level = 2
  end).after_reload_mods(function()
    assert.are.equal(2, storage.forces[game.forces.player.index].overdraft_level)
  end)
end)
