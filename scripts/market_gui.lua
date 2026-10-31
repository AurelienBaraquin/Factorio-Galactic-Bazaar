-- The Market tab of the Galactic Bazaar window (scripts/bazaar_gui.lua): balance and overdraft left,
-- the force's insolvency or credit ban with the time left (ADR-0022), the window's hub and its
-- delivery tier, a searchable and paged list of tradeable items with their prices, and a panel to buy
-- into the hub's import chests or sell from the player's inventory, with the selected item's detail
-- (scripts/item_detail_gui.lua). Prices can be read anywhere;
-- buying and selling need the window's hub within reach. Interface state is the tab's view in
-- storage.bazaar_gui; economy state stays per force. Every action is re-validated, since GUI events
-- are player input. Every part has a tooltip with its rule: set when the tab is built, or written when
-- what it shows changed for those that follow the force's state (`view.tooltips`).
local bazaar_gui = require("scripts.bazaar_gui")
local cargo = require("scripts.cargo")
local account = require("scripts.core.account")
local catalog = require("scripts.core.catalog")
local freight = require("scripts.freight")
local insolvency = require("scripts.core.insolvency")
local item_detail_gui = require("scripts.item_detail_gui")
local logistics_gui = require("scripts.logistics_gui")
local market = require("scripts.market")
local market_model = require("scripts.core.market")
local npc_market = require("scripts.core.npc_market")
local reputation = require("scripts.core.reputation")
local telecom = require("scripts.telecom")
local telecom_core = require("scripts.core.telecom")

local market_gui = {}

local TREND_CAPTIONS = { up = "▲", down = "▼", flat = "–" }
-- Most height of the detail panel, in pixels: it scrolls beyond.
local DETAIL_HEIGHT = 640

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

local function percent(share)
  return string.format("%.4g", share * 100)
end

--- What a reputation score changes, as a tooltip: freight fees and contract sizes against the usual.
function market_gui.reputation_tooltip(score)
  return { "gb-gui.reputation-effects", percent(reputation.fee_factor(score)),
    percent(reputation.contract_scale(score)) }
end

local function refresh_status(player, view, window)
  local elements = view.elements
  local state = storage.forces[player.force_index]
  elements.balance.caption = { "gb-gui.balance", catalog.format_credits(state.balance) }
  elements.overdraft.caption = { "gb-gui.overdraft", catalog.format_credits(account.overdraft_left(state)),
    catalog.format_credits(account.overdraft_limit(state)) }
  local grace, ban = insolvency.grace_left(state, game.tick), insolvency.ban_left(state, game.tick)
  elements.solvency.visible = grace ~= nil or ban ~= nil
  if grace then
    elements.solvency.caption = { "gb-gui.insolvent", catalog.format_duration(grace) }
    elements.solvency.tooltip = { "gb-gui.insolvent-terms",
      catalog.format_credits(insolvency.recovery_balance(state)) }
  elseif ban then
    local debt = state.bankruptcy_debt or 0
    if ban <= 0 then
      elements.solvency.caption = { "gb-gui.credit-ban-debt", catalog.format_credits(debt) }
    elseif debt > 0 then
      elements.solvency.caption = { "gb-gui.credit-ban", catalog.format_duration(ban), catalog.format_credits(debt) }
    else
      elements.solvency.caption = { "gb-gui.credit-ban-time", catalog.format_duration(ban) }
    end
    elements.solvency.tooltip = { "gb-gui.credit-ban-terms" }
  end
  elements.reputation.caption = { "gb-gui.reputation", state.reputation }
  -- Tooltips that follow the force's state are written only when what they show changed.
  local tooltips = view.tooltips
  if tooltips.reputation ~= state.reputation then
    tooltips.reputation = state.reputation
    elements.reputation.tooltip = market_gui.reputation_tooltip(state.reputation)
  end
  local hub = bazaar_gui.bound_hub(window)
  elements.power.caption = not hub and bazaar_gui.no_hub_message(player)
    or hub.energy > 0 and { "gb-gui.hub-powered" } or { "gb-gui.hub-unpowered" }
  elements.freight.visible = hub ~= nil
  if hub then
    local tier = freight.tier(window.hub)
    elements.freight.caption = { "gb-gui.delivery", { "gb-gui.tier-" .. tier.name },
      freight.queued(window.hub, tier.name), tier.max_capsules }
    local shown = tier.name .. " " .. state.reputation
    if tooltips.freight ~= shown then
      tooltips.freight = shown
      elements.freight.tooltip = logistics_gui.tier_tooltip(tier, player.force_index)
    end
  end
