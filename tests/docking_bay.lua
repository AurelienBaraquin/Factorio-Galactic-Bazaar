-- In-game tests of docking bays (scripts/docking_bay.lua, #65): the cargo shuttle tier while a bay
-- holds fuel, fuel burnt per shipment, and the capsule when fuel runs short.
local test_helpers = require("tests.helpers")
local docking_bay = require("scripts.docking_bay")
local freight = require("scripts.freight")
local bazaar_gui = require("scripts.bazaar_gui")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 170 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end

-- The first element under `element` carrying the gb_action tag `action`.
local function find(element, action)
  if element.tags.gb_action == action then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action)
    if found then return found end
  end
end
local GEAR = "iron-gear-wheel"

describe("docking bay", function()
  local saved_balance, hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    test_helpers.set_balance(player_state(), 1e6)
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
    if saved_balance then test_helpers.set_balance(player_state(), saved_balance) end
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

  test("gives the shuttle from a fuel buffer alone, and burns it first", function()
    local bay = place("gb-docking-bay", -3)
    storage.docking_bays.modules[bay.unit_number].fuel_mj = 150
    assert.are.equal("shuttle", freight.tier(hub.unit_number).name)
    freight.order(game.forces.player.index, hub.unit_number, GEAR, 10)
    assert.are.equal(50, storage.docking_bays.modules[bay.unit_number].fuel_mj)
  end)

  test("burns from several bays in turn", function()
    local first = place("gb-docking-bay", -3)
    local second = place("gb-docking-bay", -5)
    first.insert({ name = "rocket-fuel", count = 1 })
    second.insert({ name = "rocket-fuel", count = 1 })
    local per_shuttle = prototypes.item[GEAR].stack_size * freight.TIERS.shuttle.capacity_stacks
    assert.is_true(freight.order(game.forces.player.index, hub.unit_number, GEAR, 2 * per_shuttle))
    assert.are.equal("shuttle", freight.capsules(hub.unit_number)[1].tier)
    assert.are.equal(0, first.get_item_count("rocket-fuel") + second.get_item_count("rocket-fuel"))
  end)

  test("lands shuttle shipments even after the bay runs out of fuel", function()
    local bay = place("gb-docking-bay", -3)
    bay.insert({ name = "rocket-fuel", count = 1 })
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 10)
    assert.are.equal(0, docking_bay.fuel(hub.unit_number))
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)

  test("hands an order down to the capsule when the shuttle's queue is full", function()
    local bay = place("gb-docking-bay", -3)
    bay.insert({ name = "rocket-fuel", count = 30 })
    local full = {}
    for i = 1, freight.TIERS.shuttle.max_capsules do
      full[i] = { force_index = game.forces.player.index, kind = "item", name = GEAR, count = 1, unit_cost = 1,
        arrival = game.tick + 1e6, tier = "shuttle" }
    end
    storage.freight.hubs[hub.unit_number] = { launches = {}, capsules = full }
    assert.is_true(freight.order(game.forces.player.index, hub.unit_number, GEAR, 10))
    assert.are.equal(1, freight.queued(hub.unit_number, "capsule"))
  end)

  test("lets the market window buy what the fuel cannot cover, by capsule as shown", function()
    local player = game.get_player(1)
    local near = surface.create_entity({ name = "gb-hub", position = { player.position.x + 3, player.position.y },
      force = "player", raise_built = true })
    created[#created + 1] = near
    near.energy = near.electric_buffer_size
    place("gb-import-chest", player.position.x + 5, player.position.y)
    place("gb-docking-bay", player.position.x + 3, player.position.y + 3).insert({ name = "rocket-fuel", count = 1 })
    bazaar_gui.open(player, "market", near)
    local data = bazaar_gui.view(player.index, "market")
    data.selected = "item/" .. GEAR
    local per_shuttle = prototypes.item[GEAR].stack_size * freight.TIERS.shuttle.capacity_stacks
    data.elements.quantity.text = tostring(2 * per_shuttle)
    bazaar_gui.on_gui_input({ element = data.elements.quantity, player_index = player.index,
      name = defines.events.on_gui_text_changed })
    assert.are.equal("capsule", data.tier)
    bazaar_gui.on_gui_input({ element = find(player.gui.screen.gb_bazaar, "buy"), player_index = player.index })
    local queued = freight.queued(near.unit_number, "capsule")
    bazaar_gui.close(player.index)
    storage.freight.hubs[near.unit_number] = nil
    assert.are.equal(2 * freight.TIERS.shuttle.capacity_stacks / freight.TIERS.capsule.capacity_stacks, queued)
  end)

  test("measures 100 tier reads of a hub with 5 bays among 50", function()
    for i = 0, 49 do
      local bay = place("gb-docking-bay", -9 + (i % 10) * 2, 160 + math.floor(i / 10) * 2 + (i < 5 and 9 or 0))
      bay.insert({ name = "solid-fuel", count = 5 })
    end
    local profiler = helpers.create_profiler()
    for _ = 1, 100 do freight.tier(hub.unit_number) end
    profiler.stop()
    profiler.divide(100)
    log({ "", "[galactic-bazaar] tier read with docking bays: ", profiler })
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
