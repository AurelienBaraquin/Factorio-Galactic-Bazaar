-- In-game tests of the cargo module (scripts/cargo.lua): attachment to hubs in range, export
-- selling (spoilable stacks by freshness), import delivery, and the export batch budget.
local cargo = require("scripts.cargo")
local market = require("scripts.market")

local surface, created
local function place(name, x, y, force)
  local entity = surface.create_entity({
    name = name, position = { x, y }, force = force or "player", raise_built = true,
  })
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

  test("attaches to a hub built after it", function()
    local chest = place("gb-export-chest", 2, 0)
    assert.is_nil(module_of(chest).hub)
    local hub = place("gb-hub", 0, 0)
    assert.are.equal(hub.unit_number, module_of(chest).hub)
  end)

  test("ignores the hubs of another force", function()
    local enemy_hub = place("gb-hub", 0, 0, "enemy")
    local chest = place("gb-export-chest", 2, 0)
    assert.is_nil(module_of(chest).hub)
    assert.is_true(enemy_hub.valid)
  end)

  test("is sold through a powered hub when the nearest one has no power", function()
    local unpowered = place("gb-hub", 0, 0)
    local powered = place("gb-hub", 6, 0)
    local chest = place("gb-export-chest", 2, 0)
    assert.are.equal(unpowered.unit_number, module_of(chest).hub)
    unpowered.energy = 0
    powered.energy = powered.electric_buffer_size
    chest.insert({ name = "iron-gear-wheel", count = 10 })
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(0, chest.get_item_count("iron-gear-wheel"))
    assert.are.equal(powered.unit_number, module_of(chest).hub)
  end)

  test("stops using a hub of its old force after changing force", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    hub.energy = hub.electric_buffer_size
    chest.insert({ name = "iron-gear-wheel", count = 10 })
    local entity = chest
    entity.force = "neutral"
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(10, chest.get_item_count("iron-gear-wheel"))
    assert.is_nil(module_of(chest).hub)
  end)

  test("registers a cloned chest", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    local clone = chest.clone({ position = { 3, 0 } })
    created[#created + 1] = clone
    assert.are.equal(hub.unit_number, module_of(clone).hub)
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

  test("stays attached to an unpowered hub when an export runs before its hub's removal is known", function()
    local first = place("gb-hub", 0, 0)
    local second = place("gb-hub", 6, 0)
    local chest = place("gb-export-chest", 2, 0)
    second.energy = 0
    first.destroy()
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(second.unit_number, module_of(chest).hub)
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

  test("leaves damaged and used stacks unsold", function()
    local hub = place("gb-hub", 0, 0)
    local chest = place("gb-export-chest", 2, 0)
    hub.energy = hub.electric_buffer_size
    local inventory = chest.get_inventory(defines.inventory.chest)
    inventory.insert({ name = "firearm-magazine", count = 1 })
    inventory.insert({ name = "stone-furnace", count = 1, health = 0.5 })
    for slot = 1, #inventory do
      local stack = inventory[slot]
      if stack.valid_for_read and stack.name == "firearm-magazine" then stack.ammo = 1 end
    end
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(1, inventory.get_item_count("firearm-magazine"))
    assert.are.equal(1, inventory.get_item_count("stone-furnace"))
    assert.are.equal(0, player_state().balance)
  end)

  -- Spoilable items come with Space Age: run with `npm run test:game -- --mods space-age`. Each of
  -- their stacks carries a LuaItem, which alone must not make it unsellable.
  describe("spoilable stacks", function()
    local SPOILABLE = "nutrients"
    local inventory
    before_each(function()
      inventory = game.create_inventory(1)
      player_state().markets["item/" .. SPOILABLE] = nil
    end)
    after_each(function()
      if inventory and inventory.valid then inventory.destroy() end
      player_state().markets["item/" .. SPOILABLE] = nil
    end)

    test("sell at the market price times their freshness, moving the market by the units sold", function()
      if not script.active_mods["space-age"] then return end
      inventory.insert({ name = SPOILABLE, count = 10, spoil_percent = 0.75 })
      local freshness = 1 - inventory[1].spoil_percent
      local fresh_revenue = market.preview(game.forces.player.index, "item", SPOILABLE, "sell", 10)
      local sold, revenue = cargo.sell_stacks(inventory, game.forces.player.index, 0)
      assert.are.equal(10, sold)
      assert.is_true(freshness < 0.3)
      assert.are.near(fresh_revenue * freshness, revenue, 1e-9 * fresh_revenue)
      assert.are.near(revenue, player_state().balance, 1e-9 * fresh_revenue)
      assert.are.equal(10, player_state().markets["item/" .. SPOILABLE].displacement)
    end)

    test("stay unsold when their freshness takes a unit below the price floor", function()
      if not script.active_mods["space-age"] then return end
      inventory.insert({ name = SPOILABLE, count = 10, spoil_percent = 0.75 })
      local sold = cargo.sell_stacks(inventory, game.forces.player.index, cargo.DEFAULT_MIN_PRICE_RATIO)
      assert.are.equal(0, sold)
      assert.are.equal(10, inventory.get_item_count(SPOILABLE))
      assert.are.equal(0, player_state().balance)
    end)

    test("sell from an export chest while fresh enough for its price floor", function()
      if not script.active_mods["space-age"] then return end
      local hub = place("gb-hub", 0, 0)
      local chest = place("gb-export-chest", 2, 0)
      hub.energy = hub.electric_buffer_size
      chest.insert({ name = SPOILABLE, count = 10, spoil_percent = 0.1 })
      for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
      assert.are.equal(0, chest.get_item_count(SPOILABLE))
      assert.is_true(player_state().balance > 0)
    end)
  end)

  test("keeps visiting every export chest after one is removed", function()
    local chests = {}
    for i = 1, 3 do chests[i] = place("gb-export-chest", i, 5) end
    local exports = storage.cargo.exports
    local before = #exports
    cargo.forget(chests[1].unit_number)
    assert.are.equal(before - 1, #exports)
    for index, unit_number in ipairs(exports) do
      assert.are.equal(index, storage.cargo.modules[unit_number].export_index)
    end
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

  -- LuaProfiler is opaque to Lua, so the duration is logged for docs/terminal.md, not asserted.
  test("measures an export batch with chests in range holding 4 item kinds each", function()
    local hub = place("gb-hub", 0, 0)
    local kinds = { "iron-plate", "copper-plate", "iron-gear-wheel", "electronic-circuit" }
    local count = 0
    for x = -6, 6 do
      for y = -6, 6 do
        if count < 300 and (x ~= 0 or y ~= 0) and x * x + y * y <= 64 then
          local chest = place("gb-export-chest", x * 1.5 + 0.5, y * 1.5 + 0.5)
          if chest then
            for _, kind in ipairs(kinds) do chest.insert({ name = kind, count = 10 }) end
            count = count + 1
          end
        end
      end
    end
    hub.energy = hub.electric_buffer_size
    local batches = math.ceil(#storage.cargo.exports / cargo.EXPORT_BATCH)
    local profiler = helpers.create_profiler()
    for _ = 1, batches do cargo.on_export_tick() end
    profiler.stop()
    profiler.divide(batches)
    log({ "", "[galactic-bazaar] export batch of ", cargo.EXPORT_BATCH, " chests (", count,
      " chests in range, 4 kinds each): ", profiler })
    for _, kind in ipairs(kinds) do player_state().markets["item/" .. kind] = nil end
    assert.is_true(count >= 100)
    assert.is_true(player_state().balance > 0)
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
