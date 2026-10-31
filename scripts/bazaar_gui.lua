-- The Galactic Bazaar window (#105, ADR-0023): one window with tabs (Overview, Market, Contracts,
-- Planets, and whatever later features register), opened by a hotkey or the button in the top-left
-- mod button flow (both once the force researched the Galactic Bazaar) or by clicking a trading hub,
-- which opens it on the Market tab. Consultation works anywhere, remote view included; actions that
-- trade or commit the force go through the window's hub, which must be the player's force's and
-- within the reach of the player's body (never from remote view) when they run. The window binds the
-- hub it was opened from, otherwise the nearest hub within reach, and looks for one again while it
-- has none in reach.
--
-- Tabs register at load (file scope, the same on every peer) with `register_tab`. A tab's content
-- is built the first time it is shown and then updated in place; only the shown tab of a connected
-- player's open window is refreshed, once a second. Interface state lives in storage.bazaar_gui,
-- created by on_init and on_configuration_changed and, for a save upgraded from a version without it
-- whose events run before on_configuration_changed, lazily by the handlers; economy state stays per
-- force.
local hubs = require("scripts.hubs")
local mod_gui = require("mod-gui")

local bazaar_gui = {}

bazaar_gui.TOGGLE_INPUT = "gb-toggle-bazaar"
bazaar_gui.HUB_INPUT = "gb-open-hub"
bazaar_gui.TECHNOLOGY = "gb-galactic-bazaar"
bazaar_gui.WINDOW = "gb_bazaar"
bazaar_gui.BUTTON = "gb_bazaar_button"
bazaar_gui.DEFAULT_TAB = "overview"
-- Each open window is refreshed every SLOT_TICKS × SLOTS ticks (once a second); windows are spread
-- over the slots by player index, so they do not all refresh on the same tick.
bazaar_gui.SLOT_TICKS = 6
bazaar_gui.SLOTS = 10
-- How far, at most, the window looks for a hub to bind: a player without a character has an
-- unbounded reach, and the search must stay small.
bazaar_gui.MAX_HUB_SEARCH = 64
-- The GUI input events routed to the actions of this mod's elements (control.lua registers them).
bazaar_gui.GUI_EVENTS = {
  defines.events.on_gui_click, defines.events.on_gui_text_changed, defines.events.on_gui_confirmed,
  defines.events.on_gui_elem_changed, defines.events.on_gui_checked_state_changed,
  defines.events.on_gui_selection_state_changed, defines.events.on_gui_value_changed,
}

local PANE = "gb_bazaar_tabs"
-- The separate windows of saves made before the central window (0.1.30 and older).
local LEGACY_WINDOWS = { gb_market = true, gb_contracts = true, gb_planets = true }

-- Registered tabs, in display order, by name, and the tab owning each action name.
local tabs, tab_by_name, action_tab = {}, {}, {}

