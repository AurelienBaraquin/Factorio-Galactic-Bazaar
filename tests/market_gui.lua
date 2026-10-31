-- In-game tests of the Market tab of the Galactic Bazaar window (scripts/market_gui.lua), driven
-- through the test save's player.
local test_helpers = require("tests.helpers")
local account = require("scripts.core.account")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")

local player, surface, created, hub

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

local function window() return player.gui.screen.gb_bazaar end
local function data() return bazaar_gui.view(player.index, "market") end
local function open() bazaar_gui.open(player, "market", hub) end
local function click(action)
  bazaar_gui.on_gui_input({ element = find(window(), action), player_index = player.index })
end
local function type_text(action, text)
  local field = find(window(), action)
  field.text = text
  bazaar_gui.on_gui_input({ element = field, player_index = player.index,
    name = defines.events.on_gui_text_changed })
end
local function force_state() return storage.forces[player.force_index] end
local function shown_items()
  local items = {}
  for _, row in ipairs(data().elements.rows) do
    if row.icon.visible then items[#items + 1] = row.icon.tags.key end
  end
  return items
end

describe("market tab", function()
  local saved_balance, saved_reputation
  before_each(function()
    player = game.get_player(1)
    surface = player.surface
    created = {}
    saved_balance = force_state().balance
    saved_reputation = force_state().reputation
    test_helpers.set_balance(force_state(), 1e6)
    force_state().markets["item/iron-gear-wheel"] = nil
    player.get_main_inventory().clear()
    hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    created = created or {}
    bazaar_gui.close(player.index)
    for _, entity in ipairs(created) do
      if entity.valid then entity.destroy() end
    end
    if saved_balance then test_helpers.set_balance(force_state(), saved_balance) end
    if saved_reputation then force_state().reputation = saved_reputation end
    force_state().markets["item/iron-gear-wheel"] = nil
    player.get_main_inventory().clear()
  end)

  test("opens on a hub of the player's force, with balance and one page of items", function()
    open()
    assert.is_true(window() ~= nil)
    assert.are.equal(player.opened, window())
    assert.are.same({ "gb-gui.balance", "1.00M" }, data().elements.balance.caption)
    local delivery = data().elements.freight.caption
    assert.are.same({ "gb-gui.delivery", { "gb-gui.tier-capsule" } }, { delivery[1], delivery[2] })
    assert.are.same({ 0, 20 }, { tonumber(delivery[3]), tonumber(delivery[4]) })
    assert.are.equal(15, #shown_items())
  end)

  test("shows the overdraft left and its limit", function()
    test_helpers.set_balance(force_state(), -400)
    open()
    local limit = account.overdraft_limit(force_state())
    assert.are.same({ "gb-gui.overdraft", catalog.format_credits(limit - 400), catalog.format_credits(limit) },
      data().elements.overdraft.caption)
    test_helpers.set_balance(force_state(), 1e6)
    bazaar_gui.close(player.index)
    open()
    assert.are.equal(catalog.format_credits(limit), data().elements.overdraft.caption[2])
  end)

  test("gives every row the same column widths, whatever the item name", function()
    open()
    local rows = data().elements.rows
    assert.is_true(rows[1].name.style.minimal_width > 0)
    assert.are.equal(rows[1].name.style.minimal_width, rows[1].name.style.maximal_width)
    for _, row in ipairs(rows) do
      assert.are.equal(rows[1].name.style.minimal_width, row.name.style.minimal_width)
      assert.are.equal(rows[1].name.style.maximal_width, row.name.style.maximal_width)
      assert.are.equal(rows[1].buy.style.maximal_width, row.buy.style.maximal_width)
      assert.are.same(row.name.caption, row.name.tooltip)
    end
    assert.are.equal("middle-right", rows[1].buy.parent.style.column_alignments[3])
  end)

  test("does not open on another force's hub", function()
    local foreign = place("gb-hub", -3, 0, "enemy")
    bazaar_gui.open(player, "market", foreign)
    assert.is_nil(window())
  end)

  test("opens on the market tab, bound to the hub, when the player clicks a hub", function()
    player.selected = hub
    bazaar_gui.on_hub_input({ player_index = player.index, input_name = bazaar_gui.HUB_INPUT })
    assert.is_true(window() ~= nil)
    local state = bazaar_gui.window(player.index)
    assert.are.same({ "market", hub.unit_number }, { state.tab, state.hub })
  end)

  test("filters the list by search text", function()
    open()
    type_text("search", "iron gear")
    assert.are.same({ "item/iron-gear-wheel" }, shown_items())
  end)

  test("lists fluids too, and refuses to sell them from the inventory", function()
    open()
    type_text("search", "crude oil")
    assert.are.equal("fluid/crude-oil", shown_items()[1])
    click("select")
    type_text("quantity", "10")
    local balance = force_state().balance
    click("sell")
    assert.are.equal(balance, force_state().balance)
    place("gb-fluid-import", 5, 4)
    click("buy")
    assert.are.equal("fluid", freight.capsules(hub.unit_number)[1].kind)
    force_state().markets["fluid/crude-oil"] = nil
  end)

  test("shows the force's reputation and its effects", function()
    force_state().reputation = 20
    open()
    local reputation = data().elements.reputation
    assert.are.same({ "gb-gui.reputation", 20 }, { reputation.caption[1], tonumber(reputation.caption[2]) })
    assert.are.same({ 50, 300 }, { tonumber(reputation.tooltip[2]), tonumber(reputation.tooltip[3]) })
  end)

  test("previews exactly what the purchase then costs", function()
    force_state().reputation = 7
    place("gb-import-chest", 5, 0)
    open()
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
    open()
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "50")
    click("buy")
    assert.are.equal(1, freight.queued(hub.unit_number))
    assert.are.equal(50, freight.capsules(hub.unit_number)[1].count)
    assert.is_true(force_state().balance < 1e6)
  end)

  test("refuses to buy without power or without an import chest, changing nothing", function()
    open()
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
    open()
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    click("sell")
    assert.are.equal(10, player.get_main_inventory().get_item_count("iron-gear-wheel"))
    assert.is_true(force_state().balance > 1e6)
  end)

  test("closes with its close button and on the game's close event", function()
    open()
    click("bazaar-close")
    assert.is_nil(window())
    open()
    bazaar_gui.on_gui_closed({ element = window(), player_index = player.index })
    assert.is_nil(window())
    assert.is_nil(bazaar_gui.window(player.index))
  end)

  local function refresh_slot_of_player()
    local slot = player.index % bazaar_gui.SLOTS
    bazaar_gui.on_refresh_tick({ tick = slot * bazaar_gui.SLOT_TICKS })
  end

  test("refreshes an open window in its player's slot, keeping the row elements", function()
    open()
    local first_row = data().elements.rows[1].icon
    test_helpers.set_balance(force_state(), 2500)
    local profiler = helpers.create_profiler()
    refresh_slot_of_player()
    profiler.stop()
    log({ "", "[galactic-bazaar] market tab refresh (one player, ", #storage.tradeable_items,
      " tradeable items): ", profiler })
    assert.are.same({ "gb-gui.balance", "2.50k" }, data().elements.balance.caption)
    assert.is_true(first_row.valid)
  end)

  test("stays open out of reach, showing prices but refusing to trade", function()
    player.get_main_inventory().insert({ name = "iron-gear-wheel", count = 30 })
    place("gb-import-chest", 5, 0)
    open()
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    local home = player.position
    player.teleport({ home.x + 100, home.y })
    refresh_slot_of_player()
    assert.is_true(window() ~= nil)
    assert.are.same({ "gb-bazaar.no-hub" }, data().elements.power.caption)
    assert.is_false(data().elements.freight.visible)
    assert.is_true(data().elements.rows[1].icon.visible)
    click("buy")
    click("sell")
    assert.are.equal(0, freight.queued(hub.unit_number))
    assert.are.equal(30, player.get_main_inventory().get_item_count("iron-gear-wheel"))
    assert.are.equal(1e6, force_state().balance)
    player.teleport(home)
    -- The preview was last computed without a hub: the first purchase is refused and shows the fee.
    click("buy")
    assert.are.same({ 0, hub.unit_number }, { freight.queued(hub.unit_number), data().tier_hub })
    click("buy")
    assert.are.equal(1, freight.queued(hub.unit_number))
  end)

  test("refuses a purchase whose preview has no tier or was computed for another hub", function()
    place("gb-import-chest", 5, 0)
    open()
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    data().tier = nil
    click("buy")
    assert.are.same({ 0, 1e6 }, { freight.queued(hub.unit_number), force_state().balance })
    assert.are.equal("capsule", data().tier)
    data().tier_hub = -1
    click("buy")
    assert.are.equal(0, freight.queued(hub.unit_number))
    click("buy")
    assert.are.equal(1, freight.queued(hub.unit_number))
  end)

  test("keeps the page when the player clicks in the search field", function()
    open()
    click("next-page")
    click("search")
    assert.are.equal(2, data().page)
    type_text("search", "")
    assert.are.equal(1, data().page)
  end)

  test("names why no tier can take an order, shows no fee and refuses it with that reason", function()
    place("gb-import-chest", 5, 0)
    open()
    type_text("search", "iron gear")
    click("select")
    local per_capsule = prototypes.item["iron-gear-wheel"].stack_size * freight.TIERS.capsule.capacity_stacks
    type_text("quantity", tostring(per_capsule * freight.TIERS.capsule.max_capsules + 1))
    assert.is_nil(data().tier)
    assert.are.same({ "gb-gui.refused-queue-full" }, data().elements.preview.caption[3])
    click("buy")
    assert.are.same({ 0, 1e6 }, { freight.queued(hub.unit_number), force_state().balance })
    type_text("quantity", "20")
    click("buy")
    assert.are.equal(1, freight.queued(hub.unit_number))
  end)

  test("forgets its hub when the hub is destroyed, and stays open", function()
    open()
    hub.destroy()
    after_ticks(1, function()
      assert.is_true(window() ~= nil)
      assert.is_nil(bazaar_gui.window(player.index).hub)
    end)
  end)

  test("closes when the player changes force, is removed or leaves", function()
    open()
    bazaar_gui.on_player_event({ player_index = player.index })
    assert.is_nil(window())
    assert.is_nil(bazaar_gui.window(player.index))
  end)

  test("refuses to sell without power, keeping the items", function()
    player.get_main_inventory().insert({ name = "iron-gear-wheel", count = 30 })
    open()
    type_text("search", "iron gear")
    click("select")
    type_text("quantity", "20")
    hub.energy = 0
    click("sell")
    assert.are.equal(30, player.get_main_inventory().get_item_count("iron-gear-wheel"))
    assert.are.equal(1e6, force_state().balance)
  end)

  test("keeps the window on its hub across a save and reload", function()
    open()
    storage.gb_test_hub = hub.unit_number
  end).after_reload_mods(function()
    local entry = storage.bazaar_gui[1]
    local kept = { entry.elements.window.valid, entry.tab, entry.hub }
    bazaar_gui.close(1)
    -- The reload emptied `created`: the hub is removed here, or later windows would bind it.
    local leftover = hubs.get(storage.gb_test_hub)
    if leftover then leftover.destroy() end
    local expected = storage.gb_test_hub
    storage.gb_test_hub = nil
    -- Asserted after the clean-up, so that a failure leaves nothing behind for later tests.
    assert.are.same({ true, "market", expected }, kept)
  end)
end)
