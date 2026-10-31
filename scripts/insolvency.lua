-- Insolvency and bankruptcy (#97, ADR-0022): the runtime side of scripts/core/insolvency.lua. Every
-- CHECK_TICKS, after the loans' arrears collection, every force is checked in force index order and
-- told when it becomes insolvent, recovers, goes bankrupt or gets its credit back. The state lives in
-- storage.forces[i] (insolvent_since, credit_ban_until, bankruptcies, solvency_low). The ends a
-- bankruptcy gives contracts are picked up by the features that offer them: leases release their
-- slots (concessions sweep), rented machines are released (rental service).
local catalog = require("scripts.core.catalog")
local core = require("scripts.core.insolvency")
local reputation = require("scripts.core.reputation")

local insolvency = {}

insolvency.CHECK_TICKS = core.CHECK_TICKS

local WARNING = { r = 1, g = 0.4, b = 0.3 }
local GOOD = { r = 0.4, g = 1, b = 0.4 }

-- What a force is told of an event, and in which colour.
local function message(state, event)
  if event.name == "insolvent" then
    return { "gb-insolvency.insolvent", catalog.format_credits(core.recovery_balance(state)),
      core.GRACE_TICKS / 3600 }, WARNING
  elseif event.name == "bankrupt" then
    return { "gb-insolvency.bankrupt", #event.contracts, catalog.format_credits(event.written_off), reputation.MIN,
      event.ban_ticks / 3600 }, WARNING
  end
  return { "gb-insolvency." .. event.name }, GOOD
end

--- on_nth_tick(CHECK_TICKS): checks every force and tells it what changed.
function insolvency.on_check_tick(event)
  for _, reported in ipairs(core.check_all(storage.forces, event.tick)) do
    local force = game.forces[reported.force_index]
    if force then
      local text, color = message(storage.forces[reported.force_index], reported.event)
      force.print(text, { color = color })
    end
  end
end

return insolvency