--- Registers a tab, at load (file scope), from a definition:
--- - `name` (string, unique): the tab's key; its caption is the locale key `gb-bazaar.tab-<name>`.
--- - `order` (number, unique): position among the tabs, lowest first.
--- - `build(player, container, view, window)`: fills `container` (a vertical flow) the first time the
---   tab is shown, keeping in `view` (the tab's state in storage, a table it owns) the elements and
---   state it needs; `view.elements` must be set.
--- - `refresh(player, view, window)`: updates the built content in place.
--- - `actions` (optional): {[gb_action] = function(player, view, tags, window, element)}, run when an
---   element of this mod tagged with that `gb_action` raises one of `GUI_EVENTS` (click, text changed,
---   confirmed, element chosen, checkbox, selection, slider), `element` being that element; names are
---   unique across tabs. An action that cares which event fired checks the element's type.
--- - `available(player)` (optional): whether the tab can be shown; when false it is disabled, with
---   the tooltip `locked_tooltip(player)`.
--- `window` is the player's window state: `hub` (the bound hub's unit number, or nil), `tab`, `views`.
function bazaar_gui.register_tab(definition)
  assert(not tab_by_name[definition.name], "tab registered twice: " .. definition.name)
  for _, other in ipairs(tabs) do
    assert(other.order ~= definition.order, "tab order taken twice: " .. definition.order)
  end
  for action in pairs(definition.actions or {}) do
    assert(not action_tab[action], "action registered twice: " .. action)
    action_tab[action] = definition.name
  end
  tab_by_name[definition.name] = definition
  tabs[#tabs + 1] = definition
  table.sort(tabs, function(a, b) return a.order < b.order end)
end

--- Whether a force has researched the Galactic Bazaar, which shows the button and enables the hotkey.
function bazaar_gui.researched(force)
  local technology = force.technologies[bazaar_gui.TECHNOLOGY]
  return technology ~= nil and technology.researched
end

-- The window states by player index. A save upgraded from 0.1.30 or older has none until
-- on_configuration_changed, and events can run before it: they create the table (never on_load).
local function windows()
  storage.bazaar_gui = storage.bazaar_gui or {}
  return storage.bazaar_gui
end

-- The player's window state, if the window is open.
local function window_of(player_index)
  local data = windows()[player_index]
  local window = data and data.elements.window
  return window and window.valid and data or nil
end

--- The state of a player's open window, or nil.
bazaar_gui.window = window_of

--- The state of a tab of a player's open window once it has been built, or nil.
function bazaar_gui.view(player_index, name)
  local data = window_of(player_index)
  local view = data and data.views[name]
  return view and view.elements and view or nil
end

--- Whether the player looks through remote view (the map, another surface): nothing trades from it.
function bazaar_gui.in_remote_view(player)
  return player.controller_type == defines.controllers.remote
end

-- The hub with this unit number if it is the player's force's and within reach, or nil; never in
-- remote view.
local function usable_hub(player, unit_number)
  local hub = unit_number and hubs.get(unit_number)
  if hub and hub.force == player.force and not bazaar_gui.in_remote_view(player) and player.can_reach_entity(hub) then
    return hub
  end
  return nil
end

-- The unit number of the nearest hub of the player's force within reach of the player's body (its
-- physical surface and position), ties to the lowest unit number, or nil; none in remote view.
local function nearest_hub(player)
  if bazaar_gui.in_remote_view(player) then return nil end
  local position = player.physical_position
  local best, best_distance
  local found = player.physical_surface.find_entities_filtered({ name = hubs.NAME, force = player.force,
    position = position, radius = math.min(player.reach_distance, bazaar_gui.MAX_HUB_SEARCH) })
  for _, hub in ipairs(found) do
    if usable_hub(player, hub.unit_number) then
      local dx, dy = hub.position.x - position.x, hub.position.y - position.y
      local distance = dx * dx + dy * dy
      if not best or distance < best_distance or (distance == best_distance and hub.unit_number < best.unit_number) then
        best, best_distance = hub, distance
      end
    end
  end
  return best and best.unit_number or nil
end

--- The hub a player's window trades through: the bound one while it is the player's force's and
--- within reach, otherwise the nearest such hub, which the window binds; nil when none is in reach or
--- the player is in remote view. GUI events are player input: every action that trades or commits
--- the force calls this when it runs.
function bazaar_gui.hub(player, window)
  local hub = usable_hub(player, window.hub)
  if hub then return hub end
  window.hub = nearest_hub(player)
  return window.hub and hubs.get(window.hub) or nil
end

--- The hub the window was bound to by its last refresh or action, without looking again (a tab's
--- refresh runs right after the window resolved it), or nil.
function bazaar_gui.bound_hub(window)
  return window.hub and hubs.get(window.hub) or nil
end

--- What to tell a player whose action found no hub: remote view, or no hub within reach.
function bazaar_gui.no_hub_message(player)
  return bazaar_gui.in_remote_view(player) and { "gb-bazaar.remote-view" } or { "gb-bazaar.no-hub" }
end

local function add_title_bar(window)
  local bar = window.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = window
  bar.add({ type = "label", caption = { "gb-bazaar.title" }, style = "frame_title", ignored_by_interaction = true })
  local spacer = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  bar.add({ type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tags = { gb_action = "bazaar-close" } })
end

-- The window and one empty tab per registered tab; contents are built when first shown.
local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = bazaar_gui.WINDOW, direction = "vertical" })
  add_title_bar(window)
  local pane = window.add({ type = "tabbed-pane", name = PANE })
  local elements = { window = window, pane = pane, tabs = {} }
  for index, definition in ipairs(tabs) do
    local tab = pane.add({ type = "tab", caption = { "gb-bazaar.tab-" .. definition.name },
      tags = { gb_tab = definition.name } })
    local content = pane.add({ type = "flow", direction = "vertical" })
    pane.add_tab(tab, content)
    elements.tabs[definition.name] = { tab = tab, content = content, index = index }
  end
  window.force_auto_center()
  return elements
