-- In-game tests of electromagnetic catapults (scripts/catapult.lua, #67): bulk sales one shot at a
-- time, the energy each shot draws, and the hidden capacitor's lifecycle.
local test_helpers = require("tests.helpers")
local catapult = require("scripts.catapult")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 210 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local function module_of(entity) return storage.catapults.modules[entity.unit_number] end
local MJ = 1e6

describe("electromagnetic catapult", function()
  local hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    storage.gb_test_catapult_balance = player_state().balance
    test_helpers.set_balance(player_state(), 0)
    for _, name in ipairs({ "iron-plate", "copper-plate" }) do player_state().markets["item/" .. name] = nil end
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    if storage.gb_test_catapult_balance then
      test_helpers.set_balance(player_state(), storage.gb_test_catapult_balance)
      storage.gb_test_catapult_balance = nil
    end
    for _, name in ipairs({ "iron-plate", "copper-plate" }) do player_state().markets["item/" .. name] = nil end
  end)

  test("is unlocked by the catapult technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-catapult"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-catapult"])
  end)

  test("places a capacitor under it, and removes it with the catapult", function()
    local machine = place("gb-catapult", 3)
    local capacitor = module_of(machine).capacitor
    assert.is_true(capacitor.valid)
    assert.are.equal(catapult.CAPACITOR, capacitor.name)
    assert.is_false(capacitor.destructible)
    machine.destroy()
    after_ticks(1, function()
      assert.is_false(capacitor.valid)
    end)
  end)

  test("keeps a single capacitor when an area clone copies both", function()
    place("gb-catapult", 3)
    surface.clone_area({ source_area = { { 2, 209 }, { 4, 211 } }, destination_area = { { 2, 229 }, { 4, 231 } },
      expand_map = true })
    local copies = surface.find_entities_filtered({ area = { { 2, 229 }, { 4, 231 } } })
    local capacitors = 0
    for _, entity in ipairs(copies) do
      created[#created + 1] = entity
      if entity.name == catapult.CAPACITOR then capacitors = capacitors + 1 end
    end
    assert.are.equal(1, capacitors)
  end)

  test("visits catapults in turn, passing over empty ones, until one shoots", function()
    local empty = place("gb-catapult", 3)
    local full = place("gb-catapult", 5)
    full.insert({ name = "iron-plate", count = 100 })
    module_of(full).capacitor.energy = module_of(full).capacitor.electric_buffer_size
    storage.catapults.cursor = module_of(empty).order_index
    catapult.on_pass_tick({ tick = game.tick })
    assert.are.equal(0, full.get_item_count("iron-plate"))
  end)

  test("keeps its visiting order after a middle catapult is removed", function()
    local first, middle, last = place("gb-catapult", 3), place("gb-catapult", 5), place("gb-catapult", 7)
    catapult.forget(middle.unit_number)
    middle.destroy()
    for index, unit_number in ipairs(storage.catapults.order) do
      assert.are.equal(index, storage.catapults.modules[unit_number].order_index)
    end
    assert.is_truthy(module_of(first) and module_of(last))
  end)

  test("sells everything in one shot and spends a shot's energy", function()
    local machine = place("gb-catapult", 3)
    machine.insert({ name = "iron-plate", count = 2000 })
    machine.insert({ name = "copper-plate", count = 1000 })
    local capacitor = module_of(machine).capacitor
    capacitor.energy = capacitor.electric_buffer_size
    local sold = catapult.shoot(module_of(machine), game.tick)
    assert.are.equal(3000, sold)
    assert.is_true(player_state().balance > 0)
    assert.are.near(capacitor.electric_buffer_size - catapult.SHOT_MJ * MJ, capacitor.energy, 1)
  end)

  test("does not shoot without energy, without a powered hub, or before its interval", function()
    local machine = place("gb-catapult", 3)
    machine.insert({ name = "iron-plate", count = 100 })
    local module = module_of(machine)
    module.capacitor.energy = 0
    assert.are.equal(0, catapult.shoot(module, game.tick))
    module.capacitor.energy = module.capacitor.electric_buffer_size
    hub.energy = 0
    assert.are.equal(0, catapult.shoot(module, game.tick))
    hub.energy = hub.electric_buffer_size
    module.next_shot = game.tick + 1
    assert.are.equal(0, catapult.shoot(module, game.tick))
    assert.are.equal(100, machine.get_item_count("iron-plate"))
  end)

  test("charges its capacitor from the electric network", function()
    local generator = place("electric-energy-interface", -6)
    generator.electric_interface_mode = defines.electric_interface_mode.primary_output
    generator.power_production = 50 * MJ / 60
    generator.electric_buffer_size = 50 * MJ / 60
    place("medium-electric-pole", -3)
    local machine = place("gb-catapult", 0, 213)
    local capacitor = module_of(machine).capacitor
    capacitor.energy = 0
    after_ticks(60, function()
      assert.is_true(capacitor.energy > 0)
    end)
  end)

  test("gets a capacitor back on a configuration change if it lost it", function()
    local machine = place("gb-catapult", 3)
    module_of(machine).capacitor.destroy()
    catapult.init()
    assert.is_true(module_of(machine).capacitor.valid)
  end)

  test("measures a shot of a full catapult holding 48 different items", function()
    local machine = place("gb-catapult", 3)
    local kinds = {}
    for _, name in ipairs(storage.tradeable_items) do
      if #kinds == 48 then break end
      local item = prototypes.item[name]
      if item.type == "item" and item.get_spoil_ticks() == 0 then
        kinds[#kinds + 1] = name
        machine.insert({ name = name, count = item.stack_size })
      end
    end
    local module = module_of(machine)
    module.capacitor.energy = module.capacitor.electric_buffer_size
    local profiler = helpers.create_profiler()
    catapult.shoot(module, game.tick)
    profiler.stop()
    log({ "", "[galactic-bazaar] catapult shot of 48 stacks: ", profiler })
    for _, name in ipairs(kinds) do player_state().markets["item/" .. name] = nil end
  end)

  test("keeps its catapults across a save and reload", function()
    storage.gb_test_catapult = place("gb-catapult", 3).unit_number
  end).after_reload_mods(function()
    local module = storage.catapults.modules[storage.gb_test_catapult]
    local alive = module.capacitor.valid
    for _, entity in ipairs(game.surfaces[1].find_entities_filtered({ area = { { -10, 205 }, { 10, 215 } } })) do
      if entity.name ~= catapult.CAPACITOR then entity.destroy() end
    end
    storage.gb_test_catapult = nil
    assert.is_true(alive)
  end)
end)
