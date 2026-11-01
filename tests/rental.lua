-- In-game tests of machine capacity rental (scripts/rental.lua, #78): offers for idle machines,
-- acceptance, the machine working only for the counterparty, installments and release.
local test_helpers = require("tests.helpers")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local incoming = require("scripts.incoming_contracts")
local offers = require("scripts.core.contract_offers")
local rental = require("scripts.rental")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 310 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local function module_of(entity) return storage.rentals.machines[entity.unit_number] end

-- Rents `machine` for `crafts` gears, as an offer would, without the draw.
local function rent(machine, crafts)
  local id = contracts.offer(force().index, {
    kind = "rental", counterparty = "Test",
    provides = { { kind = "item", name = "iron-plate", count = 2 * crafts } },
    requires = { { kind = "item", name = "iron-gear-wheel", count = crafts } },
    reward = 300, deposit = 50, penalty = 100, duration_ticks = 36000, accept_ticks = 600,
    installment_ticks = 600, passive = true,
  })
  local module = module_of(machine)
  module.contract, module.recipe, module.crafts, module.provided = id, "iron-gear-wheel", crafts, {}
  return id
end

describe("capacity rental", function()
  local machine
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_rental = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
      researched = force().technologies[rental.TECHNOLOGY].researched,
    }
    test_helpers.set_balance(state(), 1e6)
    state().contracts.open = {}
    place("gb-hub", 0)
    machine = place(rental.NAME, 5)
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    local saved = storage.gb_test_rental
    if saved then
      test_helpers.set_balance(state(), saved.balance)
      state().reputation = saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      force().technologies[rental.TECHNOLOGY].researched = saved.researched
      storage.gb_test_rental = nil
    end
    state().contracts.open = {}
  end)

  test("the rental assembler is unlocked by the rental technology, closed and without module slots", function()
    local unlocked = false
    for _, effect in pairs(prototypes.technology[rental.TECHNOLOGY].effects) do
      if effect.type == "unlock-recipe" and effect.recipe == rental.NAME then unlocked = true end
    end
    assert.is_true(unlocked)
    assert.is_false(machine.operable)
    assert.are.equal(0, prototypes.entity[rental.NAME].module_inventory_size)
  end)

  test("an idle machine is offered once researched, for a recipe it can craft, and stays idle", function()
    force().technologies[rental.TECHNOLOGY].researched = false
    rental.on_offer_tick()
    assert.is_nil(module_of(machine).contract)
    force().technologies[rental.TECHNOLOGY].researched = true
    rental.on_offer_tick()
    local id = module_of(machine).contract
    local contract = contracts.get(force().index, id)
    assert.are.same({ "rental", core.OFFERED }, { contract.kind, contract.state })
    local recipe = force().recipes[module_of(machine).recipe]
    local craftable = false
    for _, category in ipairs(recipe.prototype.categories) do
      if machine.prototype.crafting_categories[category] then craftable = true end
    end
    assert.is_true(craftable)
    assert.is_true(contract.installment_ticks > 0 and contract.passive)
    -- The rent pays the machine's time, whatever the recipe's products are worth (#122).
    assert.is_true(math.abs(contract.reward - offers.RENT_PER_SECOND * recipe.energy * module_of(machine).crafts)
      < 1e-6)
    rental.on_offer_tick()
    assert.are.equal(id, module_of(machine).contract)
    rental.on_service_tick()
    assert.is_nil(machine.get_recipe())
  end)

  test("acceptance holds the guarantee and sets the counterparty's recipe and ingredients", function()
    local id = rent(machine, 100)
    assert.is_true(rental.accept(force().index, id))
    assert.is_true(state().balance <= 1e6 - 150)
    assert.are.equal("iron-gear-wheel", machine.get_recipe().name)
    rental.on_service_tick()
    local plates = machine.get_inventory(defines.inventory.crafter_input).get_item_count("iron-plate")
    assert.is_true(plates > 0 and plates <= 2 * 100)
    assert.are.equal(plates, module_of(machine).provided["iron-plate"])
  end)

  test("acceptance from a zero balance puts the guarantee on overdraft", function()
    test_helpers.set_balance(state(), 0)
    local id = rent(machine, 100)
    assert.is_true(rental.accept(force().index, id))
    assert.is_true(state().balance <= -150)
    assert.are.equal(core.ACTIVE, contracts.get(force().index, id).state)
  end)

  test("never provides more ingredients than the contract", function()
    local id = rent(machine, 1)
    rental.accept(force().index, id)
    rental.on_service_tick()
    machine.get_inventory(defines.inventory.crafter_input).clear()
    rental.on_service_tick()
    assert.are.equal(0, machine.get_inventory(defines.inventory.crafter_input).get_item_count("iron-plate"))
  end)

  test("a powered machine crafts for the contract, which pays installments for what it made", function()
    local generator = place("electric-energy-interface", 5, 315)
    generator.electric_interface_mode = defines.electric_interface_mode.primary_output
    generator.power_production = 1e6 / 60
    generator.electric_buffer_size = 1e6 / 60
    place("medium-electric-pole", 2, 313)
    local id = rent(machine, 100)
    rental.accept(force().index, id)
    local before = state().balance
    after_ticks(600, function()
      rental.on_service_tick()
      local delivered = contracts.get(force().index, id).delivered["item/iron-gear-wheel"]
      assert.is_true(delivered > 0)
      assert.are.equal(0, machine.get_output_inventory().get_item_count("iron-gear-wheel"))
      contracts.get(force().index, id).next_installment = game.tick
      contracts.on_settle_tick({ tick = game.tick })
      assert.is_true(math.abs(state().balance - before - 300 * delivered / 100) < 1e-6)
    end)
  end)

  test("a fulfilled rental pays the rest of the rent and the guarantee, earns no reputation, and frees the machine",
    function()
    local id = rent(machine, 10)
    rental.accept(force().index, id)
    local guarantee = core.guarantee(contracts.get(force().index, id))
    local before, score = state().balance, state().reputation
    machine.get_output_inventory().insert({ name = "iron-gear-wheel", count = 4 })
    rental.on_service_tick()
    contracts.get(force().index, id).next_installment = game.tick
    contracts.on_settle_tick({ tick = game.tick })
    assert.is_true(math.abs(state().balance - before - 120) < 1e-6)
    machine.get_output_inventory().insert({ name = "iron-gear-wheel", count = 7 })
    rental.on_service_tick()
    assert.are.equal(0, machine.get_output_inventory().get_item_count("iron-gear-wheel"))
    contracts.on_settle_tick({ tick = game.tick })
    assert.is_true(math.abs(state().balance - before - 300 - guarantee) < 1e-6)
    assert.are.equal(score, state().reputation)
    rental.on_service_tick()
    assert.is_nil(module_of(machine).contract)
    assert.is_nil(machine.get_recipe())
  end)

  test("a machine whose contract ended is released, and a pasted recipe is undone", function()
    local id = rent(machine, 100)
    rental.accept(force().index, id)
    machine.get_output_inventory().insert({ name = "stone", count = 1 })
    local arrears = state().arrears
    assert.are.equal(core.FAILED, contracts.abandon(force().index, id).state)
    assert.are.equal(arrears, state().arrears)
    rental.on_service_tick()
    assert.is_nil(module_of(machine).contract)
    assert.is_nil(machine.get_recipe())
    assert.is_true(machine.get_output_inventory().is_empty())
    machine.set_recipe("iron-gear-wheel")
    rental.on_settings_pasted({ destination = machine })
    assert.is_nil(machine.get_recipe())
  end)

  test("a rental whose recipe the machine can no longer craft is voided on configuration change", function()
    local id = rent(machine, 10)
    rental.accept(force().index, id)
    local before = state().balance
    local guarantee = core.guarantee(contracts.get(force().index, id))
    module_of(machine).recipe = "gb-test-vanished"
    rental.init()
    assert.is_nil(contracts.get(force().index, id))
    assert.is_true(math.abs(state().balance - before - guarantee) < 1e-6)
    assert.is_nil(module_of(machine).contract)
    assert.is_nil(machine.get_recipe())
  end)

  test("an offer on the terms before 0.1.39 is declined on configuration change, an accepted one kept",
    function()
    local id = rent(machine, 10)
    local offered = contracts.get(force().index, id)
    offered.passive = nil
    rental.init()
    assert.is_nil(contracts.get(force().index, id))
    assert.is_nil(module_of(machine).contract)
    local kept = rent(machine, 10)
    rental.accept(force().index, kept)
    contracts.get(force().index, kept).passive = nil
    rental.init()
    assert.are.equal(core.ACTIVE, contracts.get(force().index, kept).state)
    assert.are.equal(kept, module_of(machine).contract)
  end)

  test("only recipes the machine can craft where it stands are offered", function()
    local space = force().recipes["space-science-pack"]
    local enabled = space and space.enabled
    if space then space.enabled = true end
    local names, unfiltered = {}, {}
    for _, recipe in ipairs(rental.candidates(machine)) do names[recipe.name] = true end
    for _, recipe in ipairs(incoming.candidates(force(), machine.prototype.crafting_categories)) do
      unfiltered[recipe.name] = true
    end
    if space then space.enabled = enabled end
    assert.is_true(names["iron-gear-wheel"])
    -- With Space Age, the space science pack could be crafted by the machine, but not on Nauvis.
    assert.are.equal(space ~= nil, unfiltered["space-science-pack"] == true)
    assert.is_nil(names["space-science-pack"])
  end)

  test("acceptance is refused without a hub to serve the machine", function()
    local id = rent(machine, 10)
    module_of(machine).hub = nil
    assert.are.same({ false, "machine-no-hub" }, { rental.accept(force().index, id) })
    assert.is_nil(machine.get_recipe())
  end)

  test("acceptance is refused once the machine is gone", function()
    local id = rent(machine, 10)
    machine.destroy()
    after_ticks(1, function()
      assert.are.same({ false, "machine-gone" }, { rental.accept(force().index, id) })
      assert.are.equal(core.OFFERED, contracts.get(force().index, id).state)
    end)
  end)

  test("keeps rental assemblers across a save and reload", function()
    storage.gb_test_rental_machine = machine.unit_number
    storage.gb_test_rental_created = created
  end).after_reload_mods(function()
    -- After a reload the file runs again and its locals start empty: this test cleans up itself.
    local module = storage.rentals.machines[storage.gb_test_rental_machine]
    local attached = module ~= nil and module.hub ~= nil
    for _, entity in ipairs(storage.gb_test_rental_created) do
      if entity.valid then entity.destroy() end
    end
    storage.gb_test_rental_machine, storage.gb_test_rental_created = nil, nil
    assert.is_true(attached)
  end)
end)