end

local function available(player, definition)
  return not definition.available or definition.available(player)
end

-- Enables the tabs the player may see, with the reason as tooltip on the others; a tab is written
-- only when that changes (tabs start enabled, without tooltip).
local function update_tabs(player, data)
  for _, definition in ipairs(tabs) do
    local tab = data.elements.tabs[definition.name].tab
    local open = available(player, definition)
    if tab.enabled ~= open then
      tab.enabled = open
      tab.tooltip = not open and definition.locked_tooltip and definition.locked_tooltip(player) or ""
    end
  end
end

-- The shown tab's view, built on first use.
local function shown_view(player, data)
  local definition = tab_by_name[data.tab]
  local view = data.views[data.tab]
  if not view then
    view = {}
    data.views[data.tab] = view
    definition.build(player, data.elements.tabs[data.tab].content, view, data)
  end
  return definition, view
end

-- Refreshes the shown tab, after the hub binding and the tabs' availability; a tab that is no longer
-- available gives way to the default one.
local function refresh(player, data)
  bazaar_gui.hub(player, data)
  update_tabs(player, data)
  if not available(player, tab_by_name[data.tab]) then
    data.tab = bazaar_gui.DEFAULT_TAB
    data.elements.pane.selected_tab_index = data.elements.tabs[data.tab].index
  end
  local definition, view = shown_view(player, data)
  definition.refresh(player, view, data)
end

--- Refreshes the shown tab of a player's open window now (after an action changed what it shows).
function bazaar_gui.refresh(player)
  local data = window_of(player.index)
  if data then refresh(player, data) end
end

-- Shows tab `name` (the default one when it is unknown or not available) and refreshes it.
local function show_tab(player, data, name)
  local definition = tab_by_name[name]
  if not (definition and available(player, definition)) then name = bazaar_gui.DEFAULT_TAB end
  data.tab = name
  data.elements.pane.selected_tab_index = data.elements.tabs[name].index
  refresh(player, data)
end

--- Opens a player's window on tab `tab_name` (the Overview when nil), or shows that tab if it is
--- open. With a `hub`, which must be the player's force's and within reach (otherwise nothing
--- happens), the window binds it.
function bazaar_gui.open(player, tab_name, hub)
  if hub and not usable_hub(player, hub.unit_number) then return end
  local data = window_of(player.index)
  if not data then
    bazaar_gui.close(player.index)
    -- A window whose state is gone (never expected; a lost state must not block opening).
    local orphan = player.gui.screen[bazaar_gui.WINDOW]
    if orphan then orphan.destroy() end
    data = { views = {}, tab = bazaar_gui.DEFAULT_TAB }
    data.elements = build(player)
    windows()[player.index] = data
  end
  if hub then data.hub = hub.unit_number end
  show_tab(player, data, tab_name or bazaar_gui.DEFAULT_TAB)
  -- Like the game's windows: E or Esc closes it.
  if player.opened ~= data.elements.window then player.opened = data.elements.window end
