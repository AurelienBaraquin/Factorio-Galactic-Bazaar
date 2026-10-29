-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local forces = require("scripts.forces")

script.on_init(forces.init)
script.on_configuration_changed(forces.init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, forces.on_forces_merging)
