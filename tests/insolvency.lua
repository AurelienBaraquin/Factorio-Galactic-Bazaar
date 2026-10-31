-- In-game tests of insolvency and bankruptcy (scripts/insolvency.lua, #97, ADR-0022): becoming
-- insolvent and recovering, what is refused meanwhile and what is not, bankruptcy and its effects on
-- contracts, leases, debt, reputation and credit, the handler control.lua registers, force merge, the
-- market window's status and persistence.
local account = require("scripts.core.account")
local concessions = require("scripts.concessions")
local contracts = require("scripts.contracts")
local contracts_gui = require("scripts.contracts_gui")
local core = require("scripts.core.contracts")
local core_insolvency = require("scripts.core.insolvency")
local insolvency = require("scripts.insolvency")
local loans = require("scripts.loans")
local market = require("scripts.market")
local market_gui = require("scripts.market_gui")
local planets = require("scripts.planets")
local reputation = require("scripts.core.reputation")

local function force_index() return game.forces.player.index end
local function state() return storage.forces[force_index()] end
local function technology(name) return game.forces.player.technologies[name] end
-- The balance at which the player force has `available` funds left, overdraft included.
local function funds(available) return available - account.overdraft_limit(state()) end
local function check() insolvency.on_check_tick({ tick = game.tick }) end

local FIELDS = { "balance", "reputation", "arrears", "overdraft_low", "solvency_low", "insolvent_since",
  "credit_ban_until", "bankruptcies" }

-- Places `name` `dx` tiles east of the test player; destroyed after each test.
local function place(name, dx)
  local player = game.get_player(1)
  local entity = player.surface.create_entity({ name = name, force = "player", raise_built = true,
    position = { player.position.x + dx, player.position.y } })
  table.insert(storage.gb_test_insolvency_entities, entity)
  return entity
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

-- An incoming contract offered to the player force; returns its id.
local function offer()
  return contracts.offer(force_index(), {
    kind = "incoming", counterparty = "test", provides = {},
    requires = { { kind = "item", name = "iron-gear-wheel", count = 10 } },
    reward = 100, deposit = 0, penalty = 0, duration_ticks = 36000, accept_ticks = 36000,
  })
end

describe("insolvency", function()
  before_each(function()
    -- In storage, so that it survives the reload of the last test.
    local saved = { history = #state().contracts.history, entities = {},
      researched = technology(concessions.CONCESSION_TECHNOLOGY).researched }
    for _, field in ipairs(FIELDS) do saved[field] = state()[field] end
    storage.gb_test_insolvency = saved
    storage.gb_test_insolvency_entities = {}
    state().balance, state().reputation, state().arrears = 0, 0, 0
    state().overdraft_low, state().solvency_low = 0, 0
    state().insolvent_since, state().credit_ban_until, state().bankruptcies = nil, nil, 0
    state().contracts.open = {}
    state().markets["item/iron-gear-wheel"] = nil
  end)
  after_each(function()
    market_gui.close(1)
    contracts_gui.close(1)
    for _, entity in ipairs(storage.gb_test_insolvency_entities or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    storage.gb_test_insolvency_entities = nil
    local saved = storage.gb_test_insolvency
    if saved then
      for _, field in ipairs(FIELDS) do state()[field] = saved[field] end
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      technology(concessions.CONCESSION_TECHNOLOGY).researched = saved.researched
      storage.gb_test_insolvency = nil
    end
    state().contracts.open = {}
    state().markets["item/iron-gear-wheel"] = nil
    storage.concessions = {}
  end)

  test("become insolvent beyond the overdraft limit, and recover only after a whole period above the margin", function()
    state().balance = funds(-100)
    check()
    assert.are.equal(game.tick, state().insolvent_since)
    -- A sale at the check is not a recovery: the period's lowest balance was beyond the limit.
    assert.is_true(account.apply(state(), 20000, { tick = game.tick, kind = "sell" }))
    check()
    assert.is_true(core_insolvency.insolvent(state()))
    check()
    assert.is_nil(state().insolvent_since)
  end)

  test("become insolvent while owing arrears the available funds cannot cover", function()
    state().arrears = 50000
    loans.on_collect_tick({ tick = game.tick })
    check()
    assert.is_true(core_insolvency.insolvent(state()))
  end)

  test("refuse contracts and loans while insolvent, but let the force sell", function()
    state().arrears = 50000
    check()
    local id = offer()
    assert.are.same({ false, "insolvent" }, { contracts.accept(force_index(), id) })
    assert.are.equal(core.OFFERED, contracts.get(force_index(), id).state)
    assert.are.same({ nil, "insolvent" }, { loans.borrow(force_index(), 1) })
    local player = game.get_player(1)
    contracts_gui.open(player, place("gb-hub", 3).unit_number)
    local borrow = find(player.gui.screen.gb_contracts, "loan-borrow", "tier", 1)
    assert.is_false(borrow.enabled)
    assert.are.equal("gb-loans.refused-insolvent", borrow.tooltip[3][3][1])
    local ok = market.sell(force_index(), "item", "iron-gear-wheel", 10)
    assert.is_true(ok)
    assert.is_true(state().balance > 0)
  end)

  test("go bankrupt at the end of the grace period: contracts end, debt is written off, credit refused", function()
    local loan = loans.borrow(force_index(), 1)
    local offered = offer()
    state().balance, state().arrears, state().reputation = funds(-500), 3000, 10
    check()
    state().insolvent_since = game.tick - core_insolvency.GRACE_TICKS
    check()
    assert.is_nil(contracts.get(force_index(), loan))
    assert.is_nil(contracts.get(force_index(), offered))
    assert.are.equal(0, state().balance)
    assert.are.equal(0, state().arrears)
    assert.are.equal(reputation.MIN, state().reputation)
    assert.are.equal(1, state().bankruptcies)
    assert.are.equal(game.tick + core_insolvency.BAN_TICKS, state().credit_ban_until)
    assert.are.equal(core_insolvency.WRITE_OFF_KIND, state().journal[#state().journal].kind)
    assert.are.same({ nil, "credit-ban" }, { loans.borrow(force_index(), 1) })
    assert.are.same({ false, "insufficient-funds" }, { market.buy(force_index(), "item", "iron-gear-wheel", 1) })
    assert.is_truthy(contracts.accept(force_index(), offer()))
    state().credit_ban_until = game.tick
    check()
    assert.are.equal(account.BASE_OVERDRAFT_LIMIT, account.overdraft_limit(state()))
    assert.is_true((market.buy(force_index(), "item", "iron-gear-wheel", 1)))
  end)

  test("release a lease's planet slot once bankruptcy failed its contract", function()
    technology(concessions.CONCESSION_TECHNOLOGY).researched = true
    local hub = place("gb-hub", 3)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 6)
    state().balance = 1e6
    local free = planets.free(force_index(), "ferrum-prime", "resource", "iron-ore")
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    assert.are.equal(free - 1, planets.free(force_index(), "ferrum-prime", "resource", "iron-ore"))
    core_insolvency.bankrupt(state(), game.tick)
    concessions.on_sweep_tick()
    assert.is_nil(contracts.get(force_index(), id))
    assert.are.equal(free, planets.free(force_index(), "ferrum-prime", "resource", "iron-ore"))
    assert.are.equal(1e6 - state().contracts.history[#state().contracts.history].deposit, state().balance)
  end)

  test("go bankrupt from the handler control.lua registers", function()
    state().balance = funds(-1)
    state().insolvent_since = game.tick - core_insolvency.GRACE_TICKS
    after_ticks(core_insolvency.CHECK_TICKS + 1, function()
      assert.are.equal(1, state().bankruptcies)
      assert.are.equal(0, state().balance)
      assert.is_nil(state().insolvent_since)
    end)
  end)

  test("keep the clock of an insolvent force merged into a solvent one", function()
    local source = game.create_force("gb-test-insolvency")
    local source_state = storage.forces[source.index]
    local since = game.tick - 600
    source_state.balance, source_state.insolvent_since = -20000, since
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.are.equal(since, state().insolvent_since)
      assert.are.equal(-20000, state().balance)
    end)
  end)

  test("show insolvency and the credit ban with their time left in the market window", function()
    local player = game.get_player(1)
    local hub = place("gb-hub", 3)
    market_gui.open(player, hub)
    local label = storage.players[1].elements.solvency
    assert.is_false(label.visible)
    market_gui.close(1)
    state().insolvent_since = game.tick
    market_gui.open(player, hub)
    label = storage.players[1].elements.solvency
    assert.is_true(label.visible)
    assert.are.equal("gb-gui.insolvent", label.caption[1])
    assert.are.equal("10:00", label.caption[2])
    market_gui.close(1)
    state().insolvent_since, state().credit_ban_until = nil, game.tick + core_insolvency.BAN_TICKS
    market_gui.open(player, hub)
    assert.are.equal("gb-gui.credit-ban", storage.players[1].elements.solvency.caption[1])
  end)

  test("keep insolvency and the credit ban across a save and reload", function()
    state().balance = -1
    state().insolvent_since, state().credit_ban_until = game.tick, game.tick + core_insolvency.BAN_TICKS
    storage.gb_test_insolvency_tick = game.tick
  end).after_reload_mods(function()
    local saved = storage.forces[game.forces.player.index]
    local tick = storage.gb_test_insolvency_tick
    storage.gb_test_insolvency_tick = nil
    assert.are.equal(tick, saved.insolvent_since)
    assert.are.equal(tick + core_insolvency.BAN_TICKS, saved.credit_ban_until)
    assert.are.equal(0, account.overdraft_limit(saved))
    assert.are.same({ nil, "insolvent" }, { loans.borrow(game.forces.player.index, 1) })
  end)
end)
