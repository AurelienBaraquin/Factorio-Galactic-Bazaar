-- The market window, opened by clicking a trading hub: balance, a searchable and paged list of
-- tradeable items with their prices, and a panel to buy into the hub's import chests or sell from
-- the player's inventory. Interface state is per player in storage.players; economy state stays per
-- force. Every action is re-validated, since GUI events are player input.
local cargo = require("scripts.cargo")
local catalog = require("scripts.core.catalog")
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local market_gui = {}

market_gui.INPUT = "gb-open-hub"
market_gui.REFRESH_INTERVAL = 60

local WINDOW = "gb_market"
local TREND_CAPTIONS = { up = "▲", down = "▼", flat = "–" }

local function item_label(name)
  return prototypes.item[name].localised_name
end

local function tradeable_items()
  local names = {}
  for key in pairs(storage.base_values) do
    local name = key:match("^item/(.+)$")
    if name and prototypes.item[name] then names[#names + 1] = name end
  end
  return names
end

local function window_of(player_index)
  local data = storage.players[player_index]
  local window = data and data.elements and data.elements.window
  return window and window.valid and window or nil
end

-- The hub this window trades through, if it still exists and belongs to the player's force.
local function trading_hub(player, data)
  local hub = hubs.get(data.hub)
  return hub and hub.force == player.force and hub or nil
end

local function refresh_status(player, data)
  local elements = data.elements
  local balance = storage.forces[player.force_index].balance
  elements.balance.caption = { "gb-gui.balance", catalog.format_credits(balance) }
  local hub = trading_hub(player, data)
  elements.power.caption = hub and hub.energy > 0 and { "gb-gui.hub-powered" } or { "gb-gui.hub-unpowered" }
end

local function refresh_list(player, data)
  local elements = data.elements
  local shown = catalog.page(catalog.search(tradeable_items(), data.filter), data.page)
  data.page = shown.page
  elements.page.caption = { "gb-gui.page", shown.page, shown.pages }
  local list = elements.list
  list.clear()
  for _, header in ipairs({ "", "item", "buy", "sell", "trend" }) do
    list.add({ type = "label", caption = header == "" and "" or { "gb-gui.column-" .. header },
      style = "bold_label" })
  end
  for _, name in ipairs(shown.names) do
    local quote = market.quote(player.force_index, "item", name)
    list.add({ type = "sprite-button", sprite = "item/" .. name, style = "slot_button",
      tags = { gb_action = "select", item = name }, toggled = name == data.selected })
    list.add({ type = "label", caption = item_label(name) })
    list.add({ type = "label", caption = catalog.format_credits(quote.buy) })
    list.add({ type = "label", caption = catalog.format_credits(quote.sell) })
    list.add({ type = "label", caption = TREND_CAPTIONS[catalog.trend(quote.history)] })
  end
end

local function refresh_detail(player, data)
  local elements = data.elements
  local name = data.selected
  elements.detail.visible = name ~= nil
  if not name then return end
  elements.detail_icon.sprite = "item/" .. name
  elements.detail_name.caption = item_label(name)
  local quantity = catalog.parse_quantity(elements.quantity.text)
  if not quantity then
    elements.preview.caption = { "gb-gui.enter-quantity" }
    return
  end
  local cost = market.preview(player.force_index, "item", name, "buy", quantity)
  local revenue = market.preview(player.force_index, "item", name, "sell", quantity)
  elements.preview.caption = { "gb-gui.preview", quantity,
    cost and catalog.format_credits(cost) or { "gb-gui.unavailable" },
    revenue and catalog.format_credits(revenue) or { "gb-gui.unavailable" } }
end

local function refresh(player, data)
  refresh_status(player, data)
  refresh_list(player, data)
  refresh_detail(player, data)
end

local function add_title_bar(window)
  local bar = window.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = window
  bar.add({ type = "label", caption = { "gb-gui.title" }, style = "frame_title", ignored_by_interaction = true })
  local spacer = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  bar.add({ type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tags = { gb_action = "close" } })
end

local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  add_title_bar(window)
  local body = window.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local status = body.add({ type = "flow", direction = "horizontal" })
  local elements = { window = window }
  elements.balance = status.add({ type = "label", style = "bold_label" })
  elements.power = status.add({ type = "label" })

  local controls = body.add({ type = "flow", direction = "horizontal" })
  controls.add({ type = "label", caption = { "gb-gui.search" } })
  elements.search = controls.add({ type = "textfield", tags = { gb_action = "search" } })
  controls.add({ type = "button", caption = "<", tags = { gb_action = "previous-page" } })
  elements.page = controls.add({ type = "label" })
  controls.add({ type = "button", caption = ">", tags = { gb_action = "next-page" } })

  elements.list = body.add({ type = "table", column_count = 5 })

  local detail = body.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.detail = detail
  local heading = detail.add({ type = "flow", direction = "horizontal" })
  elements.detail_icon = heading.add({ type = "sprite", sprite = "utility/close" })
  elements.detail_name = heading.add({ type = "label", style = "bold_label" })
  local actions = detail.add({ type = "flow", direction = "horizontal" })
  actions.add({ type = "label", caption = { "gb-gui.quantity" } })
  elements.quantity = actions.add({ type = "textfield", text = "1", numeric = true,
    tags = { gb_action = "quantity" } })
  actions.add({ type = "button", caption = { "gb-gui.buy" }, style = "green_button", tags = { gb_action = "buy" } })
  actions.add({ type = "button", caption = { "gb-gui.sell" }, style = "red_button", tags = { gb_action = "sell" } })
  elements.preview = detail.add({ type = "label" })

  window.force_auto_center()
  return elements
end

--- Opens the market window of a hub for a player (its force must own the hub).
function market_gui.open(player, hub)
  if hub.force ~= player.force then return end
  market_gui.close(player.index)
  local data = { hub = hub.unit_number, filter = "", page = 1 }
  data.elements = build(player)
  storage.players[player.index] = data
  refresh(player, data)
  player.opened = data.elements.window
end

function market_gui.close(player_index)
  local window = window_of(player_index)
  if window then window.destroy() end
  storage.players[player_index] = nil
end

local function notify(player, message)
  player.print(message)
end

local actions = {}

function actions.close(player)
  market_gui.close(player.index)
end

function actions.select(player, data, tags)
  data.selected = tags.item
  refresh_list(player, data)
  refresh_detail(player, data)
end

function actions.search(player, data)
  data.filter = data.elements.search.text
  data.page = 1
  refresh_list(player, data)
end

actions["previous-page"] = function(player, data)
  data.page = data.page - 1
  refresh_list(player, data)
end

actions["next-page"] = function(player, data)
  data.page = data.page + 1
  refresh_list(player, data)
end

function actions.quantity(player, data)
  refresh_detail(player, data)
end

function actions.buy(player, data)
  local name, quantity = data.selected, catalog.parse_quantity(data.elements.quantity.text)
  local hub = trading_hub(player, data)
  if not (name and quantity) then return end
  if not (hub and hub.energy > 0) then return notify(player, { "gb-gui.hub-unpowered" }) end
  local units = math.min(quantity, cargo.import_capacity(hub.unit_number, name))
  if units <= 0 then return notify(player, { "gb-gui.no-space" }) end
  local ok, result = market.buy(player.force_index, "item", name, units)
  if not ok then return notify(player, { "gb-gui.refused-" .. result }) end
  cargo.deliver(hub.unit_number, name, units)
  notify(player, { "gb-gui.bought", units, item_label(name), catalog.format_credits(result) })
  refresh(player, data)
end

function actions.sell(player, data)
  local name, quantity = data.selected, catalog.parse_quantity(data.elements.quantity.text)
  local hub = trading_hub(player, data)
  local inventory = player.get_main_inventory()
  if not (name and quantity and inventory) then return end
  if not (hub and hub.energy > 0) then return notify(player, { "gb-gui.hub-unpowered" }) end
  local sold, revenue = cargo.sell_stacks(inventory, player.force_index, 0, name, quantity)
  if sold == 0 then return notify(player, { "gb-gui.sold-nothing" }) end
  notify(player, { "gb-gui.sold", sold, item_label(name), catalog.format_credits(revenue) })
  refresh(player, data)
end

-- Runs the action named by an element's tags, if the element belongs to this player's window.
local function dispatch(event)
  local element = event.element
  if not (element and element.valid) then return end
  local action = actions[element.tags.gb_action]
  local data = storage.players[event.player_index]
  if not (action and data and window_of(event.player_index)) then return end
  action(game.get_player(event.player_index), data, element.tags)
end

market_gui.on_gui_click = dispatch

function market_gui.on_gui_text_changed(event)
  local action = event.element.valid and event.element.tags.gb_action
  if action == "search" or action == "quantity" then dispatch(event) end
end

function market_gui.on_gui_closed(event)
  if event.element and event.element.valid and event.element.name == WINDOW then
    market_gui.close(event.player_index)
  end
end

--- The "open GUI" control: opens the market when the player clicks one of their force's hubs.
function market_gui.on_open_input(event)
  local player = game.get_player(event.player_index)
  local selected = player and player.selected
  if selected and selected.valid and selected.name == hubs.NAME then market_gui.open(player, selected) end
end

--- on_nth_tick(REFRESH_INTERVAL): refreshes the open windows (only the rows they show).
function market_gui.on_refresh_tick()
  for player_index, data in pairs(storage.players) do
    if window_of(player_index) then refresh(game.get_player(player_index), data) end
  end
end

function market_gui.on_player_removed(event)
  storage.players[event.player_index] = nil
end

--- on_init and on_configuration_changed: creates the state and closes every window, which is
--- rebuilt on the next opening (styles and prototypes may have changed).
function market_gui.init()
  storage.players = storage.players or {}
  local open = {}
  for player_index in pairs(storage.players) do open[#open + 1] = player_index end
  for _, player_index in ipairs(open) do market_gui.close(player_index) end
end

return market_gui
