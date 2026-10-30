-- In-game tests of teleporters (scripts/teleporter.lua, #66): the teleporter tier while powered, and
-- shipments held without power.
local freight = require("scripts.freight")

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
  local saved_balance, hub, chest
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
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
    if saved_balance then player_state().balance = saved_balance end
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

  test("draws its power from the network", function()
    local machine = place("gb-teleporter", -3)
    machine.energy = machine.electric_buffer_size
    after_ticks(10, function()
      assert.is_true(machine.energy < machine.electric_buffer_size)
    end)
  end)

  test("keeps its teleporters across a save and reload", function()
    storage.gb_test_teleporter = { machine = place("gb-teleporter", -3).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_teleporter
    local module = storage.teleporters.modules[saved.machine]
    local attached = module.hub
    for _, entity in ipairs(game.surfaces[1].find_entities_filtered({ area = { { -10, 185 }, { 10, 195 } } })) do
      entity.destroy()
    end
    storage.gb_test_teleporter = nil
    assert.are.equal(saved.hub, attached)
  end)
end)
