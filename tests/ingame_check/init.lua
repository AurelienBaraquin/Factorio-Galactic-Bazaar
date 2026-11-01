-- The in-game check (docs/ingame-check.md), loaded by control.lua only when the gb-ingame-check helper
-- mod is active, which only tools/ingame/run.py does, in a sandboxed client: the headless test server
-- draws and translates nothing. Builds every building of the mod beside base references, takes
-- screenshots (by day, alt mode, night, animation frames, unpowered, each window tab, the technology
-- tree), asks the client to translate every name of the mod and every text of the window, then writes
-- script-output/gb-ingame/report.json and done.json.
local plan = require("tests.ingame_check.plan")
local bazaar_gui = require("scripts.bazaar_gui")

local OUT = "gb-ingame/"
local REFERENCES = { "steel-chest", "accumulator" }
local ANIMATED = { "gb-hub", "gb-teleporter" }
local ANIMATION_FRAMES, ANIMATION_STEP = 8, 4
local SCENE_WIDTH, GAP, SUBSTATION_SPACING = 40, 2, 14
local SETTLE_TICKS, UNPOWERED_TICKS, TAB_TICKS, TRANSLATION_TIMEOUT = 300, 600, 30, 600
local ZOOM_CLOSE = 2

local ctx = {
  report = { screenshots = {}, errors = {}, missing = {}, no_description = {}, checked = 0 },
  pending = {}, pending_count = 0, created = {},
}

