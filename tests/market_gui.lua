-- In-game tests of the market window (scripts/market_gui.lua), driven through the test save's player.
local freight = require("scripts.freight")
local market_gui = require("scripts.market_gui")

local player, surface, created

-- Places an entity at an offset from the player, so that it is within reach.
local function place(name, dx, dy, force)
  local entity = surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + dy }, force = force or "player",
    raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function find(element, action)
  if element.tags.gb_action == action then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action)
    if found then return found end
  end
end

local function window() return player.gui.screen.gb_market end
local function data() return storage.players[player.index] end
local function click(action)
  market_gui.on_gui_click({ element = find(window(), action), player_index = player.index })
end
local function type_text(action, text)
  local field = find(window(), action)
  field.text = text
  market_gui.on_gui_text_changed({ element = field, player_index = player.index })
end
local function force_state() return storage.forces[player.force_index] end
local function shown_items()
  local items = {}
  for _, row in ipairs(data().elements.rows) do
    if row.icon.visible then items[#items + 1] = row.icon.tags.item end
  end
  return items
end

describe("market window", function()
  local saved_balance, hub
  before_each(function()
    player = game.get_player(1)
    surface = player.surface
    created = {}
    saved_balance = force_state().balance
    force_state().balance = 1e6
    force_state().markets["item/iron-gear-wheel"] = nil
    player.get_main_inventory().clear()
    hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    created = created or {}
    market_gui.close(player.index)
    for _, entity in ipairs(created) do
      if entity.valid then entity.destroy() end
    end
    if saved_balance then force_state().balance = saved_balance end
    force_state().markets["item/iron-gear-wheel"] = nil
    player.get_main_inventory().clear()
  end)

  test("opens on a hub of the player's force, with balance and one page of items", function()
    market_gui.open(player, hub)
    assert.is_true(window() ~= nil)
    assert.are.equal(player.opened, window())
    assert.are.same({ "gb-gui.balance", "1.00M" }, data().elements.balance.caption)
    assert.are.equal(15, #shown_items())
  end)

  test("does not open on another force's hub", function()
    local foreign = place("gb-hub", -3, 0, "enemy")
    market_gui.open(player, foreign)
    assert.is_nil(window())
  end)

  test("opens when the player clicks a hub", function()
    player.selected = hub
    market_gui.on_open_input({ player_index = player.index, input_name = market_gui.INPUT })
    assert.is_true(window() ~= nil)
  end)

  test("filters the list by search text", function()
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    assert.are.same({ "iron-gear-wheel" }, shown_items())
  end)

  test("previews exactly what the purchase then costs", function()
    place("gb-import-chest", 5, 0)
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "100")
    local caption = data().elements.preview.caption
    assert.are.equal("gb-gui.preview", caption[1])
    assert.are.equal(100, tonumber(caption[2]))
    local cost, fee = freight.preview(player.force_index, "iron-gear-wheel", 100)
    assert.is_true(fee > 0)
    click("buy")
    assert.is_true(math.abs((1e6 - force_state().balance) - (cost + fee)) < 1e-6)
  end)

  test("orders a capsule to the hub and debits the force", function()
    place("gb-import-chest", 5, 0)
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "50")
    click("buy")
    assert.are.equal(1, freight.queued(hub.unit_number))
    assert.are.equal(50, freight.capsules(hub.unit_number)[1].count)
    assert.is_true(force_state().balance < 1e6)
  end)

  test("refuses to buy without power or without an import chest, changing nothing", function()
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "50")
    click("buy")
    assert.are.equal(1e6, force_state().balance)
    local chest = place("gb-import-chest", 5, 0)
    hub.energy = 0
    click("buy")
    assert.are.equal(0, chest.get_item_count("iron-gear-wheel"))
    assert.are.equal(0, freight.queued(hub.unit_number))
    assert.are.equal(1e6, force_state().balance)
  end)

  test("sells from the player's inventory and credits the force", function()
    player.get_main_inventory().insert({ name = "iron-gear-wheel", count = 30 })
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    click("sell")
    assert.are.equal(10, player.get_main_inventory().get_item_count("iron-gear-wheel"))
    assert.is_true(force_state().balance > 1e6)
  end)

  test("closes with its close button and on the game's close event", function()
    market_gui.open(player, hub)
    click("close")
    assert.is_nil(window())
    market_gui.open(player, hub)
    market_gui.on_gui_closed({ element = window(), player_index = player.index })
    assert.is_nil(window())
    assert.is_nil(data())
  end)

  local function refresh_slot_of_player()
    local slot = player.index % market_gui.SLOTS
    market_gui.on_refresh_tick({ tick = slot * market_gui.SLOT_TICKS })
  end

  test("refreshes an open window in its player's slot, keeping the row elements", function()
    market_gui.open(player, hub)
    local first_row = data().elements.rows[1].icon
    force_state().balance = 2500
    local profiler = helpers.create_profiler()
    refresh_slot_of_player()
    profiler.stop()
    log({ "", "[galactic-bazaar] market window refresh (one player, ", #storage.tradeable_items,
      " tradeable items): ", profiler })
    assert.are.same({ "gb-gui.balance", "2.50k" }, data().elements.balance.caption)
    assert.is_true(first_row.valid)
  end)

  test("closes when the player walks out of reach", function()
    market_gui.open(player, hub)
    local home = player.position
    player.teleport({ home.x + 100, home.y })
    refresh_slot_of_player()
    assert.is_nil(window())
    player.teleport(home)
  end)

  test("closes when its hub is destroyed", function()
    market_gui.open(player, hub)
    hub.destroy()
    after_ticks(1, function()
      assert.is_nil(window())
    end)
  end)

  test("closes when the player changes force, is removed or leaves", function()
    market_gui.open(player, hub)
    market_gui.on_player_event({ player_index = player.index })
    assert.is_nil(window())
    assert.is_nil(data())
  end)

  test("refuses to sell without power, keeping the items", function()
    player.get_main_inventory().insert({ name = "iron-gear-wheel", count = 30 })
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    hub.energy = 0
    click("sell")
    assert.are.equal(30, player.get_main_inventory().get_item_count("iron-gear-wheel"))
    assert.are.equal(1e6, force_state().balance)
  end)

  test("is closed on a save and reload, without leaving state behind", function()
    market_gui.open(player, hub)
    storage.gb_test_hub = hub.unit_number
  end).after_reload_mods(function()
    local entry = storage.players[1]
    assert.is_true(entry == nil or (entry.elements.window.valid and entry.hub == storage.gb_test_hub))
    market_gui.close(1)
    storage.gb_test_hub = nil
  end)
end)
