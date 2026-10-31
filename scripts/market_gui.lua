-- The market window, opened by clicking a trading hub within reach: balance and overdraft left, a searchable and paged
-- list of tradeable items with their prices, and a panel to buy into the hub's import chests or sell
-- from the player's inventory. Interface state is per player in storage.players; economy state
-- stays per force. Every action is re-validated, since GUI events are player input.
local cargo = require("scripts.cargo")
local account = require("scripts.core.account")
local catalog = require("scripts.core.catalog")
local contracts_gui = require("scripts.contracts_gui")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local concessions = require("scripts.concessions")
local planets_gui = require("scripts.planets_gui")
local reputation = require("scripts.core.reputation")
local telecom = require("scripts.telecom")
local telecom_core = require("scripts.core.telecom")

local market_gui = {}

market_gui.INPUT = "gb-open-hub"
-- Each open window is refreshed every SLOT_TICKS × SLOTS ticks (once a second); windows are spread
-- over the slots by player index, so they do not all refresh on the same tick.
market_gui.SLOT_TICKS = 6
market_gui.SLOTS = 10

local WINDOW = "gb_market"
local TREND_CAPTIONS = { up = "▲", down = "▼", flat = "–" }
-- Price history points shown in the detail panel (telecommunications level 2).
local HISTORY_WIDTH = 30

-- The list shows keys: "item/<name>" and "fluid/<name>" (fluids are bought into import manifolds).
local function split(key)
  return key:match("^(%a+)/(.+)$")
end

local function label(key)
  local kind, name = split(key)
  return prototypes[kind][name].localised_name
end

