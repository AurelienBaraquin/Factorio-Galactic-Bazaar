-- The Logistics tab of the Galactic Bazaar window (#109, scripts/bazaar_gui.lua): every hub of the
-- player's force (where it is, its power and status, how full each tier's queue is), and for the hub
-- selected its delivery tier, a camera on it, the shipments queued, in flight and landed there
-- (goods, tier, state, landing time, origin, unit cost) and the modules attached to it with their
-- status (scripts/entity_status.lua). Rows come from scripts/core/logistics.lua; they are built once
-- and updated in place, each cell written only when what it shows changed (`drawn`, `visible`), and
-- every list is paged. Read only: it works anywhere. Interface state is
-- the tab's view in storage.bazaar_gui: `hub` (the hub selected), `focus` (the module the camera
-- shows), `hubs_page`, `shipments_page`, `modules_page`, what each row last showed (`drawn`: {[list] =
-- {[row] = {key, status}}}, `visible`: {[list] = rows shown}) and `modules`, the selected hub's modules as
-- last listed and sorted (redone only when the hub changes or MODULE_RESCAN_TICKS have passed, the
-- cadence at which the status passes find modules anyway).
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local core = require("scripts.core.logistics")
local entity_status = require("scripts.entity_status")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local planets = require("scripts.planets")
local reputation = require("scripts.core.reputation")

local logistics_gui = {}

local DIODE_SPRITES = {
  green = "utility/status_working", yellow = "utility/status_yellow", red = "utility/status_not_working",
}
local NO_DIODE = "utility/status_inactive"
local SHIPMENT_COLUMNS = { "goods", "tier", "state", "lands", "origin", "cost" }
-- Spelled out, so that the locale check (spec/locale_spec.lua) finds every key.
local SHIPMENT_COLUMN_TOOLTIPS = {
  goods = "gb-logistics.column-goods-tooltip", tier = "gb-logistics.column-tier-tooltip",
  state = "gb-logistics.column-state-tooltip", lands = "gb-logistics.column-lands-tooltip",
  origin = "gb-logistics.column-origin-tooltip", cost = "gb-logistics.column-cost-tooltip",
}
local CAMERA_ZOOM = 0.5
logistics_gui.MODULE_RESCAN_TICKS = entity_status.CYCLE_TICKS

local function percent(share)
  return string.format("%.4g", share * 100)
end

local function count_text(count)
  return string.format("%.0f", count)
end

-- The name of a surface: its own, its planet's, or its internal name; read once per refresh and
-- surface (`surfaces`, {[surface_index] = caption}).
local function surface_caption(entity, surfaces)
  local caption = surfaces[entity.surface_index]
  if caption then return caption end
  local surface = entity.surface
  caption = surface.localised_name or surface.planet and surface.planet.prototype.localised_name or surface.name
  surfaces[entity.surface_index] = caption
  return caption
end

local function location(entity, surfaces)
  local position = entity.position
  return { "gb-logistics.location", surface_caption(entity, surfaces), math.floor(position.x),
    math.floor(position.y) }
end

-- The status a building shows (see entity_status.shown) as a label caption: its diode and text, or
-- that it shows the game's own status (false) or was not refreshed yet (nil).
local function shown_caption(descriptor)
  if descriptor then return { "", "[img=" .. DIODE_SPRITES[descriptor.diode] .. "] ", descriptor.label } end
  return { "", "[img=" .. NO_DIODE .. "] ", { descriptor == false and "gb-logistics.status-own"
    or "gb-logistics.status-pending" } }
end

