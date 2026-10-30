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
    assert.are.equal(game.tick + freight.TIER.delay_ticks, arrival)
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
    local per_capsule = prototypes.item[GEAR].stack_size * freight.TIER.capacity_stacks
    local too_many = per_capsule * freight.TIER.max_capsules + 1
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

  test("sells the queued cargo back for the force that paid when the hub is removed", function()
    freight.order(game.forces.player.index, hub.unit_number, GEAR, 50)
    local after_order = player_state().balance
    freight.on_hub_removed(hub.unit_number)
    assert.is_true(player_state().balance > after_order)
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)
end)
