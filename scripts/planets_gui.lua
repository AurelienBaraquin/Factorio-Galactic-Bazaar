-- The planets window (#83): the NPC planets, their distance, specialties and the slots free for the
-- player's force, opened from the market window. Read-only; rows are built once on opening and
-- updated in place. Interface state lives in storage.planets_gui.
local planets = require("scripts.planets")

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
  if specialty.kind == "resource" then return "[item=" .. specialty.name .. "]" end
  return { "gb-planets.category-" .. specialty.name }
end

local function refresh(player, data)
  for _, row in ipairs(data.elements.rows) do
    local free = planets.free(player.force_index, row.planet, row.kind, row.name) or 0
    row.slots.caption = { "gb-planets.slots", free, row.total }
  end
end

local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical",
    caption = { "gb-planets.title" } })
  local elements = { window = window, rows = {} }
  local body = window.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  body.add({ type = "button", caption = { "gb-planets.close" }, tags = { gb_action = "planets-close" } })
  local list = body.add({ type = "table", column_count = 4 })
  for _, header in ipairs({ "planet", "distance", "specialty", "free" }) do
    list.add({ type = "label", style = "bold_label", caption = { "gb-planets.column-" .. header } })
  end
  for _, planet in ipairs(planets.catalog()) do
    for _, specialty in ipairs(planet.specialties) do
      list.add({ type = "label", caption = { "gb-planets.name-" .. planet.name } })
      list.add({ type = "label", caption = { "gb-planets.distance", planet.distance } })
      list.add({ type = "label", caption = specialty_caption(specialty) })
      elements.rows[#elements.rows + 1] = {
        planet = planet.name, kind = specialty.kind, name = specialty.name, total = specialty.slots,
        slots = list.add({ type = "label" }),
      }
    end
  end
  window.force_auto_center()
  return elements
end

--- Opens the planets window of a player.
function planets_gui.open(player)
  planets_gui.close(player.index)
  local data = { elements = build(player) }
  storage.planets_gui[player.index] = data
  refresh(player, data)
end

function planets_gui.close(player_index)
  local window = window_of(player_index)
  if window then window.destroy() end
  storage.planets_gui[player_index] = nil
end

--- on_gui_click: the close button of this window.
function planets_gui.on_gui_click(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  if element.tags.gb_action == "planets-close" then planets_gui.close(event.player_index) end
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
