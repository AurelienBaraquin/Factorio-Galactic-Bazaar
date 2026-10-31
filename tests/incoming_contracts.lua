-- In-game tests of incoming contracts (scripts/incoming_contracts.lua, scripts/contracts_gui.lua, #76):
-- offers gated on research, ingredients shipped free on acceptance, products collected from contract
-- chests, contract cargo never sold back, and the contracts window.
local contracts = require("scripts.contracts")
local contracts_gui = require("scripts.contracts_gui")
local core = require("scripts.core.contracts")
local freight = require("scripts.freight")
local incoming = require("scripts.incoming_contracts")
local market = require("scripts.market")

local player, surface, created
local function place(name, dx, dy)
  local entity = surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + dy }, force = "player",
    raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end

local function spec()
  return {
    kind = "incoming", counterparty = "Test",
    provides = { { kind = "item", name = "iron-plate", count = 10 } },
    requires = { { kind = "item", name = "iron-gear-wheel", count = 5 } },
    reward = 500, deposit = 100, penalty = 200, duration_ticks = 600, accept_ticks = 600,
  }
end

local function find(element, action, id)
  if element.tags.gb_action == action and (id == nil or element.tags.id == id) then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action, id)
    if found then return found end
  end
end

describe("incoming contracts", function()
  local hub, import_chest
  before_each(function()
    player = game.get_player(1)
    surface = player.surface
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_incoming = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
      researched = force().technologies[incoming.TECHNOLOGY].researched,
    }
    state().balance = 1000
    state().contracts.open = {}
    hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    import_chest = place("gb-import-chest", 6, 0)
  end)
  after_each(function()
    player = game.get_player(1)
    contracts_gui.close(player.index)
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    local saved = storage.gb_test_incoming
    if saved then
      state().balance, state().reputation = saved.balance, saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      force().technologies[incoming.TECHNOLOGY].researched = saved.researched
      storage.gb_test_incoming = nil
    end
    state().contracts.open = {}
  end)

  test("the contract chest is unlocked by the contracts technology", function()
    local unlocked = false
    for _, effect in pairs(prototypes.technology[incoming.TECHNOLOGY].effects) do
      if effect.type == "unlock-recipe" and effect.recipe == incoming.CHEST then unlocked = true end
    end
    assert.is_true(unlocked)
  end)

  test("offers come only once researched, at most MAX_OFFERS open, for a recipe the force can craft", function()
    force().technologies[incoming.TECHNOLOGY].researched = false
    incoming.on_offer_tick()
    assert.is_nil(next(state().contracts.open))
    force().technologies[incoming.TECHNOLOGY].researched = true
    for _ = 1, incoming.MAX_OFFERS + 2 do incoming.on_offer_tick() end
    local count = 0
    for _, contract in pairs(state().contracts.open) do
      count = count + 1
      assert.are.equal("incoming", contract.kind)
      assert.are.equal(core.OFFERED, contract.state)
      local product = contract.requires[1].name
      local craftable = false
      for _, recipe in pairs(force().recipes) do
        if recipe.enabled and recipe.products[1] and recipe.products[1].name == product then craftable = true end
      end
      assert.is_true(craftable)
      assert.is_true(#contract.provides > 0 and contract.reward > 0)
    end
    assert.are.equal(incoming.MAX_OFFERS, count)
  end)

  test("acceptance takes the guarantee and ships the ingredients free to the hub", function()
    local id = contracts.offer(force().index, spec())
    assert.is_true(incoming.accept(force().index, id, hub.unit_number))
    assert.are.equal(700, state().balance)
    assert.are.equal(core.ACTIVE, contracts.get(force().index, id).state)
    local capsules = freight.capsules(hub.unit_number)
    assert.are.equal(1, #capsules)
    assert.are.same({ "iron-plate", 10, 0, id },
      { capsules[1].name, capsules[1].count, capsules[1].unit_cost, capsules[1].contract })
  end)

  test("acceptance after the offer's end is refused before anything ships", function()
    local id = contracts.offer(force().index, spec())
    contracts.get(force().index, id).accept_by = game.tick - 1
    assert.are.same({ false, "expired" }, { incoming.accept(force().index, id, hub.unit_number) })
    assert.are.equal(0, freight.queued(hub.unit_number))
    assert.are.equal(1000, state().balance)
  end)

  test("the penalty rises to what the ingredients sell for on the market at acceptance", function()
    local id = contracts.offer(force().index, spec())
    local sell = market.quote(force().index, "item", "iron-plate").sell
    contracts.get(force().index, id).penalty = 0
    assert.is_true(incoming.accept(force().index, id, hub.unit_number))
    local contract = contracts.get(force().index, id)
    assert.is_true(math.abs(contract.penalty - 10 * sell) < 1e-9)
    assert.is_true(math.abs(1000 - (100 + 10 * sell) - state().balance) < 1e-9)
  end)

  test("offers grow with the force's reputation", function()
    -- The same draw state gives the same recipe and counterparty at both scores.
    local rng = storage.incoming_contracts.rng
    local saved_rng = rng[force().index]
    state().reputation = 0
    local plain = contracts.get(force().index, incoming.make_offer(force()))
    rng[force().index] = saved_rng
    state().reputation = 10
    local larger = contracts.get(force().index, incoming.make_offer(force()))
    assert.are.equal(plain.requires[1].name, larger.requires[1].name)
    assert.is_true(larger.requires[1].count > plain.requires[1].count)
    assert.is_true(larger.reward > plain.reward)
  end)

  test("no more offers while the contracts window is full", function()
    force().technologies[incoming.TECHNOLOGY].researched = true
    for _ = 1, contracts.MAX_LISTED do
      contracts.accept(force().index, contracts.offer(force().index, spec()))
    end
    incoming.on_offer_tick()
    local count = 0
    for _ in pairs(state().contracts.open) do count = count + 1 end
    assert.are.equal(contracts.MAX_LISTED, count)
  end)

  test("a contract whose goods no longer exist is voided with its guarantee back", function()
    local active = contracts.offer(force().index, spec())
    contracts.accept(force().index, active)
    contracts.get(force().index, active).requires[1].name = "gb-test-vanished"
    local offered = contracts.offer(force().index, spec())
    contracts.get(force().index, offered).provides[1].name = "gb-test-vanished"
    local reputation = state().reputation
    incoming.init()
    assert.is_nil(contracts.get(force().index, active))
    assert.is_nil(contracts.get(force().index, offered))
    assert.are.equal(1000, state().balance)
    assert.are.equal(reputation, state().reputation)
    assert.are.equal(core.VOIDED, state().contracts.history[#state().contracts.history - 1].state)
  end)

  test("acceptance without an import chest is refused, changing nothing", function()
    import_chest.destroy()
    local id = contracts.offer(force().index, spec())
    assert.are.same({ false, "no-import-chest" }, { incoming.accept(force().index, id, hub.unit_number) })
    assert.are.equal(1000, state().balance)
    assert.are.equal(core.OFFERED, contracts.get(force().index, id).state)
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)

  test("the contract chest hands over what the contract needs, which then settles", function()
    local id = contracts.offer(force().index, spec())
    contracts.accept(force().index, id)
    local chest = place(incoming.CHEST, 3, 3)
    chest.insert({ name = "iron-gear-wheel", count = 7 })
    chest.insert({ name = "iron-plate", count = 3 })
    incoming.on_collect_tick()
    assert.are.equal(2, chest.get_item_count("iron-gear-wheel"))
    assert.are.equal(3, chest.get_item_count("iron-plate"))
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(1500, state().balance)
    assert.is_nil(state().contracts.open[id])
  end)

  test("a contract chest out of reach of every hub hands nothing over", function()
    local id = contracts.offer(force().index, spec())
    contracts.accept(force().index, id)
    local chest = place(incoming.CHEST, 3, incoming.HUB_RANGE + 10)
    chest.insert({ name = "iron-gear-wheel", count = 5 })
    incoming.on_collect_tick()
    assert.are.equal(5, chest.get_item_count("iron-gear-wheel"))
  end)

  test("the counterparty's goods are not sold back when the hub is removed", function()
    local id = contracts.offer(force().index, spec())
    incoming.accept(force().index, id, hub.unit_number)
    local unit_number = hub.unit_number
    hub.destroy()
    after_ticks(1, function()
      assert.are.equal(700, state().balance)
      assert.are.equal(0, freight.queued(unit_number))
    end)
  end)

  test("the contracts window lists offers, and accepts and declines them", function()
    local first = contracts.offer(force().index, spec())
    local second = contracts.offer(force().index, spec())
    contracts_gui.open(player, hub.unit_number)
    local window = player.gui.screen.gb_contracts
    assert.is_true(window ~= nil)
    contracts_gui.on_gui_click({ element = find(window, "contract-accept", first), player_index = player.index })
    assert.are.equal(core.ACTIVE, contracts.get(force().index, first).state)
    contracts_gui.on_gui_click({ element = find(window, "contract-decline", second), player_index = player.index })
    assert.is_nil(contracts.get(force().index, second))
    contracts_gui.on_gui_click({ element = find(window, "contract-abandon", first), player_index = player.index })
    assert.is_nil(contracts.get(force().index, first))
  end)

  test("the contracts window closes when its hub is removed", function()
    contracts_gui.open(player, hub.unit_number)
    hub.destroy()
    after_ticks(1, function()
      assert.is_nil(player.gui.screen.gb_contracts)
    end)
  end)

  test("keeps contract chests across a save and reload", function()
    storage.gb_test_incoming_chest = place(incoming.CHEST, 3, 3).unit_number
    storage.gb_test_incoming_created = created
  end).after_reload_mods(function()
    -- After a reload the file runs again and its locals start empty: this test cleans up itself.
    local unit_number = storage.gb_test_incoming_chest
    local module = storage.incoming_contracts.chests[unit_number]
    local attached = module ~= nil and module.hub ~= nil
    for _, entity in ipairs(storage.gb_test_incoming_created) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    storage.gb_test_incoming_chest, storage.gb_test_incoming_created = nil, nil
    assert.is_true(attached)
  end)
end)
