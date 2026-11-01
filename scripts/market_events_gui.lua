-- The Events tab of the Galactic Bazaar window (#120, scripts/bazaar_gui.lua): the market events of
-- the galaxy (scripts/market_events.lua) — announced, active, and ended ones whose shift is still
-- fading — with their goods, where they stand (how long they may last, never their exact end), the
-- range of their possible effect (never their own path) and their effect now, and a line stating the
-- settings in force. Every cell has a tooltip with its rule. Rows are built once and updated in place:
-- a row's kind (its tooltip saying what to do about the event), goods and range are written when the
-- event or the phase it shows changes, its status and current effect on every refresh. Read only: it
-- works anywhere.
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local core = require("scripts.core.market_events")
local market_events = require("scripts.market_events")

local market_events_gui = {}

-- Rows shown; events beyond them are counted on the line below the table.
market_events_gui.MAX_ROWS = 8
local COLUMNS = { "kind", "goods", "status", "range", "now" }

local PARAMS = market_events.PARAMS

local function percent(share)
  return string.format("%.4g", share * 100)
end

-- The tooltips stating each column's rule, with the figures of market_events.DEFAULTS.
local function column_tooltips()
  return {
    kind = { "gb-events.column-kind-tooltip", PARAMS.crisis_min_keys, PARAMS.crisis_max_keys },
    goods = { "gb-events.column-goods-tooltip" },
    status = { "gb-events.column-status-tooltip", catalog.format_duration(PARAMS.warning_ticks),
      percent(PARAMS.cancel_chance), catalog.format_duration(PARAMS.min_duration_ticks),
      catalog.format_duration(PARAMS.max_duration_ticks), catalog.format_duration(PARAMS.pass_ticks),
      string.format("%.2g", PARAMS.end_chance * 100) },
    range = { "gb-events.column-range-tooltip" },
    now = { "gb-events.column-now-tooltip", catalog.format_duration(market_events.HALF_LIFE_TICKS) },
  }
end

local function summary_tooltip()
  return { "gb-events.summary-tooltip", catalog.format_duration(PARAMS.interval_ticks), percent(PARAMS.announce_chance),
    catalog.format_duration(PARAMS.warning_ticks), percent(PARAMS.cancel_chance), PARAMS.max_open }
end

local function build(_, container, view)
  local elements = { rows = {} }
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.summary = body.add({ type = "label", tooltip = summary_tooltip() })
  local list = body.add({ type = "table", column_count = #COLUMNS })
  local tooltips = column_tooltips()
  for _, column in ipairs(COLUMNS) do
    list.add({ type = "label", style = "bold_label", caption = { "gb-events.column-" .. column },
      tooltip = tooltips[column] })
  end
  for i = 1, market_events_gui.MAX_ROWS do
    local row = {}
    for _, column in ipairs(COLUMNS) do
      row[column] = list.add({ type = "label", tooltip = tooltips[column] })
    end
    elements.rows[i] = row
  end
  elements.empty = body.add({ type = "label", caption = { "gb-events.none" } })
  elements.more = body.add({ type = "label" })
  view.elements, view.shown = elements, {}
end

-- Events in display order: those announced or active first, soonest start first, then the others,
-- latest end first.
local function ordered(events, tick)
  local open, past = {}, {}
  for _, event in ipairs(events) do
    local phase = core.phase(event, tick)
    if phase == "announced" or phase == "active" then open[#open + 1] = event else past[#past + 1] = event end
  end
  table.sort(open, function(a, b)
    return a.start_tick < b.start_tick or (a.start_tick == b.start_tick and a.id < b.id)
  end)
  table.sort(past, function(a, b)
    return a.end_tick > b.end_tick or (a.end_tick == b.end_tick and a.id > b.id)
  end)
  for _, event in ipairs(past) do open[#open + 1] = event end
  return open
end

-- The range of the event's possible effect; nothing for a called-off one.
local function range_caption(event, phase)
  if phase == "cancelled" then return { "gb-events.range-cancelled" } end
  return market_events.range_caption(event)
end

local function set_visible(row, visible)
  for _, column in ipairs(COLUMNS) do row[column].visible = visible end
end

local function refresh(_, view)
  local tick = game.tick
  local elements, shown = view.elements, view.shown
  local settings = market_events.settings()
  elements.summary.caption = settings.frequency > 0
    and { "gb-events.summary", string.format("%.3g", settings.frequency),
      catalog.format_duration(PARAMS.interval_ticks / settings.frequency), string.format("%.3g", settings.magnitude) }
    or { "gb-events.summary-off" }
  local events = ordered(market_events.list(), tick)
  for i, row in ipairs(elements.rows) do
    local event = events[i]
    set_visible(row, event ~= nil)
    if event then
      local phase = core.phase(event, tick)
      local mark = event.id .. "/" .. phase
      if shown[i] ~= mark then
        shown[i] = mark
        row.kind.caption = { "gb-events.kind-" .. event.kind }
        -- What to do about it first, then the rule of the column.
        row.kind.tooltip = { "", market_events.advice(event), "\n\n", column_tooltips().kind }
        row.goods.caption = market_events.goods_caption(event)
        row.range.caption = range_caption(event, phase)
      end
      row.status.caption = market_events.phase_caption(event, tick)
      row.now.caption = { "gb-events.now-value",
        market_events.percent(math.exp(-market_events.event_depths(event, tick))) }
    else
      shown[i] = nil
    end
  end
  elements.empty.visible = #events == 0
  local hidden = #events - #elements.rows
  elements.more.visible = hidden > 0
  if hidden > 0 then elements.more.caption = { "gb-events.more", hidden } end
end

bazaar_gui.register_tab({ name = "events", order = 22, build = build, refresh = refresh })

return market_events_gui