-- The hubs of a force: {{unit_number, surface_index, entity}...}, by surface then unit number.
local function force_hubs(force_index)
  local list = {}
  for unit_number, entry in pairs(storage.hubs) do
    local entity = entry.entity
    if entity.valid and entity.force_index == force_index then
      list[#list + 1] = { unit_number = unit_number, surface_index = entity.surface_index, entity = entity }
    end
  end
  return core.hubs(list)
end

-- "orbital capsule 3 / 20   teleporter 1 / 20", or that nothing is queued.
local function queue_caption(use)
  if #use == 0 then return { "gb-logistics.queue-empty" } end
  local caption = { "" }
  for i, entry in ipairs(use) do
    if i > 1 then caption[#caption + 1] = "   " end
    caption[#caption + 1] = { "gb-logistics.queue-entry", { "gb-gui.tier-" .. entry.name }, entry.queued, entry.max }
  end
  return caption
end

-- What a tier means for a force: its delay, launch interval, capacity, fee (scaled by reputation)
-- and queue bound.
local function tier_tooltip(tier, fee_factor)
  return { "gb-logistics.tier-tooltip", { "gb-gui.tier-" .. tier.name }, tier.delay_ticks / 60,
    tier.launch_interval_ticks / 60, tier.capacity_stacks, percent(tier.fee_rate * fee_factor), tier.max_capsules }
end

local function fee_factor(force_index)
  local state = storage.forces[force_index]
  return reputation.fee_factor(state and state.reputation or 0)
end

--- What a delivery tier means for a force, as a tooltip (the Market tab's delivery line shows it too).
function logistics_gui.tier_tooltip(tier, force_index)
  return tier_tooltip(tier, fee_factor(force_index))
end

-- The kind and counterparty of each contract whose goods the capsules carry, open or settled since
-- (the force's contract history); false when it is no longer known.
local function contract_facts(force_index, capsules)
  local state = storage.forces[force_index]
  local book = state and state.contracts
  local found = {}
  for _, capsule in ipairs(capsules) do
    local id = capsule.contract
    if id and found[id] == nil then
      local contract = book and book.open[id]
      for _, settled in ipairs(not contract and book and book.history or {}) do
        if settled.id == id then contract = settled end
      end
      found[id] = contract and { kind = contract.kind, counterparty = contract.counterparty } or false
    end
  end
  return found
end

-- The tiers whose shipments cannot land at a hub now.
local function held_tiers(hub_unit_number)
  local held = {}
  for name in pairs(freight.TIERS) do
    if not freight.delivers(hub_unit_number, name) then held[name] = true end
  end
  return held
end

-- Shows a page's number and enables its buttons.
local function refresh_pager(pager, shown)
  pager.label.caption = { "gb-gui.page", shown.page, shown.pages }
  pager.previous.enabled = shown.page > 1
  pager.next.enabled = shown.page < shown.pages
end

-- Shows the first `count` rows of list `name` and hides the others (every cell of a hidden row, so
-- no later cell shifts column), writing only the rows whose visibility changes.
local function show_rows(view, name, rows, count)
  local before = view.visible[name] or #rows
  for i = math.min(before, count) + 1, math.max(before, count) do
    for _, cell in pairs(rows[i]) do cell.visible = i <= count end
  end
  view.visible[name] = count
end

-- What row `i` of list `name` last showed: {key (its facts, joined), status (the status descriptor
-- it shows)}; `fresh` when `key` differs, which the caller then writes.
local function drawn_row(view, name, i, key)
  local rows = view.drawn[name]
  local drawn = rows[i]
  if drawn and drawn.key == key then return drawn, false end
  drawn = { key = key }
  rows[i] = drawn
  return drawn, true
end

-- Writes a row's status cell when the building's status changed since it was drawn (descriptors are
-- replaced, never changed, by scripts/entity_status.lua).
local function draw_status(cell, drawn, fresh, unit_number)
  local descriptor = entity_status.shown(unit_number)
  if fresh or drawn.status ~= descriptor then
    cell.caption = shown_caption(descriptor)
    drawn.status = descriptor
  end
end

local function refresh_hubs(view, list, surfaces)
  local elements = view.elements
  local shown = core.page(list, view.hubs_page, core.HUB_ROWS)
  view.hubs_page = shown.page
  refresh_pager(elements.pagers.hubs, shown)
  elements.hub_count.caption = { "gb-logistics.hubs", #list }
  elements.no_hub.visible = #list == 0
  show_rows(view, "hubs", elements.hub_rows, #shown.items)
  for i, hub in ipairs(shown.items) do
    local row, entity = elements.hub_rows[i], hub.entity
    local use = core.queue_use(freight.capsules(hub.unit_number), freight.TIERS)
    local selected, powered = hub.unit_number == view.hub, hubs.has_power(entity)
    local key = hub.unit_number .. (selected and " selected" or "") .. (powered and " powered" or "")
    for _, entry in ipairs(use) do key = key .. " " .. entry.name .. entry.queued end
    local drawn, fresh = drawn_row(view, "hubs", i, key)
    if fresh then
      row.select.caption = location(entity, surfaces)
      row.select.toggled = selected
      row.select.tags = { gb_action = "logistics-select-hub", hub = hub.unit_number }
      row.power.caption = powered and { "gb-logistics.powered" } or { "gb-logistics.unpowered" }
      row.queue.caption = queue_caption(use)
    end
    draw_status(row.status, drawn, fresh, hub.unit_number)
  end
end

-- The locale key of a shipment's state.
local function state_key(row)
  local key = "gb-logistics.state-" .. row.state
  return row.state == "no-room" and key .. "-" .. row.kind or key
end

-- The caption of a shipment's state (a countdown while it waits for its launch).
local function state_caption(row, now)
  if row.state == "queued" then return { state_key(row), catalog.format_duration(row.launch - now) } end
  return { state_key(row) }
end

-- The tooltip of a shipment's state.
local function state_tooltip(row)
  local tier = freight.TIERS[row.tier]
  return { state_key(row) .. "-tooltip", tier and tier.launch_interval_ticks / 60 or 0 }
end

-- The caption and tooltip of a shipment's origin.
local function origin_texts(row)
  if row.origin == "purchase" then
    return { "gb-logistics.origin-purchase" }, { "gb-logistics.origin-purchase-tooltip" }
  end
  if row.origin == "incoming" then
    return { "gb-logistics.origin-incoming", row.contract }, { "gb-logistics.origin-incoming-tooltip", row.contract }
  end
  local planet = row.planet and planets.caption(row.planet) or "?"
  local caption = { "gb-logistics.origin-" .. row.origin, planet }
  if not row.loss then return caption, { "gb-logistics.origin-planet-tooltip", row.contract } end
  local terms = row.planet and planets.transit_terms(row.planet)
  return caption, { "gb-logistics.origin-planet-loss-tooltip", row.contract, percent(row.loss),
    terms and percent(terms.max_loss) or "?" }
end

-- Writes a shipment's row: every cell when `fresh`, otherwise only the countdowns.
local function refresh_shipment_row(cells, row, now, factor, fresh)
  cells.lands.caption = row.left > 0
    and { "gb-logistics.lands", core.clock(row.arrival), catalog.format_duration(row.left) }
    or { "gb-logistics.landed", core.clock(row.arrival) }
  if fresh or row.state == "queued" then cells.state.caption = state_caption(row, now) end
  if not fresh then return end
  cells.state.tooltip = state_tooltip(row)
  local prototype = (row.kind == "fluid" and prototypes.fluid or prototypes.item)[row.name]
  cells.goods.caption = "[" .. row.kind .. "=" .. row.name .. "] " .. count_text(row.count)
  cells.goods.tooltip = prototype and prototype.localised_name or row.name
  local tier = freight.TIERS[row.tier]
  cells.tier.caption = { "gb-gui.tier-" .. row.tier }
  cells.tier.tooltip = tier and tier_tooltip(tier, factor) or ""
  cells.origin.caption, cells.origin.tooltip = origin_texts(row)
  if row.unit_cost > 0 then
    cells.cost.caption = catalog.format_credits(row.unit_cost)
    cells.cost.tooltip = { row.origin == "purchase" and "gb-logistics.cost-tooltip"
      or "gb-logistics.cost-planet-tooltip" }
  else
    cells.cost.caption = { "gb-logistics.free" }
    cells.cost.tooltip = { "gb-logistics.free-tooltip" }
  end
end

local function refresh_shipments(player, view, hub)
  local elements = view.elements
  local now = game.tick
  local capsules = freight.capsules(hub.unit_number)
  local rows = core.shipments(capsules, player.force_index, now, freight.TIERS, {
    unload_ticks = freight.UNLOAD_INTERVAL, held = held_tiers(hub.unit_number),
    contracts = contract_facts(player.force_index, capsules),
  })
  local shown = core.page(rows, view.shipments_page, core.SHIPMENT_ROWS)
  view.shipments_page = shown.page
  refresh_pager(elements.pagers.shipments, shown)
  elements.shipment_count.caption = { "gb-logistics.shipments", #rows }
  elements.no_shipment.visible = #rows == 0
  local factor = fee_factor(player.force_index)
  show_rows(view, "shipments", elements.shipment_rows, #shown.items)
  for i, row in ipairs(shown.items) do
    local key = table.concat({ row.kind, row.name, row.count, row.tier, row.state, row.origin, row.contract or "",
      row.planet or "", row.loss or "", row.unit_cost, row.arrival, factor }, " ")
    local _, fresh = drawn_row(view, "shipments", i, key)
    refresh_shipment_row(elements.shipment_rows[i], row, now, factor, fresh)
  end
end

-- "[img=entity/gb-export-chest] 3 ([img=utility/status_not_working] 1)" for each building.
local function groups_caption(groups)
  local parts = {}
  for _, group in ipairs(groups) do
    local text = "[img=entity/" .. group.name .. "] " .. group.count
    local flagged = {}
    for _, diode in ipairs({ "red", "yellow" }) do
      if group[diode] > 0 then flagged[#flagged + 1] = "[img=" .. DIODE_SPRITES[diode] .. "] " .. group[diode] end
    end
    if #flagged > 0 then text = text .. " (" .. table.concat(flagged, " ") .. ")" end
    parts[#parts + 1] = text
  end
  return table.concat(parts, "   ")
end

-- The modules of a hub as listed now: {hub, tick, rows, groups (see core.modules), entities =
-- {[unit_number] = entity}}.
local function list_modules(player, hub)
  local modules = entity_status.modules_of(hub.unit_number, player.force_index)
  local entities = {}
  for _, module in ipairs(modules) do entities[module.unit_number] = module.entity end
  local listed = core.modules(modules)
  return { hub = hub.unit_number, tick = game.tick, rows = listed.rows, groups = listed.groups, entities = entities }
end

-- Shows the modules of a hub, listed again when the hub changed or the list is MODULE_RESCAN_TICKS
-- old; returns the entity the camera follows when one is in focus.
local function refresh_modules(player, view, hub, surfaces)
  local elements = view.elements
  local listed = view.modules
  if not (listed and listed.hub == hub.unit_number and game.tick - listed.tick < logistics_gui.MODULE_RESCAN_TICKS) then
    listed = list_modules(player, hub)
    view.modules = listed
  end
  local shown = core.page(listed.rows, view.modules_page, core.MODULE_ROWS)
  view.modules_page = shown.page
  refresh_pager(elements.pagers.modules, shown)
  elements.module_count.caption = { "gb-logistics.modules", #listed.rows }
  elements.module_groups.caption = groups_caption(listed.groups)
  elements.no_module.visible = #listed.rows == 0
  show_rows(view, "modules", elements.module_rows, #shown.items)
  for i, row in ipairs(shown.items) do
    local cells, entity = elements.module_rows[i], listed.entities[row.unit_number]
    local focused = row.unit_number == view.focus
    local drawn, fresh = drawn_row(view, "modules", i, row.unit_number .. (focused and " focused" or ""))
    if fresh then
      cells.locate.sprite = "entity/" .. row.name
      cells.locate.toggled = focused
      cells.locate.tags = { gb_action = "logistics-locate", unit = row.unit_number }
      cells.name.caption = entity.valid and { "", entity.localised_name, " ", location(entity, surfaces) } or ""
    end
    draw_status(cells.status, drawn, fresh, row.unit_number)
  end
  local focus = view.focus and listed.entities[view.focus]
  return focus and focus.valid and focus or nil
end

-- Points the camera at an entity, written only when it changes target.
local function aim(camera, entity)
  if camera.entity == entity then return end
  camera.surface_index = entity.surface_index
  camera.entity = entity
end

local function refresh_detail(player, view, hub, surfaces)
  local elements = view.elements
  elements.detail.visible = hub ~= nil
  if not hub then return end
  local tier = freight.tier(hub.unit_number)
  elements.title.caption = location(hub, surfaces)
  elements.tier.caption = { "gb-logistics.tier", { "gb-gui.tier-" .. tier.name } }
  elements.tier.tooltip = tier_tooltip(tier, fee_factor(player.force_index))
  elements.power.caption = hubs.has_power(hub) and { "gb-logistics.powered" } or { "gb-logistics.unpowered" }
  elements.queue.caption = queue_caption(core.queue_use(freight.capsules(hub.unit_number), freight.TIERS, tier.name))
  refresh_shipments(player, view, hub)
  local focus = refresh_modules(player, view, hub, surfaces)
  if not focus then view.focus = nil end
  aim(elements.camera, focus or hub)
end

local function refresh(player, view, window)
  local list = force_hubs(player.force_index)
  view.hub = core.select(list, view.hub, window.hub)
  local surfaces = {}
  refresh_hubs(view, list, surfaces)
  refresh_detail(player, view, view.hub and hubs.get(view.hub) or nil, surfaces)
end

local function add_pager(parent, list)
  local flow = parent.add({ type = "flow", direction = "horizontal" })
  local pager = {}
  pager.previous = flow.add({ type = "button", caption = "<", style = "mini_button",
    tags = { gb_action = "logistics-page", list = list, step = -1 } })
  pager.label = flow.add({ type = "label" })
  pager.next = flow.add({ type = "button", caption = ">", style = "mini_button",
    tags = { gb_action = "logistics-page", list = list, step = 1 } })
  return pager
end

local function add_heading(parent, elements, count_name, list)
  local flow = parent.add({ type = "flow", direction = "horizontal" })
  elements[count_name] = flow.add({ type = "label", style = "caption_label" })
  elements.pagers[list] = add_pager(flow, list)
  return flow
end

local function build_hubs(body, elements)
  add_heading(body, elements, "hub_count", "hubs")
  elements.no_hub = body.add({ type = "label", caption = { "gb-logistics.no-hub" } })
  local list = body.add({ type = "table", column_count = 4 })
  elements.hub_rows = {}
  for i = 1, core.HUB_ROWS do
    elements.hub_rows[i] = {
      select = list.add({ type = "button", tooltip = { "gb-logistics.select-tooltip" } }),
      power = list.add({ type = "label", tooltip = { "gb-logistics.power-tooltip" } }),
      status = list.add({ type = "label", tooltip = { "gb-logistics.status-tooltip" } }),
      queue = list.add({ type = "label", tooltip = { "gb-logistics.queue-tooltip" } }),
    }
  end
end

local function build_shipments(detail, elements)
  add_heading(detail, elements, "shipment_count", "shipments")
  elements.no_shipment = detail.add({ type = "label", caption = { "gb-logistics.no-shipment" } })
  local list = detail.add({ type = "table", column_count = #SHIPMENT_COLUMNS })
  for _, column in ipairs(SHIPMENT_COLUMNS) do
    list.add({ type = "label", style = "bold_label", caption = { "gb-logistics.column-" .. column },
      tooltip = { SHIPMENT_COLUMN_TOOLTIPS[column] } })
  end
  elements.shipment_rows = {}
  for i = 1, core.SHIPMENT_ROWS do
    local cells = {}
    for _, column in ipairs(SHIPMENT_COLUMNS) do cells[column] = list.add({ type = "label" }) end
    elements.shipment_rows[i] = cells
  end
end

local function build_modules(detail, elements)
  local heading = add_heading(detail, elements, "module_count", "modules")
  elements.module_groups = heading.add({ type = "label", tooltip = { "gb-logistics.groups-tooltip" } })
  elements.no_module = detail.add({ type = "label", caption = { "gb-logistics.no-module" } })
  local list = detail.add({ type = "table", column_count = 3 })
  elements.module_rows = {}
  for i = 1, core.MODULE_ROWS do
    elements.module_rows[i] = {
      locate = list.add({ type = "sprite-button", style = "tool_button", tooltip = { "gb-logistics.locate-tooltip" } }),
      name = list.add({ type = "label" }),
      status = list.add({ type = "label" }),
    }
  end
end

local function build(_, container, view)
  local elements = { pagers = {} }
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  build_hubs(body, elements)
  local detail = body.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.detail = detail
  local top = detail.add({ type = "flow", direction = "horizontal" })
  elements.camera = top.add({ type = "camera", position = { 0, 0 }, zoom = CAMERA_ZOOM })
  elements.camera.style.width, elements.camera.style.height = 240, 160
  local header = top.add({ type = "flow", direction = "vertical" })
  elements.title = header.add({ type = "label", style = "bold_label" })
  elements.power = header.add({ type = "label", tooltip = { "gb-logistics.power-tooltip" } })
  elements.tier = header.add({ type = "label" })
  elements.queue = header.add({ type = "label", tooltip = { "gb-logistics.queue-tooltip" } })
  build_shipments(detail, elements)
  build_modules(detail, elements)
  view.hubs_page, view.shipments_page, view.modules_page = 1, 1, 1
  view.drawn, view.visible = { hubs = {}, shipments = {}, modules = {} }, {}
  view.elements = elements
end

local actions = {}

-- GUI events are player input: only a hub of the player's force is selected.
actions["logistics-select-hub"] = function(player, view, tags, window)
  local hub = type(tags.hub) == "number" and hubs.get(tags.hub)
  if hub and hub.force_index == player.force_index then
    view.hub, view.focus = tags.hub, nil
    view.shipments_page, view.modules_page = 1, 1
  end
  refresh(player, view, window)
end

local PAGED = { hubs = true, shipments = true, modules = true }

actions["logistics-page"] = function(player, view, tags, window)
  if not PAGED[tags.list] then return end
  local field = tags.list .. "_page"
  view[field] = (view[field] or 1) + (tags.step == -1 and -1 or 1)
  refresh(player, view, window)
end

actions["logistics-locate"] = function(player, view, tags, window)
  view.focus = view.focus ~= tags.unit and tags.unit or nil
  refresh(player, view, window)
end

bazaar_gui.register_tab({ name = "logistics", order = 25, build = build, refresh = refresh, actions = actions })

return logistics_gui
