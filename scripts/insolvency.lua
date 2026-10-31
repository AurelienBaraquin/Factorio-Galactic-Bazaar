-- Insolvency and bankruptcy (#97, ADR-0022): the runtime side of scripts/core/insolvency.lua. Every
-- CHECK_TICKS, after the loans' arrears collection, every force is checked in force index order and
-- told when it becomes insolvent, recovers, goes bankrupt or gets its credit back; its bankruptcy debt
-- is taken from every credit (core/account.lua) and from its positive balance at each check. The state
-- lives in storage.forces[i] (insolvent_since, recovering_since, credit_ban_until, bankruptcies,
-- bankruptcy_debt, solvency_low).
-- The ends a bankruptcy gives contracts are picked up by the features that offer them: leases release
-- their slots (concessions sweep), rented machines are released (rental service).
local catalog = require("scripts.core.catalog")
local core = require("scripts.core.insolvency")
local notifications = require("scripts.notifications")
local reputation = require("scripts.core.reputation")

local insolvency = {}

insolvency.CHECK_TICKS = core.CHECK_TICKS

-- The parameters of what a force is told of an event (kinds of the same names, scripts/notifications.lua).
local function params(state, event)
  if event.name == "insolvent" then
    return { catalog.format_credits(core.recovery_balance(state)), core.GRACE_TICKS / 3600 }
  elseif event.name == "bankrupt" then
    return { #event.contracts, catalog.format_credits(event.debt), reputation.MIN, event.ban_ticks / 3600,
      string.format("%.4g", core.RESTRUCTURING_SURCHARGE * 100) }
  end
  return {}
end

--- on_nth_tick(CHECK_TICKS): checks every force and tells it what changed.
function insolvency.on_check_tick(event)
  for _, reported in ipairs(core.check_all(storage.forces, event.tick)) do
    local index = reported.force_index
    notifications.notify(index, reported.event.name, params(storage.forces[index], reported.event))
  end
end

return insolvency