end

function bazaar_gui.close(player_index)
  local all = windows()
  local data = all[player_index]
  local window = data and data.elements.window
  all[player_index] = nil
  if window and window.valid then window.destroy() end
end

-- The hotkey and the button: closes an open window, or opens one once the force has researched the
-- Galactic Bazaar.
local function toggle(player)
  if window_of(player.index) then return bazaar_gui.close(player.index) end
  if not bazaar_gui.researched(player.force) then
    return player.print({ "gb-bazaar.locked", prototypes.technology[bazaar_gui.TECHNOLOGY].localised_name })
  end
  bazaar_gui.open(player)
end

local central_actions = {
  ["bazaar-close"] = function(player) bazaar_gui.close(player.index) end,
  ["bazaar-toggle"] = toggle,
}

-- The top-level screen window of an element if it is stale: one of the separate windows of an older
-- save, or a Galactic Bazaar window that is not the one the player's state holds.
local function stale_window(element, player_index)
  local root = element
  while root.parent and root.parent.parent do root = root.parent end
  if not (root.parent and root.parent.name == "screen") then return nil end
  if LEGACY_WINDOWS[root.name] then return root end
  local data = root.name == bazaar_gui.WINDOW and window_of(player_index)
  if root.name == bazaar_gui.WINDOW and not (data and data.elements.window == root) then return root end
  return nil
end

