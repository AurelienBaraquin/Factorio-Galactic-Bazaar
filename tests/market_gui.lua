-- In-game tests of the market window (scripts/market_gui.lua), driven through the test save's player.
local market_gui = require("scripts.market_gui")

local player, surface, created

local function place(name, x, y, force)
  local entity = surface.create_entity({
    name = name, position = { x, y }, force = force or "player", raise_built = true,
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
    hub = place("gb-hub", 10, 10)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    market_gui.close(player.index)
    for _, entity in ipairs(created) do
      if entity.valid then entity.destroy() end
    end
    force_state().balance = saved_balance
    force_state().markets["item/iron-gear-wheel"] = nil
    player.get_main_inventory().clear()
  end)

  test("opens on a hub of the player's force, with balance and one page of items", function()
    market_gui.open(player, hub)
    assert.is_true(window() ~= nil)
    assert.are.equal(player.opened, window())
    assert.are.same({ "gb-gui.balance", "1.00M" }, data().elements.balance.caption)
    assert.are.equal(5 * 16, #data().elements.list.children)
  end)

  test("does not open on another force's hub", function()
    local foreign = place("gb-hub", 20, 10, "enemy")
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
    local items = {}
    for _, child in ipairs(data().elements.list.children) do
      if child.tags.item then items[#items + 1] = child.tags.item end
    end
    assert.are.same({ "iron-gear-wheel" }, items)
  end)

  test("previews the real cost and revenue of the typed quantity", function()
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "100")
    local caption = data().elements.preview.caption
    assert.are.equal("gb-gui.preview", caption[1])
    assert.are.equal(100, tonumber(caption[2]))
  end)

  test("buys into the hub's import chests and debits the force", function()
    local chest = place("gb-import-chest", 12, 10)
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "50")
    click("buy")
    assert.are.equal(50, chest.get_item_count("iron-gear-wheel"))
    assert.is_true(force_state().balance < 1e6)
  end)

  test("refuses to buy without power or without room, changing nothing", function()
    market_gui.open(player, hub)
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "50")
    click("buy")
    assert.are.equal(1e6, force_state().balance)
    local chest = place("gb-import-chest", 12, 10)
    hub.energy = 0
    click("buy")
    assert.are.equal(0, chest.get_item_count("iron-gear-wheel"))
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

  test("refreshes open windows without error", function()
    market_gui.open(player, hub)
    force_state().balance = 2500
    market_gui.on_refresh_tick()
    assert.are.same({ "gb-gui.balance", "2.50k" }, data().elements.balance.caption)
  end)
end)
