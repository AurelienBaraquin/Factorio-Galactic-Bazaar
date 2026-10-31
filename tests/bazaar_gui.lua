-- In-game tests of the Galactic Bazaar window (scripts/bazaar_gui.lua, scripts/overview_gui.lua, #105,
-- ADR-0023): the hotkey and the mod button gated by research, the tabs and their lazy build, the hub
-- the window binds and trading only within reach, the Overview figures, the removal of the separate
-- windows of older saves, the refresh cost of each tab and persistence.
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local contracts = require("scripts.contracts")
local freight = require("scripts.freight")
local loans_core = require("scripts.core.loans")
local mod_gui = require("mod-gui")

local player, created

local function force_state() return storage.forces[player.force_index] end
local function technology() return player.force.technologies[bazaar_gui.TECHNOLOGY] end
local function window() return player.gui.screen[bazaar_gui.WINDOW] end
local function button() return mod_gui.get_button_flow(player)[bazaar_gui.BUTTON] end
local function values() return bazaar_gui.view(player.index, "overview").elements.values end

local function place(name, dx, dy)
  local entity = player.surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + dy }, force = "player", raise_built = true,
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

-- Types a quantity in the Market tab, as the player would (the preview follows).
local function type_quantity(view, text)
  view.elements.quantity.text = text
  bazaar_gui.on_gui_input({ element = view.elements.quantity, player_index = player.index,
    name = defines.events.on_gui_text_changed })
end

local function click(action)
  bazaar_gui.on_gui_input({ element = find(window(), action), player_index = player.index })
end

local function press_hotkey()
  bazaar_gui.on_toggle_input({ player_index = player.index, input_name = bazaar_gui.TOGGLE_INPUT })
end

-- Sets the research and runs the research handler, as finishing or reversing it would.
local function set_researched(researched)
  technology().researched = researched
  bazaar_gui.on_research_changed({ research = technology() })
end

-- Profiles `runs` refreshes of the shown tab and logs the average.
local function measure(name, runs)
  local profiler = helpers.create_profiler()
  for _ = 1, runs do bazaar_gui.refresh(player) end
  profiler.stop()
  profiler.divide(runs)
  log({ "", "[galactic-bazaar] ", name, " tab refresh (one player, average of ", runs, "): ", profiler })
end

