-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local cargo = require("scripts.cargo")
local forces = require("scripts.forces")
local hubs = require("scripts.hubs")
local pricing = require("scripts.pricing")

local function init()
  forces.init()
  pricing.init()
  hubs.init()
  cargo.init()
end

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, forces.on_forces_merging)
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
  else
    cargo.forget(event.useful_id)
  end
end)

script.on_nth_tick(cargo.EXPORT_INTERVAL, cargo.on_export_tick)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "tests/forces", "tests/recipe_graph", "tests/pricing", "tests/market", "tests/hubs", "tests/cargo" },
    { load_luassert = true }
  )
end
