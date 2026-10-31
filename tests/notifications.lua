-- In-game tests of notifications (scripts/notifications.lua, #107): each kind raises its alert once,
-- from the feature that tells it (offers, contract settlement, deliveries, loans, insolvency); a
-- player's category setting turned off suppresses it; throttling groups deliveries per hub and tells a
-- contract due soon once; the throttle log survives a reload and goes with a merged force.
local test_helpers = require("tests.helpers")
local account = require("scripts.core.account")
local contracts = require("scripts.contracts")
local core = require("scripts.core.notifications")
local core_contracts = require("scripts.core.contracts")
local core_insolvency = require("scripts.core.insolvency")
local finance = require("scripts.finance")
local freight = require("scripts.freight")
local incoming = require("scripts.incoming_contracts")
local insolvency = require("scripts.insolvency")
local loans = require("scripts.loans")
local loans_core = require("scripts.core.loans")
local notifications = require("scripts.notifications")
local rental = require("scripts.rental")

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local function player() return game.get_player(1) end
local function setting(category) return core.CATEGORIES[category] end
-- The balance at which the player force has `available` funds left, overdraft included.
local function funds(available) return available - account.overdraft_limit(state()) end
local function check() insolvency.on_check_tick({ tick = game.tick }) end

-- Restored after each test.
local FIELDS = { "balance", "reputation", "arrears", "bankruptcies" }

-- The test player's custom alerts of `kind`.
local function alerts(kind)
  local found = {}
  for _, by_type in pairs(player().get_alerts({ type = defines.alert_type.custom })) do
    for _, list in pairs(by_type) do
      for _, alert in ipairs(list) do
        if alert.message and alert.message[1] == "gb-notify." .. kind then found[#found + 1] = alert end
      end
    end
  end
  return found
end

local function clear_alerts() player().remove_alert({ type = defines.alert_type.custom }) end

-- Places `name` `dx` tiles east of the test player; destroyed after each test.
local function place(name, dx)
  local entity = player().surface.create_entity({ name = name, force = "player", raise_built = true,
    position = { player().position.x + dx, player().position.y + 40 } })
  table.insert(storage.gb_test_notifications_entities, entity)
  return entity
end

-- An active incoming contract requiring 10 gears, due in `due_in` ticks; returns it.
local function active_contract(due_in)
  local id = contracts.offer(force().index, {
    kind = "incoming", counterparty = "test", provides = {},
    requires = { { kind = "item", name = "iron-gear-wheel", count = 10 } },
    reward = 100, deposit = 0, penalty = 50, duration_ticks = due_in, accept_ticks = 600,
  })
  assert.is_true(contracts.accept(force().index, id))
  return contracts.get(force().index, id)
end

describe("notifications", function()
  before_each(function()
    local saved = { history = #state().contracts.history, entities = {}, settings = {},
      contracts_researched = force().technologies[incoming.TECHNOLOGY].researched,
      rental_researched = force().technologies[rental.TECHNOLOGY].researched,
      credit = force().technologies[finance.CREDIT_TECHNOLOGY].researched }
    for _, field in ipairs(FIELDS) do saved[field] = state()[field] end
    for _, name in pairs(core.CATEGORIES) do saved.settings[name] = player().mod_settings[name].value end
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_notifications = saved
    storage.gb_test_notifications_entities = {}
    for _, name in pairs(core.CATEGORIES) do player().mod_settings[name] = { value = true } end
    test_helpers.set_balance(state(), 1e6)
    state().reputation, state().arrears = 0, 0
    state().contracts.open = {}
    storage.notifications[force().index] = nil
    clear_alerts()
  end)
  after_each(function()
    for _, entity in ipairs(storage.gb_test_notifications_entities or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    storage.gb_test_notifications_entities = nil
    local saved = storage.gb_test_notifications
    if saved then
      for _, field in ipairs(FIELDS) do state()[field] = saved[field] end
      test_helpers.set_balance(state(), saved.balance)
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      for name, value in pairs(saved.settings) do player().mod_settings[name] = { value = value } end
      force().technologies[incoming.TECHNOLOGY].researched = saved.contracts_researched
      force().technologies[rental.TECHNOLOGY].researched = saved.rental_researched
      force().technologies[finance.CREDIT_TECHNOLOGY].researched = saved.credit
      storage.gb_test_notifications = nil
    end
    state().insolvent_since, state().recovering_since, state().credit_ban_until = nil, nil, nil
    state().bankruptcy_debt = 0
    state().contracts.open = {}
    storage.notifications[force().index] = nil
    clear_alerts()
  end)

  test("every kind has an icon the game knows, a message in the locale and a per-user setting", function()
    for kind, spec in pairs(core.KINDS) do
      local known = spec.icon.type == "item" and prototypes.item[spec.icon.name]
        or prototypes.virtual_signal[spec.icon.name]
      assert.is_truthy(known, kind)
    end
    for _, name in pairs(core.CATEGORIES) do
      assert.are.equal("runtime-per-user", prototypes.mod_setting[name].setting_type)
    end
  end)

  test("an alert without a building points at a hub of the force", function()
    place("gb-hub", 0)
    assert.are.equal(1, notifications.notify(force(), "recovered", {}))
    local found = alerts("recovered")
    assert.are.equal(1, #found)
    assert.are.equal("gb-hub", found[1].target.name)
    assert.are.equal(force(), found[1].target.force)
  end)

  test("a new incoming offer is told", function()
    place("gb-hub", 0)
    assert.is_truthy(incoming.make_offer(force()))
    assert.are.equal(1, #alerts("contract-offer"))
  end)

  test("a new rental offer is told, pointing at the machine", function()
    place("gb-hub", 0)
    local machine = place(rental.NAME, 5)
    assert.is_truthy(rental.make_offer(storage.rentals.machines[machine.unit_number]))
    local found = alerts("contract-offer")
    assert.are.equal(1, #found)
    assert.are.equal(machine, found[1].target)
  end)

  test("offers of one kind are told once a minute", function()
    place("gb-hub", 0)
    local first = contracts.offer(force().index, {
      kind = "incoming", counterparty = "test", provides = {},
      requires = { { kind = "item", name = "iron-gear-wheel", count = 1 } },
      reward = 1, deposit = 0, penalty = 0, duration_ticks = 600, accept_ticks = 600,
    })
    local contract = contracts.get(force().index, first)
    assert.are.equal(1, notifications.contract(force().index, "contract-offer", contract))
    assert.are.equal(0, notifications.contract(force().index, "contract-offer", contract))
    contract.kind = "rental"
    assert.are.equal(1, notifications.contract(force().index, "contract-offer", contract))
  end)

  test("a contract due soon is told once, then its failure", function()
    place("gb-hub", 0)
    local contract = active_contract(core.DUE_SOON_TICKS - 60)
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(1, #alerts("contract-due"))
    clear_alerts()
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(0, #alerts("contract-due"))
    contracts.on_settle_tick({ tick = contract.due_tick + 1 })
    assert.are.equal(1, #alerts("contract-failed"))
  end)

  test("a contract not yet due soon is not told due, and its fulfilment is told", function()
    place("gb-hub", 0)
    local contract = active_contract(core.DUE_SOON_TICKS + 600)
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(0, #alerts("contract-due"))
    contracts.deliver(force().index, contract.id, "item/iron-gear-wheel", 10)
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(0, #alerts("contract-due"))
    assert.are.equal(1, #alerts("contract-fulfilled"))
  end)

  test("a loan default is told with its arrears", function()
    place("gb-hub", 0)
    force().technologies[finance.CREDIT_TECHNOLOGY].researched = true
    test_helpers.set_balance(state(), 0)
    local id = loans.borrow(force().index, 1)
    local charge = contracts.get(force().index, id).charge
    test_helpers.set_balance(state(), funds(charge - 1))
    contracts.on_settle_tick({ tick = game.tick + loans_core.PERIOD_TICKS })
    assert.are.equal(core_contracts.FAILED, state().contracts.history[#state().contracts.history].state)
    assert.are.equal(1, #alerts("loan-defaulted"))
    assert.are.equal(0, #alerts("contract-failed"))
  end)

  test("shipments landing at a hub in one pass are told in one alert, then not again within the period",
    function()
      local hub = place("gb-hub", 0)
      place("gb-import-chest", 3)
      local goods = { { kind = "item", name = "iron-plate", count = 100 },
        { kind = "item", name = "copper-plate", count = 100 } }
      assert.is_true(freight.ship(force().index, hub.unit_number, goods))
      for _, capsule in ipairs(freight.capsules(hub.unit_number)) do capsule.arrival = game.tick end
      freight.on_unload_tick({ tick = game.tick })
      local found = alerts("delivery-landed")
      assert.are.equal(1, #found)
      assert.are.equal(hub, found[1].target)
      assert.are.equal("2", found[1].message[2]) -- the game hands parameters back as text
      clear_alerts()
      assert.is_true(freight.ship(force().index, hub.unit_number, { goods[1] }))
      for _, capsule in ipairs(freight.capsules(hub.unit_number)) do capsule.arrival = game.tick end
      freight.on_unload_tick({ tick = game.tick })
      assert.are.equal(0, #freight.capsules(hub.unit_number))
      assert.are.equal(0, #alerts("delivery-landed"))
    end)

  test("insolvency, recovery, bankruptcy and credit restored are each told", function()
    place("gb-hub", 0)
    test_helpers.set_balance(state(), funds(-100))
    check()
    assert.are.equal(1, #alerts("insolvent"))
    test_helpers.set_balance(state(), 0)
    state().insolvent_since = game.tick
    state().recovering_since = game.tick - core_insolvency.RECOVERY_TICKS
    check()
    assert.are.equal(1, #alerts("recovered"))
    test_helpers.set_balance(state(), funds(-100))
    state().insolvent_since = game.tick - core_insolvency.GRACE_TICKS
    check()
    assert.are.equal(1, #alerts("bankrupt"))
    state().bankruptcy_debt, state().credit_ban_until = 0, game.tick - 1
    test_helpers.set_balance(state(), 0)
    check()
    assert.are.equal(1, #alerts("credit-restored"))
  end)

  test("a category turned off by the player shows nothing of its kinds", function()
    place("gb-hub", 0)
    player().mod_settings[setting("finance")] = { value = false }
    test_helpers.set_balance(state(), funds(-100))
    check()
    assert.is_true(core_insolvency.insolvent(state()))
    assert.are.equal(0, #alerts("insolvent"))
    player().mod_settings[setting("deliveries")] = { value = false }
    assert.are.equal(0, notifications.notify(force(), "delivery-landed", { 1 }))
    assert.are.equal(1, notifications.notify(force(), "contract-failed", { "x", "0:00", "", "0" }))
  end)

  test("a merged force's throttle log goes", function()
    storage.notifications[force().index] = {}
    notifications.notify(force(), "delivery-landed", { 1, group = 1 })
    assert.is_truthy(next(storage.notifications[force().index]))
    notifications.on_forces_merged({ source_index = force().index })
    assert.is_nil(storage.notifications[force().index])
  end)

  test("the throttle log survives a save and reload", function()
    assert.are.equal(1, notifications.notify(force(), "delivery-landed", { 1, group = 42 }))
  end).after_reload_mods(function()
    assert.are.equal(0, notifications.notify(game.forces.player, "delivery-landed", { 1, group = 42 }))
  end)
end)