-- Runs the action named by one of this mod's elements: the window's own, or a tab's when the window
-- is open and that tab built. An element of a stale window destroys that window.
local function dispatch(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  local stale = stale_window(element, event.player_index)
  if stale then return stale.destroy() end
  local action = element.tags.gb_action
  if not action then return end
  local player = game.get_player(event.player_index)
  if central_actions[action] then return central_actions[action](player) end
  local name = action_tab[action]
  local data = name and window_of(event.player_index)
  local view = data and data.views[name]
  if not (view and view.elements) then return end
  tab_by_name[name].actions[action](player, view, element.tags, data, element)
end

--- Every event of `GUI_EVENTS`.
bazaar_gui.on_gui_input = dispatch

--- on_gui_selected_tab_changed: the player picked a tab of the window.
function bazaar_gui.on_gui_selected_tab_changed(event)
  local pane = event.element
  if not (pane and pane.valid and pane.name == PANE and pane.get_mod() == script.mod_name) then return end
  local data = window_of(event.player_index)
  local selected = pane.selected_tab_index and pane.tabs[pane.selected_tab_index]
  if not (data and selected) then return end
  show_tab(game.get_player(event.player_index), data, selected.tab.tags.gb_tab)
end

--- on_gui_closed: E, Esc or another window closes this one, or a window left by an older save.
function bazaar_gui.on_gui_closed(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  if stale_window(element, event.player_index) == element then
    element.destroy()
  elseif element.name == bazaar_gui.WINDOW then
    bazaar_gui.close(event.player_index)
  end
end

--- The hotkey (`TOGGLE_INPUT`).
function bazaar_gui.on_toggle_input(event)
  local player = game.get_player(event.player_index)
  if player then toggle(player) end
end

--- The game's "open GUI" control (`HUB_INPUT`): clicking one of the force's hubs within reach opens
--- the window on the Market tab, bound to that hub. In remote view the tab opens without a hub:
--- prices can be read, nothing traded.
function bazaar_gui.on_hub_input(event)
  local player = game.get_player(event.player_index)
  local selected = player and player.selected
  if not (selected and selected.valid and selected.name == hubs.NAME) then return end
  if bazaar_gui.in_remote_view(player) then
    if selected.force == player.force then bazaar_gui.open(player, "market") end
    return
  end
  bazaar_gui.open(player, "market", selected)
end

--- on_nth_tick(SLOT_TICKS): refreshes the shown tab of the open windows of connected players whose
--- slot comes up.
function bazaar_gui.on_refresh_tick(event)
  local slot = (event.tick / bazaar_gui.SLOT_TICKS) % bazaar_gui.SLOTS
  for player_index in pairs(windows()) do
    local player = game.get_player(player_index)
    local data = player_index % bazaar_gui.SLOTS == slot and player and player.connected and window_of(player_index)
    if data then refresh(player, data) end
  end
end

--- A hub is gone: the windows bound to it look for another one.
function bazaar_gui.on_hub_removed(hub_unit_number)
  for _, data in pairs(windows()) do
    if data.hub == hub_unit_number then data.hub = nil end
  end
end

-- The mod button flow of a player, if it exists (mod_gui.get_button_flow would create it).
local function existing_button_flow(player)
  local top = player.gui.top
  if top.mod_gui_button_flow then return top.mod_gui_button_flow end
  local frame = top.mod_gui_top_frame
  return frame and frame.mod_gui_inner_frame
end

--- Shows the button in the player's mod button flow once the force has researched the Galactic
--- Bazaar, and removes it otherwise; the shared flow itself is left to mod-gui.
function bazaar_gui.sync_button(player)
  local flow = existing_button_flow(player)
  local button = flow and flow[bazaar_gui.BUTTON]
  if bazaar_gui.researched(player.force) then
    if button then return end
    mod_gui.get_button_flow(player).add({ type = "sprite-button", name = bazaar_gui.BUTTON, sprite = "item/gb-hub",
      style = mod_gui.button_style, tooltip = { "gb-bazaar.button-tooltip" }, tags = { gb_action = "bazaar-toggle" } })
  elseif button and button.get_mod() == script.mod_name then
    button.destroy()
  end
end

--- Every player's button: on init and configuration change, and every interest tick as a self-heal,
--- since research_all_technologies, reset_technologies or copy_from raise no per-technology event.
function bazaar_gui.sync_buttons()
  for _, player in pairs(game.players) do bazaar_gui.sync_button(player) end
end

local function sync_force(force)
  for _, player in pairs(force.players) do bazaar_gui.sync_button(player) end
end

--- on_player_created: the new player gets the button if the force has the research.
function bazaar_gui.on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then bazaar_gui.sync_button(player) end
end

--- on_research_finished and on_research_reversed: the Galactic Bazaar shows or hides the button.
function bazaar_gui.on_research_changed(event)
  if event.research.name == bazaar_gui.TECHNOLOGY then sync_force(event.research.force) end
end

--- on_force_reset and on_technology_effects_reset: research may have changed wholesale.
function bazaar_gui.on_force_event(event)
  sync_force(event.force)
end

--- on_player_left_game, on_player_changed_force and on_player_removed: the window no longer applies;
--- a player who changed force gets that force's button.
function bazaar_gui.on_player_event(event)
  bazaar_gui.close(event.player_index)
  local player = game.get_player(event.player_index)
  if player and player.valid and event.name == defines.events.on_player_changed_force then
    bazaar_gui.sync_button(player)
  end
end

--- on_init and on_configuration_changed: creates the state, closes every window (rebuilt on the
--- next opening: styles, prototypes and tabs may have changed), removes the separate windows of
--- older saves and their state, and shows or hides every player's button.
function bazaar_gui.init()
  local open = {}
  for player_index in pairs(windows()) do open[#open + 1] = player_index end
  for _, player_index in ipairs(open) do bazaar_gui.close(player_index) end
  storage.players, storage.contracts_gui, storage.planets_gui = nil, nil, nil
  for _, player in pairs(game.players) do
    for name in pairs(LEGACY_WINDOWS) do
      local legacy = player.gui.screen[name]
      if legacy and legacy.get_mod() == script.mod_name then legacy.destroy() end
    end
  end
  bazaar_gui.sync_buttons()
end

return bazaar_gui
