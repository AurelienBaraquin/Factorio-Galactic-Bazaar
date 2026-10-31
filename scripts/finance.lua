-- Financial engineering research (#98): `gb-credit` unlocks borrowing (scripts/loans.lua reads it),
-- and each `gb-overdraft-n` raises the force's overdraft limit. The pure account
-- (scripts/core/account.lua) cannot read research, so the level, the highest overdraft technology
-- researched, is recorded in storage.forces[i].overdraft_level whenever research changes, on on_init
-- and on_configuration_changed, and before every overdraft interest charge (a self-heal, since some
-- research changes raise no per-technology event). The limit also follows reputation
-- (account.overdraft_limit).
local finance = {}

finance.CREDIT_TECHNOLOGY = "gb-credit"
-- One technology per overdraft level, in order: level n sets account.OVERDRAFT_LEVEL_LIMITS[n].
finance.OVERDRAFT_TECHNOLOGIES = { "gb-overdraft-1", "gb-overdraft-2" }

local OVERDRAFT_LEVELS = {}
for level, name in ipairs(finance.OVERDRAFT_TECHNOLOGIES) do OVERDRAFT_LEVELS[name] = level end

--- Whether a force has researched `technology`.
function finance.researched(force, technology)
  local found = force.technologies[technology]
  return found ~= nil and found.researched
end

--- A force's overdraft level: the highest overdraft technology it researched, 0 without any.
function finance.overdraft_level(force)
  local level = 0
  for index, name in ipairs(finance.OVERDRAFT_TECHNOLOGIES) do
    if finance.researched(force, name) then level = index end
  end
  return level
end

--- Records a force's overdraft level in its state, if it has one.
function finance.sync(force)
  local state = storage.forces[force.index]
  if state then state.overdraft_level = finance.overdraft_level(force) end
end

--- on_init and on_configuration_changed, after forces.init, and every interest tick: records every
--- force's level (saves made before the levels existed have none, a mod change may have changed
--- research, and research_all_technologies, reset_technologies or copy_from raise no event per
--- technology).
function finance.init()
  for _, force in pairs(game.forces) do finance.sync(force) end
end

--- on_research_finished and on_research_reversed: an overdraft technology changes its force's level.
function finance.on_research_changed(event)
  local research = event.research
  if OVERDRAFT_LEVELS[research.name] then finance.sync(research.force) end
end

--- on_force_reset and on_technology_effects_reset: research may have changed wholesale.
function finance.on_force_event(event)
  finance.sync(event.force)
end

return finance
