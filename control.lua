-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local forces = require("scripts.forces")
local pricing = require("scripts.pricing")

local function init()
  forces.init()
  pricing.init()
end

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, forces.on_forces_merging)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")({ "tests/forces", "tests/recipe_graph", "tests/pricing" }, { load_luassert = true })
end
