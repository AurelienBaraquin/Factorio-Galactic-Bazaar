-- Settlement arithmetic of the power module (ADR-0009). Pure Lua: energies in joules, trades in
-- units of `joules_per_unit`.
local power_settlement = {}

-- Margin kept below the funds, so that float rounding in the cost never makes a purchase exceed them.
power_settlement.FUNDS_MARGIN = 1e-9

--- Units to sell out of `joules` absorbed by the export substations, when the market takes at most
--- `sellable` units; and the share of its energy each substation keeps.
function power_settlement.export(joules, sellable, joules_per_unit)
  if joules <= 0 then return 0, 1 end
  local units = math.max(0, math.min(joules / joules_per_unit, sellable))
  return units, 1 - units * joules_per_unit / joules
end

--- Units to buy for import substations lacking `missing` joules (an array), when the market supplies
--- at most `buyable` units; nil when nothing is missing.
function power_settlement.wanted_units(missing, buyable, joules_per_unit)
  local joules = 0
  for _, value in ipairs(missing) do joules = joules + value end
  if joules <= 0 then return nil end
  return math.min(joules / joules_per_unit, buyable), joules
end

--- Units affordable out of `units` costing `cost` with `funds` credits available (none when the funds
--- are not positive). The cost is convex in the units and zero at zero, so scaling the units by
--- funds / cost keeps the cost within the funds.
function power_settlement.affordable(units, cost, funds)
  if cost <= funds then return units end
  if funds <= 0 then return 0 end
  return units * funds / cost * (1 - power_settlement.FUNDS_MARGIN)
end

--- The joules each import substation receives out of `units` bought, in proportion to what it lacks.
function power_settlement.shares(missing, total_missing, units, joules_per_unit)
  local ratio = units * joules_per_unit / total_missing
  local shares = {}
  for i, value in ipairs(missing) do shares[i] = value * ratio end
  return shares
end

return power_settlement
