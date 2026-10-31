-- Keeps storage.forces in step with the game's forces (ADR-0001): one economy state per force, and
-- charges overdraft interest to those in debt every INTEREST_TICKS (ADR-0020).
local account = require("scripts.core.account")
local force_registry = require("scripts.core.force_registry")

local forces = {}

forces.INTEREST_TICKS = account.INTEREST_TICKS

local function existing_force_indices()
  local indices = {}
  for _, force in pairs(game.forces) do indices[#indices + 1] = force.index end
  return indices
end

--- on_init and on_configuration_changed: creates storage.forces and reconciles it with the
--- forces that exist. The force events keep it in step during play; this reconciliation is a
--- self-heal in case an event was missed (for example a handler that errored).
function forces.init()
  storage.forces = storage.forces or {}
  force_registry.sync(storage.forces, existing_force_indices())
end

function forces.on_force_created(event)
  force_registry.ensure(storage.forces, event.force.index)
end

function forces.on_forces_merging(event)
  force_registry.merge(storage.forces, event.source.index, event.destination.index)
end

--- on_nth_tick(INTEREST_TICKS): every force with a negative balance pays a period of interest.
function forces.on_interest_tick(event)
  force_registry.charge_interest(storage.forces, event.tick)
end

return forces