local function shot(name, spec)
  spec.player = ctx.player
  spec.surface = ctx.surface
  spec.path = OUT .. name .. ".png"
  game.take_screenshot(spec)
  ctx.report.screenshots[#ctx.report.screenshots + 1] = name .. ".png"
end

local function translate(localised, kind)
  local id = ctx.player.request_translation(localised)
  if not id then
    ctx.report.errors[#ctx.report.errors + 1] = "request_translation refused: " .. serpent.line(localised)
    return
  end
  ctx.pending[id] = { localised = localised, kind = kind }
  ctx.pending_count = ctx.pending_count + 1
  ctx.report.checked = ctx.report.checked + 1
end

-- The buildings of the mod: what its items place.
local function buildings()
  local names = {}
  for name, item in pairs(prototypes.item) do
    if name:sub(1, 3) == "gb-" and item.place_result then names[#names + 1] = item.place_result.name end
  end
  table.sort(names)
  return names
end

local function create(name, position)
  local entity = ctx.surface.create_entity({ name = name, position = position, force = ctx.player.force,
    raise_built = true })
  ctx.created[#ctx.created + 1] = entity
  return entity
end

local function clear(area)
  for _, entity in pairs(ctx.surface.find_entities(area)) do
    if entity.valid and entity.type ~= "character" then entity.destroy() end
  end
  local tiles = {}
  for x = math.floor(area[1][1]), math.ceil(area[2][1]) do
    for y = math.floor(area[1][2]), math.ceil(area[2][2]) do
      tiles[#tiles + 1] = { name = "grass-1", position = { x, y } }
    end
  end
  ctx.surface.set_tiles(tiles)
  ctx.surface.destroy_decoratives({ area = area })
end

local function circuit_connector(entity)
  local ok, connector = pcall(entity.get_wire_connector, defines.wire_connector_id.circuit_red, true)
  return ok and connector or nil
end

local function setup()
  ctx.player = game.get_player(1)
  ctx.surface = ctx.player.surface
  ctx.report.locale = ctx.player.locale
  ctx.player.force.research_all_technologies()
  ctx.surface.peaceful_mode = true
  ctx.surface.freeze_daytime = true
  ctx.surface.daytime = 0
  ctx.names = buildings()
  local entries = {}
  for index, name in ipairs(REFERENCES) do entries[index] = name end
  for _, name in ipairs(ctx.names) do entries[#entries + 1] = name end
  local sizes = {}
  for index, name in ipairs(entries) do
    local prototype = prototypes.entity[name]
    sizes[index] = { width = prototype.tile_width, height = prototype.tile_height }
  end
  -- Lanes between rows hold the substations and the hubs every building needs within reach.
  local lane = prototypes.entity["gb-hub"].tile_height + 2
  local layout = plan.layout(sizes, SCENE_WIDTH, GAP, lane)
  local origin = { x = 0, y = 0 }
  ctx.area = { { origin.x - 4, origin.y - lane - 4 },
    { origin.x + layout.width + 24, origin.y + layout.height + lane + 4 } }
  ctx.centre = { x = origin.x + layout.width / 2, y = origin.y + layout.height / 2 }
  ctx.resolution = { math.min(4096, (layout.width + 8) * 32),
    math.min(4096, (layout.height + 2 * lane + 4) * 32) }
  clear(ctx.area)
  ctx.player.teleport({ origin.x + layout.width / 2, origin.y + layout.height + lane + 12 })
  ctx.entities = {}
  for index, name in ipairs(entries) do
    local position = layout.positions[index]
    ctx.entities[name] = create(name, { origin.x + position.x, origin.y + position.y })
  end
  -- Power: an energy interface feeding substations in the lanes, joined by copper wires.
  local previous
  for _, position in ipairs(plan.substations(layout, SUBSTATION_SPACING)) do
    local pole = create("substation", { origin.x + position.x, origin.y + position.y })
    if previous then
      pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        .connect_to(previous.get_wire_connector(defines.wire_connector_id.pole_copper, true), false)
    end
    previous = pole
  end
  for _, position in ipairs(plan.hubs(layout, SUBSTATION_SPACING)) do
    create("gb-hub", { origin.x + position.x, origin.y + position.y })
  end
  ctx.source = create("electric-energy-interface", { origin.x - 2, origin.y + layout.lanes[1] })
  ctx.source.power_production = 1e9
  ctx.source.electric_buffer_size = 1e10
  -- A red wire through every building with a circuit connector, from the steel chest.
  local last = circuit_connector(ctx.entities["steel-chest"])
  for _, name in ipairs(ctx.names) do
    local connector = circuit_connector(ctx.entities[name])
    if connector and last then
      connector.connect_to(last, false)
      last = connector
    end
  end
  -- An export chest out of every hub's range, to show its alert.
  ctx.isolated = create("gb-export-chest", { origin.x + layout.width + 18, ctx.centre.y })
  return SETTLE_TICKS
end

local function scene_shots()
  local scene = { position = ctx.centre, resolution = ctx.resolution, zoom = 1 }
  shot("scene-day", scene)
  shot("scene-alt", { position = ctx.centre, resolution = ctx.resolution, zoom = 1, show_entity_info = true })
  shot("scene-night", { position = ctx.centre, resolution = ctx.resolution, zoom = 1, daytime = 0.5 })
  for _, name in ipairs(ctx.names) do
    local entity = ctx.entities[name]
    local prototype = entity.prototype
    local size = math.max(prototype.tile_width, prototype.tile_height) + 2
    local pixels = size * 32 * ZOOM_CLOSE
    shot("entity/" .. name, { position = entity.position, resolution = { pixels, pixels }, zoom = ZOOM_CLOSE })
  end
  shot("isolated-alt", { position = ctx.isolated.position, resolution = { 384, 384 }, zoom = ZOOM_CLOSE,
    show_entity_info = true })
end

local function animation_steps()
  local steps = {}
  for frame = 1, ANIMATION_FRAMES do
    steps[#steps + 1] = function()
      for _, name in ipairs(ANIMATED) do
        local entity = ctx.entities[name]
        if entity then
          shot(("anim/%s-%d"):format(name, frame),
            { position = entity.position, resolution = { 640, 640 }, zoom = ZOOM_CLOSE })
        end
      end
      return ANIMATION_STEP
    end
  end
  return steps
end

local function cut_power()
  ctx.source.destroy()
  ctx.entities["accumulator"].destroy()
  return UNPOWERED_TICKS
end

local function unpowered_shots()
  shot("scene-unpowered-alt", { position = ctx.centre, resolution = ctx.resolution, zoom = 1, show_entity_info = true })
end

-- Every localised caption, tooltip and list item under `element`.
local function window_strings(element, found)
  for _, field in ipairs({ "caption", "tooltip" }) do
    local ok, value = pcall(function() return element[field] end)
    if ok and type(value) == "table" then found[#found + 1] = value end
  end
  if element.type == "drop-down" or element.type == "list-box" then
    for _, item in ipairs(element.items) do
      if type(item) == "table" then found[#found + 1] = item end
    end
  end
  for _, child in ipairs(element.children) do window_strings(child, found) end
  return found
end

local function window_steps()
  local steps = {}
  steps[1] = function()
    local hub = ctx.entities["gb-hub"]
    ctx.player.teleport({ hub.position.x, hub.position.y + 4 })
    bazaar_gui.open(ctx.player, nil, hub)
    local data = bazaar_gui.window(ctx.player.index)
    if not data then
      ctx.report.errors[#ctx.report.errors + 1] = "the Galactic Bazaar window did not open"
      return
    end
    local names = {}
    for name, tab in pairs(data.elements.tabs) do names[tab.index] = name end
    ctx.tabs = names
    return TAB_TICKS
  end
  steps[2] = function()
    local base = ctx.next
    for index, name in ipairs(ctx.tabs or {}) do
      table.insert(ctx.queue, base + 2 * index - 1, function()
        bazaar_gui.open(ctx.player, name, ctx.entities["gb-hub"])
        return TAB_TICKS
      end)
      table.insert(ctx.queue, base + 2 * index, function()
        shot("gui/" .. name, { position = ctx.player.position, resolution = { 1920, 1080 }, show_gui = true })
        local window = ctx.player.gui.screen[bazaar_gui.WINDOW]
        if window then
          for _, localised in ipairs(window_strings(window, {})) do translate(localised, "window " .. name) end
        end
      end)
    end
  end
  return steps
end

-- Names (and, for information, descriptions) of every prototype of the mod a player can meet.
local function translate_prototypes()
  bazaar_gui.close(ctx.player.index)
  local groups = { "entity", "item", "recipe", "technology", "fluid", "virtual_signal", "mod_setting",
    "custom_input", "shortcut", "tips_and_tricks_item" }
  for _, group in ipairs(groups) do
    local ok, list = pcall(function() return prototypes[group] end)
    if ok and list then
      for name, prototype in pairs(list) do
        local hidden = false
        pcall(function() hidden = prototype.hidden end)
        -- A custom input linked to a game control is not listed in the controls settings.
        if group == "custom_input" and prototype.linked_game_control ~= "" then hidden = true end
        if name:sub(1, 3) == "gb-" and not hidden then
          -- The controls settings name a custom input by [controls], not by its prototype's key.
          local localised = group == "custom_input" and { "controls." .. name } or prototype.localised_name
          translate(localised, group .. " name " .. name)
          -- An item's tooltip shows the description of the building it places.
          if group == "entity" or group == "technology" then
            translate(prototype.localised_description, group .. " description " .. name)
          end
        end
      end
    end
  end
  ctx.deadline = game.tick + TRANSLATION_TIMEOUT
end

local function await_translations()
  if ctx.pending_count > 0 and game.tick < ctx.deadline then return false end
  for _, entry in pairs(ctx.pending) do
    ctx.report.errors[#ctx.report.errors + 1] = "no translation came back for " .. serpent.line(entry.localised)
  end
  ctx.report.missing = plan.unique(ctx.report.missing, function(entry) return entry.string end)
  -- The technology screen pauses a single-player game: it comes last, shot in the tick it opens.
  ctx.player.open_technology_gui("gb-overdraft-1")
  shot("technology-tree", { position = ctx.player.position, resolution = { 1920, 1080 }, show_gui = true })
  helpers.write_file(OUT .. "report.json", helpers.table_to_json(ctx.report))
  helpers.write_file(OUT .. "done.json", helpers.table_to_json({ tick = game.tick }))
end

local function on_translated(event)
  local entry = ctx.pending[event.id]
  if not entry then return end
  ctx.pending[event.id] = nil
  ctx.pending_count = ctx.pending_count - 1
  if event.translated then return end
  local record = { kind = entry.kind, string = serpent.line(entry.localised) }
  if entry.kind:find(" description ", 1, true) then
    ctx.report.no_description[#ctx.report.no_description + 1] = record
  else
    ctx.report.missing[#ctx.report.missing + 1] = record
  end
end

ctx.queue = { setup, scene_shots }
for _, step in ipairs(animation_steps()) do ctx.queue[#ctx.queue + 1] = step end
for _, step in ipairs({ cut_power, unpowered_shots }) do ctx.queue[#ctx.queue + 1] = step end
for _, step in ipairs(window_steps()) do ctx.queue[#ctx.queue + 1] = step end
for _, step in ipairs({ translate_prototypes, await_translations }) do
  ctx.queue[#ctx.queue + 1] = step
end
ctx.next, ctx.wake = 1, 60

-- One step per tick at most; a step returns how many ticks to wait before the next, or false to run
-- again next tick. An error is recorded and the check goes on, so done.json is always written.
local function on_tick(event)
  if event.tick < ctx.wake or not game.get_player(1) then return end
  local step = ctx.queue[ctx.next]
  if not step then return end
  local ok, result = pcall(step)
  local failure = not ok and tostring(result) or ""
  if not ok then
    ctx.report.errors[#ctx.report.errors + 1] = "step " .. ctx.next .. ": " .. failure
    result = nil
  end
  -- Progress, read by tools/ingame/run.py when the check does not finish.
  helpers.write_file(OUT .. "progress.txt", ("tick %d step %d/%d %s\n"):format(event.tick, ctx.next, #ctx.queue,
    failure), true)
  if result ~= false then ctx.next = ctx.next + 1 end
  ctx.wake = event.tick + (type(result) == "number" and result or 1)
end

script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_string_translated, on_translated)
