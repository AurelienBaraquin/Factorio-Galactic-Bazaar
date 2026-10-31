-- The planets window (#83, #85): the NPC planets, their distance, transit terms, specialties and the
-- slots free for the player's force, opened from the market window of a hub. A resource specialty
-- can be leased from it (a mining concession delivered to that hub). Rows are built once on opening
-- and updated in place. Interface state lives in storage.planets_gui.
local concessions = require("scripts.concessions")
local contracts = require("scripts.contracts")
local hubs = require("scripts.hubs")
local planets = require("scripts.planets")
local transit = require("scripts.core.transit")

local planets_gui = {}

planets_gui.REFRESH_TICKS = 60

local WINDOW = "gb_planets"

local function window_of(player_index)
  local data = storage.planets_gui[player_index]
  local window = data and data.elements.window
  return window and window.valid and window or nil
end

-- How a specialty reads: an item icon for a resource, the category's name for crafting.
local function specialty_caption(specialty)
  if specialty.kind == "resource" then
    return { "", "[item=" .. specialty.name .. "] ", prototypes.item[specialty.name].localised_name }
  end
  local category = prototypes.recipe_category[specialty.name]
  return { "?", { "gb-planets.category-" .. specialty.name }, category and category.localised_name or specialty.name }
end

local function refresh(player, data)
  for _, row in ipairs(data.elements.rows) do
    local free = planets.free(player.force_index, row.planet, row.kind, row.name) or 0
    row.slots.caption = { "gb-planets.slots", free, row.total }
    if row.lease then row.lease.enabled = free > 0 end
    if row.book then row.book.enabled = free > 0 end
  end
end

-- The tooltip of a lease button: what one slot ships, its charge and guarantee.
local function lease_tooltip(planet, resource)
  local spec = concessions.terms(planet.name, resource, 1)
  if not spec then return { "gb-planets.lease-unavailable" } end
  local terms = transit.terms(planet.distance)
  return { "gb-planets.lease-terms", spec.provides[1].count / (spec.duration_ticks / spec.installment_ticks),
    spec.installment_ticks / 3600, spec.duration_ticks / 3600, string.format("%.0f", spec.charge),
    string.format("%.0f", spec.deposit), string.format("%.4g", terms.max_loss * 100) }
end

local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical",
    caption = { "gb-planets.title" } })
  local elements = { window = window, rows = {} }
  local body = window.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  body.add({ type = "button", caption = { "gb-planets.close" }, tags = { gb_action = "planets-close" } })
  local list = body.add({ type = "table", column_count = 6 })
  for _, header in ipairs({ "planet", "distance", "transit", "specialty", "free", "lease" }) do
    list.add({ type = "label", style = "bold_label", caption = { "gb-planets.column-" .. header } })
  end
  for _, planet in ipairs(planets.catalog()) do
    for _, specialty in ipairs(planet.specialties) do
      list.add({ type = "label", caption = planets.caption(planet.name) })
      list.add({ type = "label", caption = { "gb-planets.distance", planet.distance } })
      local terms = transit.terms(planet.distance)
      list.add({ type = "label", caption = { "gb-planets.transit", string.format("%d", terms.delay_ticks / 60),
        string.format("%.4g", terms.max_loss * 100) } })
      list.add({ type = "label", caption = specialty_caption(specialty) })
      local row = {
        planet = planet.name, kind = specialty.kind, name = specialty.name, total = specialty.slots,
        slots = list.add({ type = "label" }),
      }
      if specialty.kind == "resource" then
        row.lease = list.add({ type = "button", caption = { "gb-planets.lease" },
          tooltip = lease_tooltip(planet, specialty.name),
          tags = { gb_action = "planets-lease", planet = planet.name, resource = specialty.name } })
      else
        local cell = list.add({ type = "flow", direction = "horizontal" })
        row.recipe = cell.add({ type = "choose-elem-button", elem_type = "recipe",
          tooltip = { "gb-planets.book-recipe" } })
        row.book = cell.add({ type = "button", caption = { "gb-planets.book" }, tooltip = { "gb-planets.book-terms" },
          tags = { gb_action = "planets-book", planet = planet.name, category = specialty.name } })
      end
      elements.rows[#elements.rows + 1] = row
    end
  end
  window.force_auto_center()
  return elements
end

--- Opens the planets window of a player, at the hub concessions are delivered to.
function planets_gui.open(player, hub_unit_number)
  planets_gui.close(player.index)
  local data = { hub = hub_unit_number, elements = build(player) }
  storage.planets_gui[player.index] = data
  refresh(player, data)
  -- Like the game's windows: E or Esc closes it, and it replaces the market window.
  player.opened = data.elements.window
end

function planets_gui.close(player_index)
  local window = window_of(player_index)
  if window then window.destroy() end
  storage.planets_gui[player_index] = nil
end

-- Leases a slot from a lease or book button, at the window's hub, which must still be the player's
-- force's and within reach (GUI events are player input). A book button books its row's recipe.
local function lease(player, data, element)
  local hub = hubs.get(data.hub)
  if not (hub and hub.force == player.force and player.can_reach_entity(hub)) then
    planets_gui.close(player.index)
    return player.print({ "gb-planets.hub-unavailable" })
  end
  local tags = element.tags
  local id, reason
  if tags.gb_action == "planets-book" then
    local recipe
    for _, row in ipairs(data.elements.rows) do
      if row.book == element then recipe = row.recipe.elem_value end
    end
    id, reason = concessions.book(player.force_index, data.hub, tags.planet, tags.category, recipe)
  else
    id, reason = concessions.lease(player.force_index, data.hub, tags.planet, tags.resource)
  end
  if id then
    local contract = contracts.get(player.force_index, id)
    local lease_record = storage.concessions[id]
    player.print({ "gb-planets.leased", planets.caption(tags.planet),
      lease_record.units, "[item=" .. lease_record.item .. "]", string.format("%.0f", contract.charge),
      string.format("%.0f", contract.deposit) })
  else
    player.print({ "gb-planets.refused-" .. reason })
  end
  refresh(player, data)
end

--- on_gui_click: the close, lease and book buttons of this window.
function planets_gui.on_gui_click(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  local action = element.tags.gb_action
  local data = storage.planets_gui[event.player_index]
  if action == "planets-close" then
    planets_gui.close(event.player_index)
  elseif (action == "planets-lease" or action == "planets-book") and data and window_of(event.player_index) then
    lease(game.get_player(event.player_index), data, element)
  end
end

--- on_gui_closed: E, Esc or another window closes this one.
function planets_gui.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == WINDOW and element.get_mod() == script.mod_name then
    planets_gui.close(event.player_index)
  end
end

--- on_nth_tick(REFRESH_TICKS): refreshes the open windows of connected players.
function planets_gui.on_refresh_tick()
  for player_index, data in pairs(storage.planets_gui) do
    local player = game.get_player(player_index)
    if player and player.connected and window_of(player_index) then refresh(player, data) end
  end
end

--- on_player_left_game, on_player_changed_force and on_player_removed: the window no longer applies.
function planets_gui.on_player_event(event)
  planets_gui.close(event.player_index)
end

--- on_init and on_configuration_changed: creates the state and closes every window (the catalog
--- may have changed).
function planets_gui.init()
  storage.planets_gui = storage.planets_gui or {}
  local open = {}
  for player_index in pairs(storage.planets_gui) do open[#open + 1] = player_index end
  for _, player_index in ipairs(open) do planets_gui.close(player_index) end
end

return planets_gui
