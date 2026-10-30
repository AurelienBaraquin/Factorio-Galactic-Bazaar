-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local cargo = require("scripts.cargo")
local forces = require("scripts.forces")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local market_gui = require("scripts.market_gui")
local pricing = require("scripts.pricing")

local function init()
  forces.init()
  pricing.init()
  hubs.init()
  cargo.init()
  freight.init()
  market_gui.init()
end

remote.add_interface("galactic-bazaar", pricing.REMOTE)

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, function(event)
  freight.on_forces_merging(event)
  forces.on_forces_merging(event)
end)
script.on_event(defines.events.on_forces_merged, cargo.on_forces_merged)

-- Every way an entity can appear, filtered to the mod's buildings.
local BUILT_EVENTS = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_entity_cloned,
}
local BUILDING_FILTER = { { filter = "name", name = hubs.NAME } }
for name in pairs(cargo.KINDS) do
  table.insert(BUILDING_FILTER, { filter = "name", name = name, mode = "or" })
end

local function on_built(event)
  local entity = event.entity or event.destination
  if not (entity and entity.valid) then return end
  if hubs.on_built(entity) then
    cargo.on_hub_built(entity)
  else
    cargo.on_built(entity)
  end
end

for _, event in ipairs(BUILT_EVENTS) do
  script.on_event(event, on_built, BUILDING_FILTER)
end

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type ~= defines.target_type.entity then return end
  if hubs.forget(event.useful_id) then
    cargo.on_hub_removed(event.useful_id)
    freight.on_hub_removed(event.useful_id)
    market_gui.on_hub_removed(event.useful_id)
  else
    cargo.forget(event.useful_id)
  end
end)

-- One handler per tick interval is kept by Factorio, so handlers sharing an interval are composed.
local periodic = {}
local function every(ticks, handler)
  periodic[ticks] = periodic[ticks] or {}
  table.insert(periodic[ticks], handler)
end
every(cargo.EXPORT_INTERVAL, cargo.on_export_tick)
every(market_gui.SLOT_TICKS, market_gui.on_refresh_tick)
every(freight.UNLOAD_INTERVAL, freight.on_unload_tick)
for ticks, handlers in pairs(periodic) do
  script.on_nth_tick(ticks, function(event)
    for _, handler in ipairs(handlers) do handler(event) end
  end)
end

script.on_event(market_gui.INPUT, market_gui.on_open_input)
script.on_event(defines.events.on_gui_click, market_gui.on_gui_click)
script.on_event(defines.events.on_gui_text_changed, market_gui.on_gui_text_changed)
script.on_event(defines.events.on_gui_closed, market_gui.on_gui_closed)
script.on_event({
  defines.events.on_player_left_game, defines.events.on_player_changed_force, defines.events.on_player_removed,
}, market_gui.on_player_event)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "tests/forces", "tests/recipe_graph", "tests/pricing", "tests/overrides", "tests/market", "tests/hubs",
      "tests/cargo", "tests/freight", "tests/market_gui" },
    { load_luassert = true }
  )
end
