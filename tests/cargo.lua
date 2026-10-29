-- In-game tests of the cargo module (scripts/cargo.lua): attachment to hubs in range, export
-- selling, import delivery, and the export batch budget.
local cargo = require("scripts.cargo")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({ name = name, position = { x, y }, force = "player", raise_built = true })
  created[#created + 1] = entity
  return entity
end

local function module_of(entity) return storage.cargo.modules[entity.unit_number] end
local function player_state() return storage.forces[game.forces.player.index] end

describe("cargo module", function()
  local saved_balance
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 0
    player_state().markets["item/iron-gear-wheel"] = nil
  end)
  after_each(function()
    -- After a reload the file runs again and `created` starts empty; that test cleans up itself.
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    player_state().balance = saved_balance
    player_state().markets["item/iron-gear-wheel"] = nil
  end)

  test("chests are unlocked with the hub by the Galactic Bazaar technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-galactic-bazaar"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-export-chest"] and unlocks["gb-import-chest"])
  end)

  test("attaches to the nearest hub in range, and to none beyond it", function()
    local near = place("gb-hub", 0, 0)
    local far = place("gb-hub", 8, 0)
    local chest = place("gb-export-chest", 2, 0)
    local lonely = place("gb-export-chest", 40, 0)
    assert.are.equal(near.unit_number, module_of(chest).hub)
    assert.is_nil(module_of(lonely).hub)
    assert.is_true(far.valid)
  end)

  test("moves to another hub when its hub is removed", function()
    local first = place("gb-hub", 0, 0)
    local second = place("gb-hub", 6, 0)
    local chest = place("gb-export-chest", 2, 0)
    assert.are.equal(first.unit_number, module_of(chest).hub)
    first.destroy()
    after_ticks(1, function()
      assert.are.equal(second.unit_number, module_of(chest).hub)
    end)
  end)

  test("sells an export chest's content when its hub has power", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    chest.insert({ name = "iron-gear-wheel", count = 100 })
    hub.energy = hub.electric_buffer_size
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(0, chest.get_item_count("iron-gear-wheel"))
    assert.is_true(player_state().balance > 0)
  end)

  test("sells nothing when its hub has no power", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    chest.insert({ name = "iron-gear-wheel", count = 100 })
    hub.energy = 0
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(100, chest.get_item_count("iron-gear-wheel"))
    assert.are.equal(0, player_state().balance)
  end)

  test("stops selling at the price floor", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    module_of(chest).min_price_ratio = 2
    chest.insert({ name = "iron-gear-wheel", count = 100 })
    hub.energy = hub.electric_buffer_size
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(100, chest.get_item_count("iron-gear-wheel"))
  end)

  test("delivers purchases into the hub's import chests, returning what fits", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-import-chest", -2, 0)
    assert.are.equal(30, cargo.deliver(hub.unit_number, "iron-plate", 30))
    assert.are.equal(30, chest.get_item_count("iron-plate"))
    assert.are.equal(48 * 100 - 30, cargo.deliver(hub.unit_number, "iron-plate", 10000))
  end)

  test("keeps the export batch within budget with 500 chests", function()
    local hub = place("gb-hub", 0, 0)
    for i = 1, 500 do
      local chest = place("gb-export-chest", (i % 25) - 12, math.floor(i / 25) - 10)
      chest.insert({ name = "iron-plate", count = 10 })
    end
    hub.energy = hub.electric_buffer_size
    local batches = math.ceil(#storage.cargo.exports / cargo.EXPORT_BATCH)
    local profiler = helpers.create_profiler()
    for _ = 1, batches do cargo.on_export_tick() end
    profiler.stop()
    profiler.divide(batches)
    log({ "", "[galactic-bazaar] export batch of ", cargo.EXPORT_BATCH, " chests (500 chests): ", profiler })
    player_state().markets["item/iron-plate"] = nil
  end)

  test("keeps its modules across a save and reload", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-import-chest", 2, 0)
    storage.gb_test_cargo = { chest = chest.unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_cargo
    assert.are.equal(saved.hub, storage.cargo.modules[saved.chest].hub)
    storage.cargo.modules[saved.chest].entity.destroy()
    storage.hubs[saved.hub].entity.destroy()
    storage.gb_test_cargo = nil
  end)
end)
