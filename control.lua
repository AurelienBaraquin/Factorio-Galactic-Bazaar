-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local forces = require("scripts.forces")
local hubs = require("scripts.hubs")
local pricing = require("scripts.pricing")

local function init()
  forces.init()
  pricing.init()
  hubs.init()
end

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, forces.on_forces_merging)
for _, event in ipairs(hubs.BUILT_EVENTS) do
  script.on_event(event, hubs.on_built, hubs.FILTER)
end
script.on_event(defines.events.on_object_destroyed, hubs.on_object_destroyed)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "tests/forces", "tests/recipe_graph", "tests/pricing", "tests/market", "tests/hubs" },
    { load_luassert = true }
  )
end
