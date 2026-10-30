-- Reputation (#77, ADR-0016). Pure Lua: a force's score with counterparties, moved by contract
-- outcomes (+1 fulfilled, -1 failed) and kept within [MIN, MAX]. It lowers (or, below zero, raises)
-- the force's freight fees and sizes the contracts it is offered. On a force merge only a debt
-- follows the source: a high score cannot be built in a throwaway force and handed over, and a low
-- one cannot be shed by merging away.
local reputation = {}

reputation.MIN, reputation.MAX = -20, 20
-- Change of the freight fee per point: ×0.5 at MAX, ×1.5 at MIN.
reputation.FEE_STEP = 0.025
-- Change of the size of offered contracts per point (×3 at MAX), never below MIN_SIZE.
reputation.SIZE_STEP = 0.1
reputation.MIN_SIZE = 0.5

local function bounded(score)
  return math.max(reputation.MIN, math.min(reputation.MAX, score))
end

--- The score after a change of `delta`.
function reputation.add(score, delta)
  return bounded(score + delta)
end

--- Factor applied to a force's freight fees.
function reputation.fee_factor(score)
  return 1 - reputation.FEE_STEP * bounded(score)
end

--- Factor applied to the value of the contracts a force is offered.
function reputation.contract_scale(score)
  return math.max(reputation.MIN_SIZE, 1 + reputation.SIZE_STEP * bounded(score))
end

--- The destination's score once `source` merges into it: the destination keeps its own, less the
--- source's debt.
function reputation.merge(destination, source)
  return bounded(destination + math.min(0, source))
end

return reputation
