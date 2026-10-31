-- The Statement tab of the Galactic Bazaar window (#108, scripts/bazaar_gui.lua): the force's account
-- journal, newest first, a page at a time, filtered by category, with the totals of each category
-- over a chosen period. What each row and total means comes from scripts/core/statement.lua; every
-- kind of transaction has a label and a tooltip explaining the mechanism behind it. Rows are built
-- once and updated in place (an unused row is emptied, never hidden). Read only: it works anywhere.
local account = require("scripts.core.account")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local freight = require("scripts.core.freight")
local insolvency = require("scripts.core.insolvency")
local quality = require("scripts.core.quality")
local statement = require("scripts.core.statement")

local statement_gui = {}

-- Columns of the journal, and of the totals; each heading is the locale key `gb-statement.column-<name>`.
local ROW_COLUMNS = { "time", "kind", "subject", "quantity", "amount", "balance" }
local TOTAL_COLUMNS = { "category", "income", "spending", "net", "count" }
-- Contract kinds with a name (`gb-notify.kind-<kind>`).
local CONTRACT_KINDS = { incoming = true, rental = true, concession = true, outsourcing = true, loan = true }

local function percent(share)
  return string.format("%.4g", share * 100)
end

-- Parameters of the tooltips of labels whose mechanism has figures.
local function label_parameters(label)
  if label == "freight" then
    return percent(freight.TIERS.capsule.fee_rate), percent(freight.TIERS.shuttle.fee_rate),
      percent(freight.TIERS.teleporter.fee_rate)
  elseif label == "overdraft-interest" then
    return percent(account.INTEREST_RATE), account.INTEREST_TICKS / 3600
  elseif label == "bankruptcy-restructured" then
    return percent(insolvency.RESTRUCTURING_SURCHARGE)
  end
end

local function label_tooltip(label, entry)
  if label == "other" then return { "gb-statement.kind-other-tooltip", tostring(entry.kind) } end
  return { "gb-statement.kind-" .. label .. "-tooltip", label_parameters(label) }
end

-- What an entry was about, as a caption with an icon: goods whose prototype still exists, energy, or
-- a contract; the raw key otherwise, nothing for the account itself.
local function subject_caption(entry)
  local subject = statement.subject(entry)
  if not subject then return "" end
  if subject.type == "contract" then
    return CONTRACT_KINDS[subject.contract_kind]
      and { "gb-statement.contract", subject.id, { "gb-notify.kind-" .. subject.contract_kind } }
      or { "gb-statement.contract-unknown", subject.id }
  elseif subject.type == "energy" then
    return { "gb-statement.electricity" }
  end
  local prototype = (subject.type == "item" and prototypes.item or prototypes.fluid)[subject.name]
  if not prototype then return entry.key end
  local tag = subject.quality ~= quality.NORMAL and prototypes.quality[subject.quality]
    and string.format("[%s=%s,quality=%s] ", subject.type, subject.name, subject.quality)
    or string.format("[%s=%s] ", subject.type, subject.name)
  return { "", tag, prototype.localised_name }
end

local function add_headings(table_element, columns)
  for _, column in ipairs(columns) do
    table_element.add({ type = "label", style = "caption_label", caption = { "gb-statement.column-" .. column },
      tooltip = { "gb-statement.column-" .. column .. "-tooltip" } })
  end
end

local function add_cells(table_element, columns)
  local cells = {}
  for _, column in ipairs(columns) do cells[column] = table_element.add({ type = "label" }) end
  return cells
end

local function localised_items(prefix, names)
  local items = {}
  for i, name in ipairs(names) do items[i] = { prefix .. name } end
  return items
end

local function filter_names()
  local names = { statement.ALL }
  for _, category in ipairs(statement.CATEGORIES) do names[#names + 1] = category end
  return names
end

local function period_names()
  local names = {}
  for i, period in ipairs(statement.PERIODS) do names[i] = period.name end
  return names
end

local function index_of(list, value)
  for i, item in ipairs(list) do
    if item == value then return i end
  end
  return 1
end

local function build_controls(container, view, elements)
  local controls = container.add({ type = "flow", direction = "horizontal" })
  controls.style.vertical_align = "center"
  controls.add({ type = "label", caption = { "gb-statement.filter" }, tooltip = { "gb-statement.filter-tooltip" } })
  elements.filter = controls.add({ type = "drop-down",
    items = localised_items("gb-statement.category-", filter_names()),
    selected_index = index_of(filter_names(), view.filter), tags = { gb_action = "statement-filter" } })
  controls.add({ type = "label", caption = { "gb-statement.period" }, tooltip = { "gb-statement.period-tooltip" } })
  elements.period = controls.add({ type = "drop-down", items = localised_items("gb-statement.period-", period_names()),
    selected_index = index_of(period_names(), view.period), tags = { gb_action = "statement-period" } })
  elements.since = container.add({ type = "label" })
end

local function build_totals(container, elements)
  local frame = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local totals = frame.add({ type = "table", column_count = #TOTAL_COLUMNS })
  add_headings(totals, TOTAL_COLUMNS)
  elements.totals = {}
  local rows = {}
  for _, category in ipairs(statement.CATEGORIES) do rows[#rows + 1] = category end
  rows[#rows + 1] = statement.ALL
  for _, category in ipairs(rows) do
    local cells = add_cells(totals, TOTAL_COLUMNS)
    cells.category.caption = category == statement.ALL and { "gb-statement.total" }
      or { "gb-statement.category-" .. category }
    cells.category.tooltip = { "gb-statement.category-" .. category .. "-tooltip" }
    elements.totals[category] = cells
  end
end

local function build_journal(container, elements)
  local frame = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.covers = frame.add({ type = "label" })
  local journal = frame.add({ type = "table", column_count = #ROW_COLUMNS })
  add_headings(journal, ROW_COLUMNS)
  elements.rows = {}
  for i = 1, statement.PAGE_SIZE do
    local cells = add_cells(journal, ROW_COLUMNS)
    cells.subject.style.width = 220
    cells.kind.style.width = 160
    elements.rows[i] = cells
  end
  local pager = container.add({ type = "flow", direction = "horizontal" })
  pager.style.vertical_align = "center"
  pager.add({ type = "button", caption = "<", tags = { gb_action = "statement-previous" } })
  elements.page = pager.add({ type = "label" })
  pager.add({ type = "button", caption = ">", tags = { gb_action = "statement-next" } })
end

local function build(_, container, view)
  view.filter, view.period, view.page = statement.ALL, "all", 1
  -- What each element shows, as plain values: an element is written only when its value changes.
  view.shown = { rows = {}, totals = {}, since_tick = false }
  local elements = {}
  build_controls(container, view, elements)
  build_totals(container, elements)
  build_journal(container, elements)
  view.elements = elements
end

-- What a row shows of `entry` (nil for an empty row), as plain strings, one per group of element
-- properties written together.
local function row_values(entry)
  if not entry then
    return { time = "", merged = "", kind = "", subject = "", quantity = "", amount = "", balance = "" }
  end
  local label = statement.label(entry)
  local amount = entry.amount or 0
  return {
    time = statement.format_time(entry.tick or 0),
    merged = entry.first_tick and entry.first_tick ~= entry.tick and (entry.first_tick .. "/" .. entry.tick) or "",
    kind = label == "other" and "other/" .. tostring(entry.kind) or label,
    subject = tostring(entry.key) .. "/" .. tostring(entry.contract_kind),
    quantity = statement.format_quantity(entry.quantity),
    amount = statement.format_signed(amount),
    balance = entry.balance and catalog.format_credits(entry.balance) or "",
  }
end

-- The fields of a journal entry a row shows.
local ENTRY_FIELDS = { "tick", "first_tick", "kind", "key", "contract_kind", "quantity", "amount", "balance" }

-- Whether the row last showed this very entry, unchanged (`shown.entry` holds a copy of its fields).
local function same_entry(shown, entry)
  local copy = shown.entry
  if not (copy and entry) then return copy == nil and entry == nil and shown.time ~= nil end
  for _, field in ipairs(ENTRY_FIELDS) do
    if copy[field] ~= entry[field] then return false end
  end
  return true
end

-- Writes the cells of a row whose values differ from those it shows (`shown`, updated): rows shift
-- by one with each new entry, and most cells of the next row hold the same text. A row still showing
-- the same entry is left alone without formatting anything.
local function refresh_row(cells, shown, entry)
  if same_entry(shown, entry) then return end
  local copy
  if entry then
    copy = {}
    for _, field in ipairs(ENTRY_FIELDS) do copy[field] = entry[field] end
  end
  shown.entry = copy
  local values = row_values(entry)
  if values.time ~= shown.time then cells.time.caption = values.time end
  if values.merged ~= shown.merged then
    cells.time.tooltip = values.merged ~= "" and { "gb-statement.merged", statement.format_time(entry.first_tick),
      statement.format_time(entry.tick or 0) } or ""
  end
  if values.kind ~= shown.kind then
    local label = entry and statement.label(entry)
    cells.kind.caption = label and { "gb-statement.kind-" .. label } or ""
    cells.kind.tooltip = label and label_tooltip(label, entry) or ""
  end
  if values.subject ~= shown.subject then cells.subject.caption = entry and subject_caption(entry) or "" end
  if values.quantity ~= shown.quantity then cells.quantity.caption = values.quantity end
  if values.amount ~= shown.amount then cells.amount.caption = values.amount end
  if values.balance ~= shown.balance then cells.balance.caption = values.balance end
  for field, value in pairs(values) do shown[field] = value end
end

-- How each figure of a total is written.
local TOTAL_FORMATS = {
  income = catalog.format_credits, spending = catalog.format_credits, net = statement.format_signed,
  count = tostring,
}

-- Writes the figures of a total that changed since they were shown (`shown`, updated).
local function refresh_total(cells, shown, total)
  for field, format in pairs(TOTAL_FORMATS) do
    if shown[field] ~= total[field] then
      cells[field].caption = format(total[field])
      shown[field] = total[field]
    end
  end
end

local function refresh_totals(view, totals)
  local elements, shown = view.elements, view.shown.totals
  for _, category in ipairs(statement.CATEGORIES) do
    shown[category] = shown[category] or {}
    refresh_total(elements.totals[category], shown[category], totals.categories[category])
  end
  shown[statement.ALL] = shown[statement.ALL] or {}
  refresh_total(elements.totals[statement.ALL], shown[statement.ALL], totals.all)
end

-- Where the totals start, and what the journal holds, written when they change.
local function refresh_coverage(view, journal, since_tick)
  local elements, shown = view.elements, view.shown
  if shown.since_tick ~= since_tick then
    elements.since.caption = since_tick and { "gb-statement.since", statement.format_time(since_tick) }
      or { "gb-statement.since-none" }
    shown.since_tick = since_tick
  end
  local oldest = journal[1]
  local from_tick = oldest and (oldest.first_tick or oldest.tick)
  if shown.count ~= #journal or shown.from_tick ~= from_tick then
    elements.covers.caption = from_tick
      and { "gb-statement.covers", #journal, statement.format_time(from_tick), account.JOURNAL_SIZE }
      or { "gb-statement.covers-empty" }
    shown.count, shown.from_tick = #journal, from_tick
  end
end

local function refresh(player, view)
  local state = storage.forces[player.force_index]
  local journal = state and state.journal or {}
  local elements, shown = view.elements, view.shown
  local totals = statement.totals(state and state.ledger, view.period, game.tick)
  refresh_totals(view, totals)
  refresh_coverage(view, journal, totals.since_tick)
  local page = statement.page(journal, view.filter, view.page)
  view.page = page.page
  if shown.page ~= page.page or shown.pages ~= page.pages then
    elements.page.caption = { "gb-gui.page", page.page, page.pages }
    shown.page, shown.pages = page.page, page.pages
  end
  for i, cells in ipairs(elements.rows) do
    shown.rows[i] = shown.rows[i] or {}
    refresh_row(cells, shown.rows[i], page.entries[i])
  end
end

-- A drop-down's new choice, only on a selection (a click on it raises on_gui_click too).
local function chosen(element, event, names)
  if event.name ~= defines.events.on_gui_selection_state_changed then return nil end
  return names[element.selected_index]
end

local actions = {}

actions["statement-filter"] = function(player, view, _, _, element, event)
  local filter = chosen(element, event, filter_names())
  if not filter then return end
  view.filter, view.page = filter, 1
  refresh(player, view)
end

actions["statement-period"] = function(player, view, _, _, element, event)
  local period = chosen(element, event, period_names())
  if not period then return end
  view.period = period
  refresh(player, view)
end

actions["statement-previous"] = function(player, view)
  view.page = view.page - 1
  refresh(player, view)
end

actions["statement-next"] = function(player, view)
  view.page = view.page + 1
  refresh(player, view)
end

bazaar_gui.register_tab({ name = "statement", order = 50, build = build, refresh = refresh, actions = actions })

return statement_gui