end

-- Updates the fixed rows in place: elements are never destroyed by a refresh, so a click sent just
-- before it still finds its button (multiplayer latency).
local function refresh_list(player, view)
  local elements = view.elements
  -- Below telecommunications 2 the trend column stays in place, empty: hiding its cells would shift
  -- every later cell of the table into the wrong column.
  local history = telecom.shows_history(player.force)
  local period = telecom.period(player.force)
  elements.trend_header.caption = history and { "gb-gui.column-trend" } or ""
  local shown = catalog.page(view.matches, view.page)
  view.page = shown.page
  elements.page.caption = { "gb-gui.page", shown.page, shown.pages }
  for i, row in ipairs(elements.rows) do
    local name = shown.names[i]
    -- The list is taken when the tab is first shown: an item whose value another mod removes since
    -- then is hidden, and one that gains a value appears on the next opening.
    local quote
    if name then
      local kind, item = split(name)
      quote = telecom.quote(player.force_index, kind, item, period)
    end
    for _, cell in pairs(row) do cell.visible = quote ~= nil end
    if quote then
      row.icon.sprite = name
      row.icon.tags = { gb_action = "select", key = name }
      row.icon.toggled = name == view.selected
      row.name.caption = label(name)
      row.name.tooltip = label(name)
      row.buy.caption = catalog.format_credits(quote.buy)
      row.sell.caption = catalog.format_credits(quote.sell)
      row.trend.caption = history and TREND_CAPTIONS[catalog.trend(quote.history)] or ""
    end
  end
end

local function refresh_detail(player, view, window)
  local elements = view.elements
  local name = view.selected
  elements.detail.visible = name ~= nil
  if not name then return end
  local kind, item = split(name)
  elements.detail_icon.sprite = name
  elements.detail_name.caption = label(name)
  local quantity = catalog.parse_quantity(elements.quantity.text)
  item_detail_gui.refresh(player, elements, kind, item, quantity)
  if not quantity then
    elements.preview.caption = { "gb-gui.enter-quantity" }
    return
  end
  -- The tier this quantity would ship by from the window's hub: a purchase ships by it, or is refused
  -- (tier-changed) if that changed since it was shown. Without a hub, the orbital capsule's fee is
  -- shown; when the hub has no tier that can take the order (a full queue...), the reason is.
  local planned, no_tier = freight.tier_for(window.hub, item, quantity, kind)
  view.tier, view.tier_hub = planned and planned.name, window.hub
  local cost, fee = freight.preview(player.force_index, item, quantity, kind, window.hub)
  if window.hub and not planned then cost = nil end
  -- What selling from the inventory would bring: the market price of the units, scaled by the
  -- freshness of the stacks the sale would take (ADR-0013). Fluids are sold by export manifolds.
  local revenue = kind == "item" and market.preview(player.force_index, kind, item, "sell", quantity)
  local inventory = player.get_main_inventory()
  if revenue and inventory then revenue = revenue * cargo.sale_freshness(inventory, item, quantity, "normal") end
  elements.preview.caption = { "gb-gui.preview", quantity,
    cost and { "gb-gui.cost-with-freight", catalog.format_credits(cost + fee), catalog.format_credits(fee),
      { "gb-gui.tier-" .. (planned or freight.tier(window.hub)).name } }
      or no_tier and { "gb-gui.refused-" .. no_tier }
      or { "gb-gui.unavailable" },
    revenue and catalog.format_credits(revenue) or { "gb-gui.unavailable" } }
end

local function refresh(player, view, window)
  refresh_status(player, view, window)
  refresh_list(player, view)
  refresh_detail(player, view, window)
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

