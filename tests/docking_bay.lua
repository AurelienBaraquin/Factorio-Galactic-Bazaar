-- In-game tests of docking bays (scripts/docking_bay.lua, #65): the cargo shuttle tier while a bay
-- holds fuel, fuel burnt per shipment, and the capsule when fuel runs short.
local docking_bay = require("scripts.docking_bay")
local freight = require("scripts.freight")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 170 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local GEAR = "iron-gear-wheel"

describe("docking bay", function()
  local saved_balance, hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
    player_state().markets["item/" .. GEAR] = nil
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 3)
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

  test("is unlocked by the cargo shuttle technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-cargo-shuttle"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-docking-bay"])
  end)

  test("gives its hub the shuttle while it holds fuel for a shipment", function()
    local bay = place("gb-docking-bay", -3)
    assert.are.equal("capsule", freight.tier(hub.unit_number).name)
    bay.insert({ name = "rocket-fuel", count = 1 })
    assert.are.equal("shuttle", freight.tier(hub.unit_number).name)
  end)

  test("burns fuel per shipment when an order is paid, keeping the surplus", function()
    local bay = place("gb-docking-bay", -3)
    bay.insert({ name = "solid-fuel", count = 20 })
    local per_shuttle = prototypes.item[GEAR].stack_size * freight.TIERS.shuttle.capacity_stacks
    assert.is_true(freight.order(game.forces.player.index, hub.unit_number, GEAR, 2 * per_shuttle))
    assert.are.equal("shuttle", freight.capsules(hub.unit_number)[1].tier)
    local fuel_mj = prototypes.item["solid-fuel"].fuel_value / 1e6
    local burnt = 2 * docking_bay.FUEL_MJ_PER_SHIPMENT
    assert.are.equal(20 - math.ceil(burnt / fuel_mj), bay.get_item_count("solid-fuel"))
    assert.are.near(20 * fuel_mj - burnt, docking_bay.fuel(hub.unit_number), 1e-6)
  end)

  test("sends an order its fuel cannot cover by orbital capsule, burning nothing", function()
    local bay = place("gb-docking-bay", -3)
    bay.insert({ name = "rocket-fuel", count = 1 })
    local per_shuttle = prototypes.item[GEAR].stack_size * freight.TIERS.shuttle.capacity_stacks
    assert.is_true(freight.order(game.forces.player.index, hub.unit_number, GEAR, 2 * per_shuttle))
    assert.are.equal("capsule", freight.capsules(hub.unit_number)[1].tier)
    assert.are.equal(1, bay.get_item_count("rocket-fuel"))
  end)

  test("ignores fuel that is not chemical and bays of another force", function()
    local bay = place("gb-docking-bay", -3)
    bay.insert({ name = "uranium-fuel-cell", count = 10 })
    local foreign = surface.create_entity({ name = "gb-docking-bay", position = { -6, 170 }, force = "enemy",
      raise_built = true })
    created[#created + 1] = foreign
    foreign.insert({ name = "rocket-fuel", count = 10 })
    assert.are.equal("capsule", freight.tier(hub.unit_number).name)
  end)

  test("keeps its bays and fuel buffer across a save and reload", function()
    local bay = place("gb-docking-bay", -3)
    storage.docking_bays.modules[bay.unit_number].fuel_mj = 42
    storage.gb_test_bay = { bay = bay.unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_bay
    local module = storage.docking_bays.modules[saved.bay]
    local fuel, attached = module.fuel_mj, module.hub
    for _, entity in ipairs(game.surfaces[1].find_entities_filtered({ area = { { -10, 165 }, { 10, 175 } } })) do
      entity.destroy()
    end
    storage.gb_test_bay = nil
    assert.are.equal(42, fuel)
    assert.are.equal(saved.hub, attached)
  end)
end)
