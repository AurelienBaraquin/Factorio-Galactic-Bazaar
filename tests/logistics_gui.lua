-- In-game tests of the Logistics tab of the Galactic Bazaar window (scripts/logistics_gui.lua, #109):
-- the force's hubs, a hub's purchases, incoming contract ingredients and planet shipments with their
-- state, landing time, origin and cost, a long queue paged, the modules attached with their status
-- and the camera, a save from before the tab, the refresh cost and persistence.
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local entity_status = require("scripts.entity_status")
local freight = require("scripts.freight")
local logistics = require("scripts.core.logistics")
local planets = require("scripts.planets")

local Y = 640
local GEAR = "iron-gear-wheel"

local player

local function force_state() return storage.forces[player.force_index] end
local function view() return bazaar_gui.view(player.index, "logistics") end
local function elements() return view().elements end

local function place(name, x, y, force)
  local entity = game.surfaces[1].create_entity({ name = name, position = { x, Y + (y or 0) },
    force = force or "player", raise_built = true })
  -- In storage, so that a test's buildings are removed after a reload too.
  table.insert(storage.gb_test_logistics_created, entity)
  return entity
end

-- Queues `count` capsules of gears at a hub, as purchases would, without going through the market.
local function queue_capsules(hub, count)
  local queue = { launches = {}, capsules = {} }
  for i = 1, count do
    queue.capsules[i] = { force_index = player.force_index, kind = "item", name = GEAR, count = 1000,
      unit_cost = 1.5, arrival = game.tick + 1800 + 600 * (i - 1), tier = "capsule" }
  end
  storage.freight.hubs[hub.unit_number] = queue
  return queue.capsules
end

-- A LocalisedString as plain text, numbers included (the game may give numbers back as strings).
local function plain(value)
  if type(value) ~= "table" then return tostring(value) end
  local copy = {}
  for i, entry in ipairs(value) do copy[i] = plain(entry) end
  return copy
end

local function same(expected, actual)
  assert.are.same(plain(expected), plain(actual))
end

-- A powered hub at x with an import chest of its force.
local function trading_hub(x)
  local hub = place("gb-hub", x)
  hub.energy = hub.electric_buffer_size
  place("gb-import-chest", x + 3)
  return hub
end

-- Opens the window on the Logistics tab showing `hub`.
local function show(hub)
  bazaar_gui.open(player, "logistics")
  view().hub = hub.unit_number
  bazaar_gui.refresh(player)
end

local function click(element)
  bazaar_gui.on_gui_input({ element = element, player_index = player.index, name = defines.events.on_gui_click })
end

-- The visible rows of a list of the tab.
local function visible(rows)
  local shown = {}
  for _, row in ipairs(rows) do
    local _, cell = next(row)
    if cell.visible then shown[#shown + 1] = row end
  end
  return shown
end

-- The row of a hub in the hubs list, paging from the first page with the tab's own buttons (other
-- test files may leave hubs before it); fails when the hub is not listed.
local function hub_row(unit_number)
  view().hubs_page = 1
  bazaar_gui.refresh(player)
  while true do
    for _, row in ipairs(visible(elements().hub_rows)) do
      if row.select.tags.hub == unit_number then return row end
    end
    local next_page = elements().pagers.hubs.next
    assert.is_true(next_page.enabled, "hub " .. unit_number .. " not listed")
    click(next_page)
  end
end

-- Every hub of the player's force.
local function hub_count()
  local count = 0
  for _, entry in pairs(storage.hubs) do
    if entry.entity.valid and entry.entity.force == player.force then count = count + 1 end
  end
  return count
end

describe("Logistics tab", function()
  before_each(function()
    player = game.get_player(1)
    storage.gb_test_logistics_created = {}
    storage.gb_test_logistics = { balance = force_state().balance, reputation = force_state().reputation,
      contracts = force_state().contracts.open }
    test_helpers.set_balance(force_state(), 1e7)
    force_state().reputation = 0
    force_state().contracts.open = {}
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    bazaar_gui.close(player.index)
    for _, entity in ipairs(storage.gb_test_logistics_created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    storage.gb_test_logistics_created = nil
    local saved = storage.gb_test_logistics
    if saved then
      test_helpers.set_balance(force_state(), saved.balance)
      force_state().reputation = saved.reputation
      force_state().contracts.open = saved.contracts
      storage.gb_test_logistics = nil
    end
  end)

  test("lists the force's hubs with power, status and queue, and selects one by a click", function()
    local first = trading_hub(0)
    local second = place("gb-hub", 20)
    place("gb-hub", 40, 0, "enemy")
    assert.is_true(freight.order(player.force_index, first.unit_number, GEAR, 10))
    show(first)
    same({ "gb-logistics.hubs", hub_count() }, elements().hub_count.caption)
    local row = hub_row(first.unit_number)
    assert.is_true(row.select.toggled)
    assert.are.same({ "gb-logistics.powered" }, row.power.caption)
    same({ "", { "gb-logistics.queue-entry", { "gb-gui.tier-capsule" }, 1, 20 } }, row.queue.caption)
    local other = hub_row(second.unit_number)
    assert.are.same({ "gb-logistics.unpowered" }, other.power.caption)
    assert.are.same({ "gb-logistics.queue-empty" }, other.queue.caption)
    assert.is_false(other.select.toggled)
    click(other.select)
    assert.are.equal(second.unit_number, view().hub)
    assert.is_true(hub_row(second.unit_number).select.toggled)
    assert.is_true(elements().no_shipment.visible)
    assert.are.equal(second, elements().camera.entity)
  end)

  test("never selects another force's hub or points the camera at another force's building", function()
    local hub = trading_hub(0)
    local enemy_hub = place("gb-hub", 30, 0, "enemy")
    local enemy_chest = place("gb-export-chest", 33, 0, "enemy")
    place("gb-export-chest", 0, 3)
    show(hub)
    -- Inputs are player input: tags of the tab's own buttons, pointed at the enemy's buildings.
    local select = hub_row(hub.unit_number).select
    select.tags = { gb_action = "logistics-select-hub", hub = enemy_hub.unit_number }
    click(select)
    assert.are.same({ hub.unit_number, hub }, { view().hub, elements().camera.entity })
    local locate = visible(elements().module_rows)[1].locate
    locate.tags = { gb_action = "logistics-locate", unit = enemy_chest.unit_number }
    click(locate)
    assert.are.same({ nil, hub }, { view().focus, elements().camera.entity })
  end)

  test("shows purchases, incoming contract ingredients and planet shipments with origin and cost", function()
    local hub = trading_hub(0)
    assert.is_true(freight.order(player.force_index, hub.unit_number, GEAR, 10))
    force_state().contracts.open[901] = { id = 901, kind = "incoming", state = "active" }
    force_state().contracts.open[902] = { id = 902, kind = "concession", counterparty = "carbo", state = "active" }
    assert.is_true(freight.ship(player.force_index, hub.unit_number, { { kind = "item", name = "copper-plate",
      count = 50 } }, 901))
    assert.is_true(planets.ship(player.force_index, hub.unit_number, "carbo", { { kind = "item", name = "coal",
      count = 400 } }, 902, 3))
    show(hub)
    local rows = visible(elements().shipment_rows)
    assert.are.equal(3, #rows)
    same({ "gb-logistics.shipments", 3 }, elements().shipment_count.caption)
    -- Purchase first (it lands first), then the ingredients, then the coal after its transit.
    local purchase, ingredients, coal = rows[1], rows[2], rows[3]
    assert.are.equal("[item=" .. GEAR .. "] 10", purchase.goods.caption)
    assert.are.same({ "gb-gui.tier-capsule" }, purchase.tier.caption)
    assert.are.equal("gb-logistics.tier-tooltip", purchase.tier.tooltip[1])
    assert.are.equal("gb-logistics.state-in-flight", purchase.state.caption[1])
    assert.are.equal("gb-logistics.lands", purchase.lands.caption[1])
    assert.are.same({ "gb-logistics.origin-purchase" }, purchase.origin.caption)
    assert.are.equal(catalog.format_credits(freight.capsules(hub.unit_number)[1].unit_cost), purchase.cost.caption)
    assert.are.same({ "gb-logistics.cost-tooltip" }, purchase.cost.tooltip)
    -- The ingredients wait for the capsule launched before them.
    assert.are.same({ "gb-logistics.state-queued" }, { ingredients.state.caption[1] })
    same({ "gb-logistics.origin-incoming", 901 }, ingredients.origin.caption)
    assert.are.same({ "gb-logistics.free" }, ingredients.cost.caption)
    assert.are.equal("gb-logistics.state-in-transit", coal.state.caption[1])
    assert.are.equal("gb-logistics.origin-concession", coal.origin.caption[1])
    same({ "?", { "gb-planets.name-carbo" }, "carbo" }, coal.origin.caption[2])
    local capsule = freight.capsules(hub.unit_number)[3]
    assert.are.same({ "carbo", true }, { capsule.planet, capsule.loss > 0 })
    assert.are.equal("gb-logistics.origin-planet-loss-tooltip", coal.origin.tooltip[1])
    assert.are.equal(string.format("%.4g", capsule.loss * 100), plain(coal.origin.tooltip[3]))
    assert.are.same({ "gb-logistics.cost-planet-tooltip" }, coal.cost.tooltip)
    assert.is_true(capsule.count < 400)
    assert.are.equal("[item=coal] " .. capsule.count, coal.goods.caption)
  end)

  test("explains landed shipments waiting for room or held, and pages a long queue", function()
    local hub = trading_hub(0)
    -- 12 capsules: two pages of shipments.
    local capsules = queue_capsules(hub, 12)
    capsules[1].arrival = game.tick - 2 * freight.UNLOAD_INTERVAL
    capsules[2].arrival, capsules[2].tier = game.tick - 2 * freight.UNLOAD_INTERVAL, "teleporter"
    place("gb-teleporter", 6)
    show(hub)
    local rows = visible(elements().shipment_rows)
    assert.are.equal(logistics.SHIPMENT_ROWS, #rows)
    same({ "gb-gui.page", 1, 2 }, elements().pagers.shipments.label.caption)
    local states = { rows[1].state.caption[1], rows[2].state.caption[1] }
    table.sort(states)
    assert.are.same({ "gb-logistics.state-held", "gb-logistics.state-no-room-item" }, states)
    assert.are.equal("gb-logistics.landed", rows[1].lands.caption[1])
    click(elements().pagers.shipments.next)
    assert.are.equal(2, view().shipments_page)
    assert.are.equal(12 - logistics.SHIPMENT_ROWS, #visible(elements().shipment_rows))
    assert.is_false(elements().pagers.shipments.next.enabled)
    click(elements().pagers.shipments.next)
    assert.are.equal(2, view().shipments_page)
  end)

  test("lists the modules attached to the hub with their status, and shows one on the camera", function()
    local hub = trading_hub(0)
    local export = place("gb-export-chest", 0, 3)
    place("gb-power-export", 3, 3)
    place("gb-export-chest", 0, -3, "enemy")
    show(hub)
    local rows = visible(elements().module_rows)
    same({ "gb-logistics.modules", 3 }, elements().module_count.caption)
    assert.are.equal(3, #rows)
    local by_sprite = {}
    for _, row in ipairs(rows) do by_sprite[row.locate.sprite] = row end
    local chest = by_sprite["entity/gb-export-chest"]
    local descriptor = entity_status.shown(export.unit_number)
    same({ "", "[img=utility/status_working] ", descriptor.label }, chest.status.caption)
    assert.is_true(by_sprite["entity/gb-import-chest"] ~= nil and by_sprite["entity/gb-power-export"] ~= nil)
    assert.is_true(elements().module_groups.caption:find("[img=entity/gb-export-chest] 1", 1, true) ~= nil)
    assert.are.equal(hub, elements().camera.entity)
    click(chest.locate)
    assert.are.same({ export.unit_number, export }, { view().focus, elements().camera.entity })
    by_sprite = {}
    for _, row in ipairs(visible(elements().module_rows)) do by_sprite[row.locate.sprite] = row end
    click(by_sprite["entity/gb-export-chest"].locate)
    assert.are.same({ nil, hub }, { view().focus, elements().camera.entity })
    -- Unpowered, the chest that sells through the hub is stopped, and its row says so.
    hub.energy = 0
    entity_status.on_built(export)
    bazaar_gui.refresh(player)
    for _, row in ipairs(visible(elements().module_rows)) do by_sprite[row.locate.sprite] = row end
    assert.are.equal("[img=utility/status_not_working] ", by_sprite["entity/gb-export-chest"].status.caption[2])
  end)

  test("reads a save from before the tab: older capsules and no building status yet", function()
    local hub = trading_hub(0)
    storage.freight.hubs[hub.unit_number] = { launches = {}, capsules = {
      { force_index = player.force_index, name = "stone", count = 30, unit_cost = 1, arrival = game.tick + 600 },
      { force_index = player.force_index, kind = "item", name = "coal", count = 20, unit_cost = 2,
        arrival = game.tick + 900, tier = "capsule", contract = 903 },
    } }
    force_state().contracts.open[903] = { id = 903, kind = "outsourcing", counterparty = "carbo", state = "active" }
    storage.entity_status, storage.bazaar_gui = nil, nil
    show(hub)
    local rows = visible(elements().shipment_rows)
    assert.are.same({ "gb-gui.tier-capsule" }, rows[1].tier.caption)
    assert.are.same({ "gb-logistics.origin-purchase" }, rows[1].origin.caption)
    assert.are.equal("gb-logistics.origin-outsourcing", rows[2].origin.caption[1])
    same({ "gb-logistics.origin-planet-tooltip", 903 }, rows[2].origin.tooltip)
    local modules = visible(elements().module_rows)
    assert.are.same({ "", "[img=utility/status_inactive] ", { "gb-logistics.status-pending" } },
      modules[1].status.caption)
  end)

  test("measures the refresh with many hubs, a full queue and 1000 modules", function()
    local names = { "gb-export-chest", "gb-import-chest", "gb-fluid-export", "gb-power-export",
      "gb-sell-price-combinator", "gb-order-combinator", "gb-docking-bay", "gb-catapult", "gb-contract-chest",
      "gb-rental-assembler" }
    local hubs = {}
    for h = 0, 19 do
      local x, y = -40 + (h % 5) * 20, 30 + math.floor(h / 5) * 20
      hubs[h + 1] = place("gb-hub", x, y)
      hubs[h + 1].energy = 1e5
      for i = 0, 48 do
        place(names[i % #names + 1], x - 6 + 2 * (i % 7), y - 6 + 2 * math.floor(i / 7))
      end
    end
    local hub = hubs[1]
    queue_capsules(hub, freight.TIERS.capsule.max_capsules)
    show(hub)
    assert.are.equal(logistics.MODULE_ROWS, #visible(elements().module_rows))
    -- Steady refreshes, then refreshes that each list the hub's modules again (every
    -- MODULE_RESCAN_TICKS, or when another hub is selected), after a full garbage collection and a
    -- warm-up of both, so that the garbage left by placing 1000 buildings and by the test files run
    -- before is not charged to them (without the collection, the full suite charged up to 6 ms of it
    -- to the first refreshes measured).
    local runs = 10
    collectgarbage("collect")
    for _ = 1, 2 * runs do
      view().modules = nil
      bazaar_gui.refresh(player)
      bazaar_gui.refresh(player)
    end
    local steady = helpers.create_profiler()
    for _ = 1, runs do bazaar_gui.refresh(player) end
    steady.stop()
    steady.divide(runs)
    local rescan = helpers.create_profiler(true)
    for _ = 1, runs do
      view().modules = nil
      rescan.restart()
      bazaar_gui.refresh(player)
      rescan.stop()
    end
    rescan.divide(runs)
    log({ "", "[galactic-bazaar] logistics tab refresh (", hub_count(), " hubs, ",
      freight.TIERS.capsule.max_capsules, " shipments, about 1000 modules, average of ", runs, "): ", steady,
      "; listing the modules again: ", rescan })
  end)

  test("keeps the hub selected and the tab working across a save and reload", function()
    local hub = trading_hub(0)
    assert.is_true(freight.order(player.force_index, hub.unit_number, GEAR, 10))
    show(hub)
  end).after_reload_mods(function()
    local reloaded = game.get_player(1)
    local hub = storage.gb_test_logistics_created[1].unit_number
    local data = bazaar_gui.window(reloaded.index)
    assert.are.same({ "logistics", hub }, { data.tab, data.views.logistics.hub })
    bazaar_gui.on_refresh_tick({ tick = (reloaded.index % bazaar_gui.SLOTS) * bazaar_gui.SLOT_TICKS })
    local rows = bazaar_gui.view(reloaded.index, "logistics").elements.shipment_rows
    assert.are.same({ true, "[item=" .. GEAR .. "] 10" }, { rows[1].goods.valid, rows[1].goods.caption })
  end)
end)