describe("Galactic Bazaar window", function()
  before_each(function()
    player = game.get_player(1)
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_bazaar = {
      researched = technology().researched, balance = force_state().balance, reputation = force_state().reputation,
    }
    set_researched(true)
    test_helpers.set_balance(force_state(), 1e6)
    force_state().contracts.open = {}
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    if bazaar_gui.in_remote_view(player) then player.exit_remote_view() end
    bazaar_gui.close(player.index)
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    local saved = storage.gb_test_bazaar
    if saved then
      set_researched(saved.researched)
      test_helpers.set_balance(force_state(), saved.balance)
      force_state().reputation = saved.reputation
      storage.gb_test_bazaar = nil
    end
    force_state().credit_ban_until, force_state().bankruptcy_debt, force_state().arrears = nil, 0, 0
    force_state().contracts.open = {}
  end)

  test("the hotkey opens the window on the Overview anywhere, and closes it", function()
    press_hotkey()
    assert.is_true(window() ~= nil)
    assert.are.equal(window(), player.opened)
    assert.are.equal("overview", bazaar_gui.window(player.index).tab)
    assert.is_nil(bazaar_gui.window(player.index).hub)
    press_hotkey()
    assert.is_nil(window())
    assert.is_nil(storage.bazaar_gui[player.index])
  end)

  test("the hotkey opens nothing before the Galactic Bazaar research", function()
    set_researched(false)
    press_hotkey()
    assert.is_nil(window())
  end)

  test("the mod button follows the research and toggles the window", function()
    assert.is_true(button() ~= nil)
    bazaar_gui.on_gui_input({ element = button(), player_index = player.index })
    assert.is_true(window() ~= nil)
    bazaar_gui.on_gui_input({ element = button(), player_index = player.index })
    assert.is_nil(window())
    set_researched(false)
    local top = player.gui.top.mod_gui_top_frame
    assert.is_true(top == nil or top.mod_gui_inner_frame[bazaar_gui.BUTTON] == nil)
    bazaar_gui.on_force_event({ force = player.force })
    set_researched(true)
    assert.is_true(button() ~= nil)
  end)

  test("builds a tab when first shown and refreshes only the shown one", function()
    press_hotkey()
    local data = bazaar_gui.window(player.index)
    assert.are.same({ true, false, false }, { data.views.overview ~= nil, data.views.market ~= nil,
      data.views.contracts ~= nil })
    test_helpers.select_tab(player, "contracts")
    assert.are.equal("contracts", data.tab)
    assert.is_true(bazaar_gui.view(player.index, "contracts") ~= nil)
    test_helpers.set_balance(force_state(), 2500)
    bazaar_gui.on_refresh_tick({ tick = (player.index % bazaar_gui.SLOTS) * bazaar_gui.SLOT_TICKS })
    assert.are.same({ "gb-overview.credits", "1.00M" }, values().balance.caption)
    test_helpers.select_tab(player, "overview")
    assert.are.same({ "gb-overview.credits", "2.50k" }, values().balance.caption)
    assert.is_nil(data.views.market)
  end)

  test("binds the nearest hub within reach, and trades only through it", function()
    local hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 5, 0)
    press_hotkey()
    assert.are.equal(hub.unit_number, bazaar_gui.window(player.index).hub)
    test_helpers.select_tab(player, "market")
    local view = bazaar_gui.view(player.index, "market")
    view.selected = "item/iron-gear-wheel"
    type_quantity(view, "10")
    local home = player.position
    player.teleport({ home.x + 100, home.y })
    bazaar_gui.on_gui_input({ element = find(window(), "buy"), player_index = player.index })
    assert.is_nil(bazaar_gui.window(player.index).hub)
    assert.are.equal(0, freight.queued(hub.unit_number))
    player.teleport(home)
    bazaar_gui.on_gui_input({ element = find(window(), "buy"), player_index = player.index })
    assert.are.equal(1, freight.queued(hub.unit_number))
  end)

  test("shows the account, the next interest charge and the reputation's effects", function()
    test_helpers.set_balance(force_state(), -2000)
    force_state().reputation = 8
    press_hotkey()
    local shown = values()
    assert.are.same({ "gb-overview.credits", catalog.format_credits(-2000) }, shown.balance.caption)
    assert.are.same({ "gb-overview.overdraft-value", catalog.format_credits(2000) },
      { shown.overdraft.caption[1], shown.overdraft.caption[2] })
    local interest = shown["next-interest"].caption
    assert.are.same({ "gb-overview.next-interest-value", catalog.format_credits(10) }, { interest[1], interest[2] })
    assert.are.same({ "gb-overview.percent", "80" }, shown.fees.caption)
    assert.are.same({ "gb-overview.percent", "180" }, shown["contract-size"].caption)
    assert.are.equal("gb-overview.loan-terms-value", shown["loan-terms"].caption[1])
    assert.are.equal("gb-overview.credit-open", shown.credit.caption[1])
  end)

  test("shows insolvency, the credit ban and the debt to repay", function()
    test_helpers.set_balance(force_state(), -20000)
    force_state().insolvent_since = game.tick
    press_hotkey()
    assert.are.same({ "gb-overview.insolvent", "10:00" }, { values().state.caption[1], values().state.caption[2] })
    test_helpers.set_balance(force_state(), 0)
    force_state().credit_ban_until, force_state().bankruptcy_debt = game.tick + 3600, 1234
    bazaar_gui.refresh(player)
    assert.are.equal("gb-overview.solvent", values().state.caption[1])
    assert.are.same({ "gb-gui.credit-ban", "1:00", "1.23k" },
      { values().credit.caption[1], values().credit.caption[2], values().credit.caption[3] })
  end)

  test("sums up offers, loans and the next deadline", function()
    local id = contracts.offer(player.force_index, loans_core.spec(5000, 0))
    press_hotkey()
    assert.are.same({ "1", "0" }, { values().offers.caption, values().contracts.caption })
    contracts.accept(player.force_index, id)
    bazaar_gui.refresh(player)
    local loans = values().loans.caption
    assert.are.same({ "gb-overview.loans-value", 1, catalog.format_credits(5000) },
      { loans[1], tonumber(loans[2]), loans[3] })
    assert.are.same({ "gb-overview.next-due-value", { "gb-notify.kind-loan" } },
      { values()["next-due"].caption[1], values()["next-due"].caption[3] })
  end)

  test("removes the separate windows of older saves and their state on configuration change", function()
    local legacy = player.gui.screen.add({ type = "frame", name = "gb_market" })
    storage.players, storage.contracts_gui, storage.planets_gui = { [player.index] = { elements = {} } }, {}, {}
    press_hotkey()
    bazaar_gui.init()
    assert.is_false(legacy.valid)
    assert.are.same({ nil, nil, nil }, { storage.players, storage.contracts_gui, storage.planets_gui })
    assert.is_nil(window())
    assert.is_true(button() ~= nil)
  end)

  test("survives the events of a save from before the window until its configuration change", function()
    storage.bazaar_gui = nil
    local legacy = player.gui.screen.add({ type = "frame", name = "gb_market" })
    local legacy_buy = legacy.add({ type = "button", tags = { gb_action = "buy" } })
    bazaar_gui.on_refresh_tick({ tick = (player.index % bazaar_gui.SLOTS) * bazaar_gui.SLOT_TICKS })
    storage.bazaar_gui = nil
    bazaar_gui.on_hub_removed(1)
    storage.bazaar_gui = nil
    bazaar_gui.on_gui_input({ element = legacy_buy, player_index = player.index })
    assert.is_false(legacy.valid)
    storage.bazaar_gui = nil
    local closing = player.gui.screen.add({ type = "frame", name = "gb_contracts" })
    bazaar_gui.on_gui_closed({ element = closing, player_index = player.index })
    assert.is_false(closing.valid)
    storage.bazaar_gui = nil
    press_hotkey()
    assert.is_true(window() ~= nil)
    storage.bazaar_gui = nil
    bazaar_gui.on_gui_input({ element = button(), player_index = player.index })
    assert.is_true(window() ~= nil)
    assert.is_true(storage.bazaar_gui[player.index] ~= nil)
  end)

  test("trades nothing from remote view, where clicking a hub only shows its prices", function()
    local hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 5, 0)
    -- Entering remote view closes the player's opened GUI, as for the game's windows: reopen it there.
    player.set_controller({ type = defines.controllers.remote, position = hub.position, surface = hub.surface })
    assert.is_true(bazaar_gui.in_remote_view(player))
    bazaar_gui.open(player, "market", hub)
    assert.is_nil(window())
    press_hotkey()
    test_helpers.select_tab(player, "market")
    local view = bazaar_gui.view(player.index, "market")
    view.selected = "item/iron-gear-wheel"
    type_quantity(view, "10")
    click("buy")
    assert.are.same({ 0, 1e6 }, { freight.queued(hub.unit_number), force_state().balance })
    assert.are.same({ "gb-bazaar.remote-view" }, view.elements.power.caption)
    bazaar_gui.close(player.index)
    player.selected = hub
    bazaar_gui.on_hub_input({ player_index = player.index, input_name = bazaar_gui.HUB_INPUT })
    assert.are.same({ "market", nil }, { bazaar_gui.window(player.index).tab, bazaar_gui.window(player.index).hub })
    player.exit_remote_view()
    assert.is_false(bazaar_gui.in_remote_view(player))
    bazaar_gui.open(player, "market")
    assert.are.equal(hub.unit_number, bazaar_gui.window(player.index).hub)
  end)

  test("measures the refresh of each tab, and of a window looking for a hub in vain", function()
    -- A reach above the search cap: the window searches its whole radius, finding nothing.
    local bonus = player.force.character_reach_distance_bonus
    player.force.character_reach_distance_bonus = 100
    press_hotkey()
    measure("overview, no hub within 64 tiles,", 10)
    assert.is_nil(bazaar_gui.window(player.index).hub)
    player.force.character_reach_distance_bonus = bonus
    bazaar_gui.close(player.index)
    local hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    local concessions = player.force.technologies["gb-planetary-concessions"]
    local researched = concessions.researched
    concessions.researched = true
    bazaar_gui.open(player, "market", hub)
    for _, name in ipairs({ "overview", "market", "contracts", "planets" }) do
      test_helpers.select_tab(player, name)
      measure(name, 10)
    end
    concessions.researched = researched
    assert.are.equal("planets", bazaar_gui.window(player.index).tab)
  end)

  test("keeps an open window, its tab and its button across a save and reload", function()
    press_hotkey()
    test_helpers.select_tab(player, "contracts")
  end).after_reload_mods(function()
    local reloaded = game.get_player(1)
    local entry = storage.bazaar_gui[1]
    assert.are.same({ true, "contracts", true },
      { entry.elements.window.valid, entry.tab, entry.views.overview ~= nil })
    assert.are.equal(entry.elements.window, reloaded.opened)
    bazaar_gui.on_refresh_tick({ tick = (1 % bazaar_gui.SLOTS) * bazaar_gui.SLOT_TICKS })
    assert.is_true(bazaar_gui.view(1, "contracts").elements.debt.valid)
    assert.is_true(mod_gui.get_button_flow(reloaded)[bazaar_gui.BUTTON] ~= nil)
  end)
end)
