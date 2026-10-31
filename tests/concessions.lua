-- In-game tests of mining concessions (scripts/concessions.lua, #85): leasing a planet's slot, the
-- charge per period shipped, defaults, the end of the term and the lease button of the planets window.
local concessions = require("scripts.concessions")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local freight = require("scripts.freight")
local market_gui = require("scripts.market_gui")
local planets = require("scripts.planets")
local planets_gui = require("scripts.planets_gui")

local player, created
local function place(name, dx, dy)
  local entity = player.surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + dy }, force = "player",
    raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function force_index() return game.forces.player.index end
local function recipe_of(name) return game.forces.player.recipes[name] end
local function state() return storage.forces[force_index()] end

local function find(element, action, resource)
  if element.tags.gb_action == action and (resource == nil or element.tags.resource == resource) then
    return element
  end
  for _, child in ipairs(element.children) do
    local found = find(child, action, resource)
    if found then return found end
  end
end

-- Runs the period of contract `id` now.
local function run_period(id)
  contracts.get(force_index(), id).next_installment = game.tick
  contracts.on_settle_tick({ tick = game.tick })
end

describe("mining concessions", function()
  local hub
  before_each(function()
    player = game.get_player(1)
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_concessions = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
      reservations = state().reservations,
    }
    state().balance = 1e6
    state().contracts.open = {}
    state().reservations = {}
    hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 6, 0)
  end)
  after_each(function()
    player = game.get_player(1)
    market_gui.close(1)
    planets_gui.close(1)
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    local saved = storage.gb_test_concessions
    if saved then
      state().balance, state().reputation = saved.balance, saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      state().reservations = saved.reservations
      storage.gb_test_concessions = nil
    end
    state().contracts.open = {}
    storage.concessions = {}
  end)

  test("a lease reserves a slot and holds one period's charge as guarantee", function()
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    local contract = contracts.get(force_index(), id)
    assert.are.same({ "concession", core.ACTIVE }, { contract.kind, contract.state })
    assert.are.equal(3, planets.free(force_index(), "ferrum-prime", "resource", "iron-ore"))
    assert.is_true(math.abs(1e6 - contract.deposit - state().balance) < 1e-6)
    assert.are.equal(contract.charge, contract.deposit)
  end)

  test("each period ships the ore by transit and takes the charge", function()
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    local before = state().balance
    local charge = contracts.get(force_index(), id).charge
    run_period(id)
    local capsules = freight.capsules(hub.unit_number)
    assert.is_true(#capsules > 0)
    assert.are.equal(id, capsules[1].contract)
    assert.is_true(capsules[1].arrival > game.tick + freight.TIERS.capsule.delay_ticks)
    assert.is_true(math.abs(before - charge - state().balance) < 1e-6)
  end)

  test("a period that cannot ship is not charged", function()
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    local before = state().balance
    storage.concessions[id].hub = 1e9
    run_period(id)
    assert.are.equal(before, state().balance)
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
  end)

  test("a force that cannot pay defaults, and the slot is released", function()
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "copper-ore")
    state().balance = 0
    local reputation = state().reputation
    run_period(id)
    assert.is_nil(contracts.get(force_index(), id))
    assert.are.equal(reputation - 1, state().reputation)
    concessions.on_sweep_tick()
    assert.are.equal(2, planets.free(force_index(), "ferrum-prime", "resource", "copper-ore"))
    assert.is_nil(storage.concessions[id])
  end)

  test("the end of the term gives the guarantee back, without reputation", function()
    local id = concessions.lease(force_index(), hub.unit_number, "carbo", "coal")
    local contract = contracts.get(force_index(), id)
    local before, reputation = state().balance, state().reputation
    -- Every period up to the deadline was charged.
    contract.next_installment = contract.due_tick + 1
    contracts.on_settle_tick({ tick = contract.due_tick + 1 })
    assert.is_true(math.abs(before + contract.deposit - state().balance) < 1e-6)
    assert.are.equal(reputation, state().reputation)
  end)

  test("leases are refused without capacity, an import chest or the guarantee", function()
    concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "copper-ore")
    concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "copper-ore")
    assert.are.same({ nil, "no-capacity" },
      { concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "copper-ore") })
    assert.are.same({ nil, "unknown-specialty" },
      { concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "coal") })
    state().balance = 0
    assert.are.same({ nil, "insufficient-funds" },
      { concessions.lease(force_index(), hub.unit_number, "carbo", "coal") })
    state().balance = 1e6
    for _ = 1, contracts.MAX_LISTED - #contracts.listed(force_index()) do
      concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
      concessions.lease(force_index(), hub.unit_number, "carbo", "stone")
    end
    assert.are.same({ nil, "too-many-contracts" },
      { concessions.lease(force_index(), hub.unit_number, "uranos-deep", "uranium-ore") })
    state().contracts.open = {}
    local bare = place("gb-hub", -30, 0)
    assert.are.same({ nil, "no-import-chest" }, { concessions.lease(force_index(), bare.unit_number, "carbo", "coal") })
  end)

  test("ore paid for is sold back if its hub is removed before it lands", function()
    local id = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    run_period(id)
    local after_charge = state().balance
    local unit_number = hub.unit_number
    hub.destroy()
    after_ticks(1, function()
      assert.is_true(state().balance > after_charge)
      assert.are.equal(0, freight.queued(unit_number))
    end)
  end)

  test("a lease whose specialty is gone is voided on configuration change", function()
    local id = concessions.lease(force_index(), hub.unit_number, "carbo", "coal")
    local before = state().balance
    local deposit = contracts.get(force_index(), id).deposit
    local reservation = state().reservations[1]
    concessions.init({ [force_index()] = { reservation } })
    assert.is_nil(contracts.get(force_index(), id))
    assert.is_true(math.abs(before + deposit - state().balance) < 1e-6)
    assert.is_nil(storage.concessions[id])
  end)

  test("leases follow a merged force", function()
    local source = game.create_force("gb-test-concessions")
    storage.forces[source.index].balance = 1e6
    local id = concessions.lease(source.index, hub.unit_number, "carbo", "coal")
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.are.equal(force_index(), storage.concessions[id].force_index)
      assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
      assert.are.equal(3, planets.free(force_index(), "carbo", "resource", "coal"))
    end)
  end)

  test("the planets window leases a slot at its hub", function()
    market_gui.open(player, hub)
    market_gui.on_gui_click({ element = find(player.gui.screen.gb_market, "planets"), player_index = 1 })
    local window = player.gui.screen.gb_planets
    local button = find(window, "planets-lease", "stone")
    assert.is_true(button.enabled)
    planets_gui.on_gui_click({ element = button, player_index = 1 })
    local id, lease = next(storage.concessions)
    assert.are.same({ hub.unit_number, "carbo", "stone" }, { lease.hub, lease.planet, lease.item })
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
    assert.are.equal(2, planets.free(force_index(), "carbo", "resource", "stone"))
  end)

  test("a booking crafts the force's recipe on a planet and ships its products", function()
    local id = concessions.book(force_index(), hub.unit_number, "fabrica-nova", "crafting", "iron-gear-wheel")
    local contract = contracts.get(force_index(), id)
    assert.are.same({ "outsourcing", core.ACTIVE }, { contract.kind, contract.state })
    assert.are.equal(3, planets.free(force_index(), "fabrica-nova", "crafting", "crafting"))
    local before = state().balance
    run_period(id)
    local capsules = freight.capsules(hub.unit_number)
    assert.are.equal("iron-gear-wheel", capsules[1].name)
    assert.is_true(math.abs(before - contract.charge - state().balance) < 1e-6)
  end)

  test("bookings are refused without a recipe, for a locked one or the wrong category", function()
    local function reason(category, recipe)
      return select(2, concessions.book(force_index(), hub.unit_number, "fabrica-nova", category, recipe))
    end
    assert.are.equal("no-recipe", reason("crafting", nil))
    assert.are.equal("wrong-category", reason("advanced-crafting", "iron-gear-wheel"))
    local locked = recipe_of("rocket-silo")
    local enabled = locked.enabled
    locked.enabled = false
    assert.are.equal("recipe-locked", reason("crafting", "rocket-silo"))
    locked.enabled = enabled
    assert.are.equal("unknown-specialty",
      select(2, concessions.book(force_index(), hub.unit_number, "carbo", "crafting", "iron-gear-wheel")))
  end)

  test("the planets window books the chosen recipe", function()
    market_gui.open(player, hub)
    market_gui.on_gui_click({ element = find(player.gui.screen.gb_market, "planets"), player_index = 1 })
    local button
    for _, row in ipairs(storage.planets_gui[1].elements.rows) do
      if row.planet == "fabrica-nova" and row.name == "crafting" then button = row.book end
    end
    button.parent.children[1].elem_value = "iron-gear-wheel"
    planets_gui.on_gui_click({ element = button, player_index = 1 })
    local id, lease = next(storage.concessions)
    assert.are.same({ "iron-gear-wheel", 600 }, { lease.item, lease.units })
    assert.are.equal("outsourcing", contracts.get(force_index(), id).kind)
  end)

  test("leases saved by 0.1.21 are converted on configuration change", function()
    local id = concessions.lease(force_index(), hub.unit_number, "carbo", "stone")
    storage.concessions[id] = { force_index = force_index(), hub = hub.unit_number, planet = "carbo",
      resource = "stone", slots = 1 }
    concessions.init({})
    local lease = storage.concessions[id]
    assert.are.same({ "stone", 150 }, { lease.item, lease.units })
    assert.is_nil(lease.resource)
    assert.is_nil(lease.slots)
  end)

  test("keeps leases across a save and reload", function()
    storage.gb_test_concession_id = concessions.lease(force_index(), hub.unit_number, "carbo", "stone")
    storage.gb_test_concession_created = created
  end).after_reload_mods(function()
    -- After a reload the file runs again and its locals start empty: this test cleans up itself.
    local id = storage.gb_test_concession_id
    local kept = storage.concessions[id] ~= nil
      and contracts.get(game.forces.player.index, id).state == core.ACTIVE
    for _, entity in ipairs(storage.gb_test_concession_created) do
      if entity.valid then entity.destroy() end
    end
    storage.gb_test_concession_id, storage.gb_test_concession_created = nil, nil
    assert.is_true(kept)
  end)
end)