-- The rule behind each column, as the tooltip of its header and of its cells (the name cells keep
-- the item's whole name); set once, when the tab is built.
local function column_tooltips()
  local periods = telecom_core.PERIOD_TICKS
  local half_spread = percent(market_model.DEFAULTS.spread / 2)
  local item = { "gb-gui.column-item-tooltip" }
  return {
    icon = item,
    name = item,
    buy = { "gb-gui.column-buy-tooltip", half_spread, periods[0] / 60, periods[1] / 60, periods[2] / 60 },
    sell = { "gb-gui.column-sell-tooltip", half_spread, periods[0] / 60, periods[1] / 60, periods[2] / 60 },
    trend = { "gb-gui.column-trend-tooltip", npc_market.DEFAULTS.history_size,
      npc_market.DEFAULTS.step_ticks / 3600, percent(catalog.FLAT_TREND) },
  }
end

local function add_list(body, elements)
  local list = body.add({ type = "table", column_count = #COLUMNS })
  local tooltips = column_tooltips()
  for i, column in ipairs(COLUMNS) do
    if column.align then list.style.column_alignments[i] = column.align end
    local header = add_cell(list, column, { type = "label", style = "bold_label",
      caption = column.header and { "gb-gui.column-" .. column.header } or "", tooltip = tooltips[column.key] })
    if column.key == "trend" then elements.trend_header = header end
  end
  elements.rows = {}
  for i = 1, catalog.PAGE_SIZE do
    local row = {}
    for _, column in ipairs(COLUMNS) do
      local element = column.key == "icon" and { type = "sprite-button", style = "slot_button" } or { type = "label" }
      if column.key ~= "name" then element.tooltip = tooltips[column.key] end
      row[column.key] = add_cell(list, column, element)
    end
    elements.rows[i] = row
  end
end

local function build(_, container, view)
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local status = body.add({ type = "flow", direction = "horizontal" })
  local elements = {}
  elements.balance = status.add({ type = "label", style = "bold_label", tooltip = { "gb-overview.balance-tooltip" } })
  elements.overdraft = status.add({ type = "label", tooltip = { "gb-gui.overdraft-terms",
    percent(account.INTEREST_RATE), account.INTEREST_TICKS / 3600 } })
  elements.solvency = status.add({ type = "label", style = "bold_label" })
  elements.solvency.style.font_color = { r = 1, g = 0.4, b = 0.3 }
  elements.reputation = status.add({ type = "label" })
  elements.power = status.add({ type = "label", tooltip = { "gb-gui.hub-tooltip" } })
  elements.freight = status.add({ type = "label" })
  view.tooltips = {}

  local controls = body.add({ type = "flow", direction = "horizontal" })
  controls.add({ type = "label", caption = { "gb-gui.search" } })
  elements.search = controls.add({ type = "textfield", tags = { gb_action = "search" } })
  controls.add({ type = "button", caption = "<", tags = { gb_action = "previous-page" } })
  elements.page = controls.add({ type = "label" })
  controls.add({ type = "button", caption = ">", tags = { gb_action = "next-page" } })

  -- The list, and the selected item's detail beside it.
  local columns = body.add({ type = "flow", direction = "horizontal" })
  add_list(columns, elements)
  local pane = columns.add({ type = "scroll-pane", horizontal_scroll_policy = "never" })
  pane.style.maximal_height = DETAIL_HEIGHT
  elements.detail = pane
  local detail = pane.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local heading = detail.add({ type = "flow", direction = "horizontal" })
  elements.detail_icon = heading.add({ type = "sprite" })
  elements.detail_name = heading.add({ type = "label", style = "bold_label" })
  local actions = detail.add({ type = "flow", direction = "horizontal" })
  local quantity_tooltip = { "gb-gui.quantity-tooltip", catalog.format_units(catalog.MAX_QUANTITY) }
  actions.add({ type = "label", caption = { "gb-gui.quantity" }, tooltip = quantity_tooltip })
  elements.quantity = actions.add({ type = "textfield", text = "1", numeric = true, tooltip = quantity_tooltip,
    tags = { gb_action = "quantity" } })
  actions.add({ type = "button", caption = { "gb-gui.buy" }, style = "green_button", tooltip = { "gb-gui.buy-tooltip" },
    tags = { gb_action = "buy" } })
  actions.add({ type = "button", caption = { "gb-gui.sell" }, style = "red_button",
    tooltip = { "gb-gui.sell-tooltip", percent(cargo.WINDOW_MIN_PRICE_RATIO) }, tags = { gb_action = "sell" } })
  elements.preview = detail.add({ type = "label", tooltip = { "gb-gui.preview-tooltip" } })
  elements.preview.style.single_line = false
  elements.preview.style.maximal_width = item_detail_gui.TEXT_WIDTH
  item_detail_gui.build(detail, elements)

  view.filter, view.page, view.matches = "", 1, catalog.search(tradeable_keys(), "")
  view.elements = elements
end

local function notify(player, message)
  player.print(message)
end

-- The hub to trade through for an action, or nil after telling the player why not.
local function trading_hub(player, window)
  local hub = bazaar_gui.hub(player, window)
  if not hub then
    notify(player, bazaar_gui.no_hub_message(player))
    return nil
  end
  if hub.energy <= 0 then
    notify(player, { "gb-gui.hub-unpowered" })
    return nil
  end
  return hub
end

local actions = {}

function actions.select(player, view, tags, window)
  view.selected = tags.key
  refresh_list(player, view)
  refresh_detail(player, view, window)
end

-- The search and quantity fields act on their text only: a click in a field also raises on_gui_click,
-- which must not reset the page.
local function is_text_event(event)
  return event.name == defines.events.on_gui_text_changed or event.name == defines.events.on_gui_confirmed
end

function actions.search(player, view, _, _, _, event)
  if not is_text_event(event) then return end
  view.filter = view.elements.search.text
  view.matches = catalog.search(tradeable_keys(), view.filter)
  view.page = 1
  refresh_list(player, view)
end

actions["previous-page"] = function(player, view)
  view.page = view.page - 1
  refresh_list(player, view)
end

actions["next-page"] = function(player, view)
  view.page = view.page + 1
  refresh_list(player, view)
end

function actions.quantity(player, view, _, window, _, event)
  if not is_text_event(event) then return end
  refresh_detail(player, view, window)
end

function actions.buy(player, view, _, window)
  local key, quantity = view.selected, catalog.parse_quantity(view.elements.quantity.text)
  if not (key and quantity) then return end
  local hub = trading_hub(player, window)
  if not hub then return end
  -- The preview shown must have been computed for this hub: otherwise the player has not seen the
  -- fee, and the refreshed preview shows it before they try again. A preview without a tier expects
  -- "none": the order then gives the real reason (queue-full...), and a tier that opened up since
  -- does not match, so its fee is shown first.
  if view.tier_hub ~= hub.unit_number then
    notify(player, { "gb-gui.refused-tier-changed" })
    return refresh(player, view, window)
  end
  local kind, name = split(key)
  local ok, cost, fee, arrival = freight.order(player.force_index, hub.unit_number, name, quantity, nil, nil, kind,
    view.tier or "none")
  if not ok then
    notify(player, { "gb-gui.refused-" .. cost })
    return refresh(player, view, window)
  end
  notify(player, { "gb-gui.ordered", quantity, label(key), catalog.format_credits(cost),
    catalog.format_credits(fee), math.ceil((arrival - game.tick) / 60) })
  refresh(player, view, window)
end

function actions.sell(player, view, _, window)
  local key, quantity = view.selected, catalog.parse_quantity(view.elements.quantity.text)
  local inventory = player.get_main_inventory()
  if not (key and quantity and inventory) then return end
  local kind, name = split(key)
  if kind ~= "item" then return notify(player, { "gb-gui.sell-fluid" }) end
  if not trading_hub(player, window) then return end
  local sold, revenue = cargo.sell_stacks(inventory, player.force_index, cargo.WINDOW_MIN_PRICE_RATIO, name, quantity,
    "normal")
  if sold == 0 then return notify(player, { "gb-gui.sold-nothing" }) end
  notify(player, { "gb-gui.sold", sold, label(key), catalog.format_credits(revenue) })
  refresh(player, view, window)
end

bazaar_gui.register_tab({ name = "market", order = 20, build = build, refresh = refresh, actions = actions })

return market_gui
