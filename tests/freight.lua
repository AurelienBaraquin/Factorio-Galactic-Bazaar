-- In-game tests of purchase deliveries by orbital capsule (scripts/freight.lua): payment, landing
-- after the delay, waiting for room, bounded queue, and settlement when the hub is removed.
local freight = require("scripts.freight")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({ name = name, position = { x, y }, force = "player", raise_built = true })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local GEAR = "iron-gear-wheel"

-- Tier providers for tests: storage.gb_test_tiers[hub unit number] = tier name. They stay registered
-- for the test files run after this one, and answer only while a test sets that table.
for name in pairs(freight.TIERS) do
  if name ~= "capsule" then
    local function available(hub_unit_number)
      return storage.gb_test_tiers ~= nil and storage.gb_test_tiers[hub_unit_number] == name
    end
    freight.register_tier_provider({ tier = name, available = available })
  end
end

describe("orbital capsule", function()
  local saved_balance, hub, chest
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
    player_state().markets["item/" .. GEAR] = nil
    hub = place("gb-hub", 0, 0)
    chest = place("gb-import-chest", 3, 0)
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: that test cleans up itself.
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    if saved_balance then player_state().balance = saved_balance end
    player_state().markets["item/" .. GEAR] = nil
  end)

  test("charges the market cost plus the freight fee, and journals both", function()
    local cost, fee = freight.preview(game.forces.player.index, GEAR, 50)
    local ok, paid, charged = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    assert.is_true(ok)
    assert.is_true(math.abs(paid - cost) < 1e-9 and math.abs(charged - fee) < 1e-9)
    assert.is_true(math.abs((1e6 - player_state().balance) - (cost + fee)) < 1e-6)
    local journal = player_state().journal
    assert.are.equal("freight", journal[#journal].kind)
    assert.are.equal("buy", journal[#journal - 1].kind)
  end)

  test("lands in the import chests after the delay, not before", function()
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    assert.are.equal(game.tick + freight.TIERS.capsule.delay_ticks, arrival)
    freight.on_unload_tick({ tick = arrival - 1 })
    assert.are.equal(0, chest.get_item_count(GEAR))
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(50, chest.get_item_count(GEAR))
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)

  test("waits, landed, while the chests are full, and loses nothing", function()
    local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    chest.insert({ name = "stone", count = 48 * 50 })
    freight.on_unload_tick({ tick = arrival })
    assert.are.equal(1, freight.queued(hub.unit_number))
    chest.clear_items_inside()
    freight.on_unload_tick({ tick = arrival + freight.UNLOAD_INTERVAL })
    assert.are.equal(50, chest.get_item_count(GEAR))
  end)

  test("refuses orders beyond the queue bound, and without an import chest, changing nothing", function()
    local per_capsule = prototypes.item[GEAR].stack_size * freight.TIERS.capsule.capacity_stacks
    local too_many = per_capsule * freight.TIERS.capsule.max_capsules + 1
    local ok, reason = freight.order(game.forces.player.index, hub.unit_number, GEAR, too_many)
    assert.is_false(ok)
    assert.are.equal("queue-full", reason)
    chest.destroy()
    ok, reason = freight.order(game.forces.player.index, hub.unit_number, GEAR, 1)
    assert.is_false(ok)
    assert.are.equal("no-import-chest", reason)
    assert.are.equal(1e6, player_state().balance)
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)

  test("unloads what fits and keeps the rest landed, holding back the next capsule", function()
    local per_capsule = prototypes.item[GEAR].stack_size * freight.TIERS.capsule.capacity_stacks
    freight.order(game.forces.player.index, hub.unit_number, GEAR, per_capsule + 10)
    local capsules = freight.capsules(hub.unit_number)
    chest.insert({ name = "stone", count = 47 * 50 })
    freight.on_unload_tick({ tick = capsules[2].arrival })
    local room = prototypes.item[GEAR].stack_size
    assert.are.equal(room, chest.get_item_count(GEAR))
    assert.are.equal(2, freight.queued(hub.unit_number))
    assert.are.equal(per_capsule - room, capsules[1].count)
    assert.are.equal(10, capsules[2].count)
  end)

  test("sells the queued cargo back for the force that paid when the hub is destroyed", function()
    freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    local after_order = player_state().balance
    local unit_number = hub.unit_number
    hub.destroy()
    after_ticks(1, function()
      assert.is_true(player_state().balance > after_order)
      assert.are.equal(0, freight.queued(unit_number))
    end)
  end)

  test("refunds the price paid for cargo the market will not take back", function()
    local unit_number = 1e9
    storage.freight.hubs[unit_number] = { next_launch = 0, capsules = {
      { force_index = game.forces.player.index, name = "gb-no-such-item", count = 4, unit_cost = 2.5, arrival = 0 },
    } }
    freight.on_hub_removed(unit_number)
    assert.are.equal(1e6 + 10, player_state().balance)
    assert.are.equal("freight-refund", player_state().journal[#player_state().journal].kind)
  end)

  test("refunds capsules of items that no longer exist, and settles the queues of removed hubs", function()
    storage.freight.hubs[hub.unit_number] = { next_launch = 0, capsules = {
      { force_index = game.forces.player.index, name = "gb-no-such-item", count = 4, unit_cost = 2.5, arrival = 0 },
    } }
    freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    local unit_number = hub.unit_number
    local after_order = player_state().balance
    storage.hubs[unit_number] = nil
    freight.init()
    assert.is_nil(storage.freight.hubs[unit_number])
    assert.is_true(player_state().balance > after_order + 10)
  end)

  test("moves the capsules of a merged force to the destination force", function()
    local source = game.create_force("gb-test-freight")
    local source_index = source.index
    storage.forces[source_index].balance = 1e6
    freight.order(source_index, hub.unit_number, GEAR, 50)
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.are.equal(game.forces.player.index, freight.capsules(hub.unit_number)[1].force_index)
    end)
  end)

  test("keeps its queue across a save and reload", function()
    freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    storage.gb_test_freight = { hub = hub.unit_number, chest = chest.unit_number }
  end).after_reload_mods(function()
    local unit_number = storage.gb_test_freight.hub
    local capsules = freight.capsules(unit_number)
    local count, first = #capsules, capsules[1] and capsules[1].count
    local launch = storage.freight.hubs[unit_number].launches.capsule
    -- Clean up before asserting, so that a failure does not leave entities behind for later tests.
    storage.freight.hubs[unit_number] = nil
    storage.hubs[unit_number].entity.destroy()
    storage.cargo.modules[storage.gb_test_freight.chest].entity.destroy()
    storage.gb_test_freight = nil
    assert.are.equal(1, count)
    assert.are.equal(50, first)
    assert.is_true(launch > 0)
  end)

  describe("tiers", function()
    after_each(function() storage.gb_test_tiers = nil end)

    test("ship by the orbital capsule when a hub has no better tier", function()
      assert.are.equal("capsule", freight.tier(hub.unit_number).name)
      freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
      assert.are.equal("capsule", freight.capsules(hub.unit_number)[1].tier)
    end)

    test("ship by the best tier a hub's buildings provide, with its delay, capacity and fee", function()
      storage.gb_test_tiers = { [hub.unit_number] = "shuttle" }
      local shuttle = freight.TIERS.shuttle
      local cost, fee = freight.preview(game.forces.player.index, GEAR, 50, "item", hub.unit_number)
      assert.is_true(math.abs(fee - cost * shuttle.fee_rate) < 1e-9 * cost)
      local units = prototypes.item[GEAR].stack_size * shuttle.capacity_stacks
      local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, GEAR, units)
      assert.are.equal(1, freight.queued(hub.unit_number))
      assert.are.equal("shuttle", freight.capsules(hub.unit_number)[1].tier)
      assert.are.equal(game.tick + shuttle.delay_ticks, arrival)
    end)

    test("land a fast tier at its own time, never behind a slower one", function()
      storage.gb_test_tiers = { [hub.unit_number] = "shuttle" }
      local per_shuttle = prototypes.item[GEAR].stack_size * freight.TIERS.shuttle.capacity_stacks
      freight.order(game.forces.player.index, hub.unit_number, GEAR, 2 * per_shuttle)
      storage.gb_test_tiers = { [hub.unit_number] = "teleporter" }
      local _, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, "iron-plate", 10)
      assert.are.equal(game.tick + freight.TIERS.teleporter.delay_ticks, arrival)
      freight.on_unload_tick({ tick = arrival })
      assert.are.equal(10, chest.get_item_count("iron-plate"))
      assert.are.equal(2, freight.queued(hub.unit_number))
      player_state().markets["item/iron-plate"] = nil
    end)

    test("bound each tier's queue on its own, so a better tier never locks a hub out", function()
      local per_capsule = prototypes.item[GEAR].stack_size * freight.TIERS.capsule.capacity_stacks
      freight.order(game.forces.player.index, hub.unit_number, GEAR, per_capsule * freight.TIERS.capsule.max_capsules)
      storage.gb_test_tiers = { [hub.unit_number] = "teleporter" }
      assert.is_true(freight.order(game.forces.player.index, hub.unit_number, GEAR, 10))
      assert.are.equal(1, freight.queued(hub.unit_number, "teleporter"))
    end)

    test("refuse an order whose tier changed since the player saw it", function()
      local ok, reason = freight.order(game.forces.player.index, hub.unit_number, GEAR, 10, nil, nil, "item", "shuttle")
      assert.is_false(ok)
      assert.are.equal("tier-changed", reason)
      assert.are.equal(0, freight.queued(hub.unit_number))
    end)
  end)
end)