-- Every tradeable item, then every tradeable fluid, as keys.
local function tradeable_keys()
  local keys = {}
  for _, name in ipairs(storage.tradeable_items) do keys[#keys + 1] = "item/" .. name end
  for _, name in ipairs(storage.tradeable_fluids) do keys[#keys + 1] = "fluid/" .. name end
  return keys
end

local function window_of(player_index)
  local data = storage.players[player_index]
  local window = data and data.elements and data.elements.window
  return window and window.valid and window or nil
end

-- The hub this window trades through, if it still exists, belongs to the player's force and is
-- within the player's reach.
local function usable_hub(player, data)
  local hub = hubs.get(data.hub)
  if hub and hub.force == player.force and player.can_reach_entity(hub) then return hub end
  return nil
end

local function refresh_status(player, data)
  local elements = data.elements
  local state = storage.forces[player.force_index]
  elements.balance.caption = { "gb-gui.balance", catalog.format_credits(state.balance) }
  elements.overdraft.caption = { "gb-gui.overdraft", catalog.format_credits(account.overdraft_left(state)),
    catalog.format_credits(account.overdraft_limit(state)) }
  elements.reputation.caption = { "gb-gui.reputation", state.reputation }
  elements.reputation.tooltip = { "gb-gui.reputation-effects",
    string.format("%.4g", reputation.fee_factor(state.reputation) * 100),
    string.format("%.4g", reputation.contract_scale(state.reputation) * 100) }
  local hub = usable_hub(player, data)
  elements.power.caption = hub and hub.energy > 0 and { "gb-gui.hub-powered" } or { "gb-gui.hub-unpowered" }
  elements.planets.visible = concessions.researched(player.force, concessions.CONCESSION_TECHNOLOGY)
  local tier = freight.tier(data.hub)
  elements.freight.caption = { "gb-gui.delivery", { "gb-gui.tier-" .. tier.name },
    freight.queued(data.hub, tier.name), tier.max_capsules }
end

-- Updates the fixed rows in place: elements are never destroyed by a refresh, so a click sent just
-- before it still finds its button (multiplayer latency).
local function refresh_list(player, data)
  local elements = data.elements
  -- Below telecommunications 2 the trend column stays in place, empty: hiding its cells would shift
  -- every later cell of the table into the wrong column.
  local history = telecom.shows_history(player.force)
  local period = telecom.period(player.force)
  elements.trend_header.caption = history and { "gb-gui.column-trend" } or ""
  local shown = catalog.page(data.matches, data.page)
  data.page = shown.page
  elements.page.caption = { "gb-gui.page", shown.page, shown.pages }
  for i, row in ipairs(elements.rows) do
    local name = shown.names[i]
    -- The list is taken when the window opens: an item whose value another mod removes since then
    -- is hidden, and one that gains a value appears on the next opening.
    local quote
    if name then
      local kind, item = split(name)
      quote = telecom.quote(player.force_index, kind, item, period)
    end
    for _, cell in pairs(row) do cell.visible = quote ~= nil end
    if quote then
      row.icon.sprite = name
      row.icon.tags = { gb_action = "select", key = name }
      row.icon.toggled = name == data.selected
      row.name.caption = label(name)
      row.name.tooltip = label(name)
      row.buy.caption = catalog.format_credits(quote.buy)
      row.sell.caption = catalog.format_credits(quote.sell)
      row.trend.caption = history and TREND_CAPTIONS[catalog.trend(quote.history)] or ""
    end
  end
end

local function refresh_detail(player, data)
  local elements = data.elements
  local name = data.selected
  elements.detail.visible = name ~= nil
  if not name then return end
  local kind, item = split(name)
  elements.detail_icon.sprite = name
  elements.detail_name.caption = label(name)
  local seen = telecom.shows_history(player.force) and telecom.quote(player.force_index, kind, item)
  -- A market entry has no history for its first NPC steps: nothing to draw yet.
  seen = seen and #seen.history >= 2 and seen
  elements.history.visible = seen and true or false
  if seen then elements.history.caption = { "gb-gui.history", telecom_core.sparkline(seen.history, HISTORY_WIDTH) } end
  local quantity = catalog.parse_quantity(elements.quantity.text)
  if not quantity then
    elements.preview.caption = { "gb-gui.enter-quantity" }
    return
  end
  -- The tier this quantity would ship by: a purchase from the window ships by it, or is refused
  -- (tier-changed) if that changed since it was shown.
  local planned = freight.tier_for(data.hub, item, quantity, kind)
  data.tier = planned and planned.name
  local cost, fee = freight.preview(player.force_index, item, quantity, kind, data.hub)
  -- What selling from the inventory would bring: the market price of the units, scaled by the
  -- freshness of the stacks the sale would take (ADR-0013). Fluids are sold by export manifolds.
  local revenue = kind == "item" and market.preview(player.force_index, kind, item, "sell", quantity)
  local inventory = player.get_main_inventory()
  if revenue and inventory then revenue = revenue * cargo.sale_freshness(inventory, item, quantity, "normal") end
  elements.preview.caption = { "gb-gui.preview", quantity,
    cost and { "gb-gui.cost-with-freight", catalog.format_credits(cost + fee), catalog.format_credits(fee),
      { "gb-gui.tier-" .. (planned or freight.tier(data.hub)).name } }
      or { "gb-gui.unavailable" },
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

-- Fixed column widths, so the price columns stay aligned whatever the length of the item names; a
-- name too long for its column is clipped and shown whole in its tooltip.
local COLUMNS = {
  { key = "icon" },
  { key = "name", header = "item", width = 260 },
  { key = "buy", header = "buy", width = 70, align = "middle-right" },
  { key = "sell", header = "sell", width = 70, align = "middle-right" },
  { key = "trend", header = "trend", width = 60, align = "middle-center" },
}

local function add_cell(list, column, element)
  local cell = list.add(element)
  if column.width then cell.style.width = column.width end
  return cell
end

local function add_list(body, elements)
  local list = body.add({ type = "table", column_count = #COLUMNS })
  for i, column in ipairs(COLUMNS) do
    if column.align then list.style.column_alignments[i] = column.align end
    local header = add_cell(list, column, { type = "label", style = "bold_label",
      caption = column.header and { "gb-gui.column-" .. column.header } or "" })
    if column.key == "trend" then elements.trend_header = header end
  end
  elements.rows = {}
  for i = 1, catalog.PAGE_SIZE do
    local row = {}
    for _, column in ipairs(COLUMNS) do
      local element = column.key == "icon" and { type = "sprite-button", style = "slot_button" } or { type = "label" }
      row[column.key] = add_cell(list, column, element)
    end
    elements.rows[i] = row
  end
end

local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  add_title_bar(window)
  local body = window.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local status = body.add({ type = "flow", direction = "horizontal" })
  local elements = { window = window }
  elements.balance = status.add({ type = "label", style = "bold_label" })
  elements.overdraft = status.add({ type = "label", tooltip = { "gb-gui.overdraft-terms",
    string.format("%.4g", account.INTEREST_RATE * 100), account.INTEREST_TICKS / 3600 } })
  elements.reputation = status.add({ type = "label" })
  elements.power = status.add({ type = "label" })
  elements.freight = status.add({ type = "label" })
  status.add({ type = "button", caption = { "gb-contracts.open" }, tags = { gb_action = "contracts" } })
  elements.planets = status.add({ type = "button", caption = { "gb-planets.open" }, tags = { gb_action = "planets" } })

  local controls = body.add({ type = "flow", direction = "horizontal" })
  controls.add({ type = "label", caption = { "gb-gui.search" } })
  elements.search = controls.add({ type = "textfield", tags = { gb_action = "search" } })
  controls.add({ type = "button", caption = "<", tags = { gb_action = "previous-page" } })
  elements.page = controls.add({ type = "label" })
  controls.add({ type = "button", caption = ">", tags = { gb_action = "next-page" } })

  add_list(body, elements)

  local detail = body.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.detail = detail
  local heading = detail.add({ type = "flow", direction = "horizontal" })
  elements.detail_icon = heading.add({ type = "sprite" })
  elements.detail_name = heading.add({ type = "label", style = "bold_label" })
  local actions = detail.add({ type = "flow", direction = "horizontal" })
  actions.add({ type = "label", caption = { "gb-gui.quantity" } })
  elements.quantity = actions.add({ type = "textfield", text = "1", numeric = true,
    tags = { gb_action = "quantity" } })
  actions.add({ type = "button", caption = { "gb-gui.buy" }, style = "green_button", tags = { gb_action = "buy" } })
  actions.add({ type = "button", caption = { "gb-gui.sell" }, style = "red_button", tags = { gb_action = "sell" } })
  elements.history = detail.add({ type = "label" })
  elements.preview = detail.add({ type = "label" })

  window.force_auto_center()
  return elements
end

--- Opens the market window of a hub for a player: the hub must belong to the player's force and be
--- within reach.
function market_gui.open(player, hub)
  if hub.force ~= player.force or not player.can_reach_entity(hub) then return end
  market_gui.close(player.index)
  local data = { hub = hub.unit_number, filter = "", page = 1, matches = catalog.search(tradeable_keys(), "") }
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

-- The hub to trade through for an action, or nil after telling the player why not.
local function trading_hub(player, data)
  local hub = usable_hub(player, data)
  if not hub then
    notify(player, { "gb-gui.hub-unavailable" })
    market_gui.close(player.index)
    return nil
  end
  if hub.energy <= 0 then
    notify(player, { "gb-gui.hub-unpowered" })
    return nil
  end
  return hub
end

local actions = {}

function actions.close(player)
  market_gui.close(player.index)
end

function actions.contracts(player, data)
  contracts_gui.open(player, data.hub)
end

function actions.planets(player, data)
  if not concessions.researched(player.force, concessions.CONCESSION_TECHNOLOGY) then return end
  planets_gui.open(player, data.hub)
end

function actions.select(player, data, tags)
  data.selected = tags.key
  refresh_list(player, data)
  refresh_detail(player, data)
end

function actions.search(player, data)
  data.filter = data.elements.search.text
  data.matches = catalog.search(tradeable_keys(), data.filter)
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
  local key, quantity = data.selected, catalog.parse_quantity(data.elements.quantity.text)
  if not (key and quantity) then return end
  local hub = trading_hub(player, data)
  if not hub then return end
  local kind, name = split(key)
  local ok, cost, fee, arrival = freight.order(player.force_index, hub.unit_number, name, quantity, nil, nil, kind,
    data.tier)
  if not ok then return notify(player, { "gb-gui.refused-" .. cost }) end
  notify(player, { "gb-gui.ordered", quantity, label(key), catalog.format_credits(cost),
    catalog.format_credits(fee), math.ceil((arrival - game.tick) / 60) })
  refresh(player, data)
end

function actions.sell(player, data)
  local key, quantity = data.selected, catalog.parse_quantity(data.elements.quantity.text)
  local inventory = player.get_main_inventory()
  if not (key and quantity and inventory) then return end
  local kind, name = split(key)
  if kind ~= "item" then return notify(player, { "gb-gui.sell-fluid" }) end
  if not trading_hub(player, data) then return end
  local sold, revenue = cargo.sell_stacks(inventory, player.force_index, cargo.WINDOW_MIN_PRICE_RATIO, name, quantity,
    "normal")
  if sold == 0 then return notify(player, { "gb-gui.sold-nothing" }) end
  notify(player, { "gb-gui.sold", sold, label(key), catalog.format_credits(revenue) })
  refresh(player, data)
end

-- Runs the action named by one of this mod's elements, if it belongs to the player's open window.
local function dispatch(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  local action = actions[element.tags.gb_action]
  local data = storage.players[event.player_index]
  if not (action and data and window_of(event.player_index)) then return end
  action(game.get_player(event.player_index), data, element.tags)
end

market_gui.on_gui_click = dispatch

function market_gui.on_gui_text_changed(event)
  local element = event.element
  local action = element.valid and element.get_mod() == script.mod_name and element.tags.gb_action
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

--- on_nth_tick(SLOT_TICKS): refreshes the open windows of connected players whose slot comes up;
--- a window whose hub is gone, foreign or out of reach is closed.
function market_gui.on_refresh_tick(event)
  local slot = (event.tick / market_gui.SLOT_TICKS) % market_gui.SLOTS
  local closing = {}
  for player_index, data in pairs(storage.players) do
    local player = game.get_player(player_index)
    if player_index % market_gui.SLOTS == slot and player and player.connected and window_of(player_index) then
      if usable_hub(player, data) then
        refresh(player, data)
      else
        closing[#closing + 1] = player_index
      end
    end
  end
  for _, player_index in ipairs(closing) do market_gui.close(player_index) end
end

--- Closes every window trading through a hub that no longer exists.
function market_gui.on_hub_removed(hub_unit_number)
  local closing = {}
  for player_index, data in pairs(storage.players) do
    if data.hub == hub_unit_number then closing[#closing + 1] = player_index end
  end
  for _, player_index in ipairs(closing) do market_gui.close(player_index) end
end

--- on_player_left_game, on_player_changed_force and on_player_removed: the window no longer applies.
function market_gui.on_player_event(event)
  market_gui.close(event.player_index)
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
