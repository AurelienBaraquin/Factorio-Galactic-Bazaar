-- In-game tests of electromagnetic catapults (scripts/catapult.lua, #67): bulk sales one shot at a
-- time, the energy each shot draws, and the hidden capacitor's lifecycle.
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
    player_state().balance = 0
    for _, name in ipairs({ "iron-plate", "copper-plate" }) do player_state().markets["item/" .. name] = nil end
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    if storage.gb_test_catapult_balance then
      player_state().balance = storage.gb_test_catapult_balance
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
    local unit_number = machine.unit_number
    machine.destroy()
    catapult.forget(unit_number)
    assert.is_false(capacitor.valid)
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

  test("measures a shot of a full catapult", function()
    local machine = place("gb-catapult", 3)
    local kinds = { "iron-plate", "copper-plate", "iron-gear-wheel", "electronic-circuit" }
    for i = 1, 48 do
      local name = kinds[(i - 1) % #kinds + 1]
      machine.insert({ name = name, count = prototypes.item[name].stack_size })
    end
    local module = module_of(machine)
    module.capacitor.energy = module.capacitor.electric_buffer_size
    local profiler = helpers.create_profiler()
    catapult.shoot(module, game.tick)
    profiler.stop()
    log({ "", "[galactic-bazaar] catapult shot of 48 stacks: ", profiler })
    for _, name in ipairs(kinds) do player_state().markets["item/" .. name] = nil end
  end)
end)
