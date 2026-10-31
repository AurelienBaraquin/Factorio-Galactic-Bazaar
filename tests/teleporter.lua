-- In-game tests of teleporters (scripts/teleporter.lua, #66): the teleporter tier while powered, and
-- shipments held without power.
local test_helpers = require("tests.helpers")
local freight = require("scripts.freight")
local teleporter = require("scripts.teleporter")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 190 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local GEAR = "iron-gear-wheel"

describe("teleporter", function()
  local hub, chest
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_teleporter_balance = player_state().balance
    test_helpers.set_balance(player_state(), 1e6)
    player_state().markets["item/" .. GEAR] = nil
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
    chest = place("gb-import-chest", 3)
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    if storage.gb_test_teleporter_balance then
      test_helpers.set_balance(player_state(), storage.gb_test_teleporter_balance)
      storage.gb_test_teleporter_balance = nil
    end
    player_state().markets["item/" .. GEAR] = nil
  end)

  test("is unlocked by the teleporter technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-teleporter"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-teleporter"])
  end)

  test("gives its hub the teleporter while powered, and nothing without power", function()
    local machine = place("gb-teleporter", -3)
    machine.energy = 0
    assert.are.equal("capsule", freight.tier(hub.unit_number).name)
    machine.energy = machine.electric_buffer_size
    assert.are.equal("teleporter", freight.tier(hub.unit_number).name)
  end)

  test("delivers in about a second, and holds its shipments while unpowered", function()
    local machine = place("gb-teleporter", -3)
    machine.energy = machine.electric_buffer_size
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    assert.are.equal(game.tick + freight.TIERS.teleporter.delay_ticks, arrival)
    machine.energy = 0
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(0, chest.get_item_count(GEAR))
    machine.energy = machine.electric_buffer_size
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(50, chest.get_item_count(GEAR))
  end)

  -- A teleporter fed by a generator of `megawatts` through a pole, starting with a full buffer.
  local function fed(megawatts)
    local generator = place("electric-energy-interface", -9)
    generator.electric_interface_mode = defines.electric_interface_mode.primary_output
    generator.power_production = megawatts * 1e6 / 60
    generator.electric_buffer_size = megawatts * 1e6 / 60
    place("medium-electric-pole", -6)
    local machine = place("gb-teleporter", -3)
    machine.energy = machine.electric_buffer_size
    return machine
  end

  test("stays powered on a network that covers its draw", function()
    local machine = fed(30)
    after_ticks(300, function()
      assert.is_true(machine.energy >= machine.electric_buffer_size / 2)
      assert.are.equal("teleporter", freight.tier(hub.unit_number).name)
    end)
  end)

  test("loses the tier on a network that cannot keep up", function()
    fed(10)
    after_ticks(300, function()
      assert.are.equal("capsule", freight.tier(hub.unit_number).name)
    end)
  end)

  test("delivers while any of its hub's teleporters is powered", function()
    local first = place("gb-teleporter", -3)
    local second = place("gb-teleporter", -6)
    first.energy, second.energy = 0, second.electric_buffer_size
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(50, chest.get_item_count(GEAR))
  end)

  test("lands held shipments once its hub has no teleporter left", function()
    local machine = place("gb-teleporter", -3)
    machine.energy = machine.electric_buffer_size
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    machine.energy = 0
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(0, chest.get_item_count(GEAR))
    local unit_number = machine.unit_number
    machine.destroy()
    teleporter.forget(unit_number) -- its destruction event arrives a tick later
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(50, chest.get_item_count(GEAR))
  end)

  test("keeps its teleporters across a save and reload", function()
    storage.gb_test_teleporter = { machine = place("gb-teleporter", -3).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_teleporter
    local module = storage.teleporters.modules[saved.machine]
    local attached = module.hub
    local indexed = storage.teleporters.by_hub[saved.hub] and storage.teleporters.by_hub[saved.hub][saved.machine]
    for _, entity in ipairs(game.surfaces[1].find_entities_filtered({ area = { { -10, 185 }, { 10, 195 } } })) do
      entity.destroy()
    end
    storage.gb_test_teleporter = nil
    assert.are.equal(saved.hub, attached)
    assert.is_true(indexed)
  end)
end)
