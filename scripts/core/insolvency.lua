-- Insolvency and bankruptcy (#97, ADR-0022). Pure Lua: operates on a force's state from
-- storage.forces. A force is insolvent from the check at which its available funds were below zero
-- at some point of the period (its balance beyond the overdraft limit, through interest) or its
-- arrears exceeded its available funds. It recovers at a check once its available funds stayed at or
-- above a margin for the whole period and it owes no arrears; still insolvent GRACE_TICKS after it
-- became so, it goes bankrupt: its open contracts end (offers declined, active ones failed, their
-- guarantees kept), its debt is written off (a negative balance back to zero, arrears cleared), its
-- reputation falls to the minimum, and credit (loans and the overdraft) is refused for a ban that
-- doubles with each bankruptcy.
local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")
local reputation = require("scripts.core.reputation")

local insolvency = {}

-- Period of the checks, grace before bankruptcy and the first credit ban.
insolvency.CHECK_TICKS = 60
insolvency.GRACE_TICKS = 3600 * 10
insolvency.BAN_TICKS = 3600 * 60
-- The ban doubles with each bankruptcy, at most this many times (8 hours).
insolvency.MAX_BAN_DOUBLINGS = 3
-- Share of the overdraft limit the available funds must stay above for a period to recover, so that
-- a force hovering at the limit is not declared insolvent and solvent again every minute.
insolvency.RECOVERY_SHARE = 0.05
insolvency.WRITE_OFF_KIND = "bankruptcy-write-off"

--- Gives a force state its insolvency fields if it lacks them: `bankruptcies` (a count);
--- `insolvent_since` and `credit_ban_until` (ticks) are nil while they do not apply.
function insolvency.init(state)
  state.bankruptcies = state.bankruptcies or 0
end

--- Whether a force is insolvent.
function insolvency.insolvent(state)
  return state.insolvent_since ~= nil
end

--- Whether credit (loans and the overdraft) is refused to a force after a bankruptcy.
function insolvency.credit_banned(state)
  return state.credit_ban_until ~= nil
end

--- The available funds an insolvent force must keep for a whole period to recover.
function insolvency.recovery_margin(state)
  return account.overdraft_limit(state) * insolvency.RECOVERY_SHARE
end

--- The balance an insolvent force must keep for a whole period to recover.
function insolvency.recovery_balance(state)
  return insolvency.recovery_margin(state) - account.overdraft_limit(state)
end

--- Ticks left at `tick` before an insolvent force goes bankrupt (at least 0), or nil.
function insolvency.grace_left(state, tick)
  if not state.insolvent_since then return nil end
  return math.max(0, state.insolvent_since + insolvency.GRACE_TICKS - tick)
end

--- Ticks left at `tick` before credit returns to a force after a bankruptcy (at least 0), or nil.
function insolvency.ban_left(state, tick)
  if not state.credit_ban_until then return nil end
  return math.max(0, state.credit_ban_until - tick)
end

--- The credit ban of a force's `count`-th bankruptcy.
function insolvency.ban_ticks(count)
  return insolvency.BAN_TICKS * 2 ^ (math.min(count, insolvency.MAX_BAN_DOUBLINGS + 1) - 1)
end

--- Declares a force bankrupt at `tick`. Returns {name = "bankrupt", written_off (the debt written
--- off: a negative balance and the arrears), ban_ticks, contracts (the ids closed, in order)}.
function insolvency.bankrupt(state, tick)
  local ids = {}
  for id in pairs(state.contracts.open) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local contract = state.contracts.open[id]
    if not contracts.decline(contract, tick) then contracts.default(contract, tick, 0) end
    contracts.close(state, id)
  end
  local written_off = math.max(0, -state.balance)
  if written_off > 0 then
    account.apply(state, written_off, { tick = tick, kind = insolvency.WRITE_OFF_KIND, key = "account/bankruptcy" })
  end
  written_off = written_off + (state.arrears or 0)
  state.arrears = 0
  state.overdraft_low, state.solvency_low = state.balance, state.balance
  state.reputation = reputation.MIN
  state.bankruptcies = (state.bankruptcies or 0) + 1
  local ban = insolvency.ban_ticks(state.bankruptcies)
  state.credit_ban_until = tick + ban
  state.insolvent_since = nil
  return { name = "bankrupt", written_off = written_off, ban_ticks = ban, contracts = ids }
end

--- Checks a force at `tick`, once per CHECK_TICKS: ends an expired credit ban, then starts, ends or
--- concludes its insolvency from its lowest balance since the previous check (`solvency_low`, kept
--- by the account) and its arrears. Starts the next period. Returns the events, in order: tables
--- named "credit-restored", "insolvent", "recovered" or "bankrupt" (see `bankrupt`).
function insolvency.check(state, tick)
  local events = {}
  if state.credit_ban_until and tick >= state.credit_ban_until then
    state.credit_ban_until = nil
    events[#events + 1] = { name = "credit-restored" }
  end
  local lowest = math.min(state.solvency_low or state.balance, state.balance) + account.overdraft_limit(state)
  state.solvency_low = state.balance
  local arrears = state.arrears or 0
  if not state.insolvent_since then
    if lowest < 0 or arrears > account.available(state) then
      state.insolvent_since = tick
      events[#events + 1] = { name = "insolvent" }
    end
  elseif arrears <= 0 and lowest >= insolvency.recovery_margin(state) then
    state.insolvent_since = nil
    events[#events + 1] = { name = "recovered" }
  elseif tick >= state.insolvent_since + insolvency.GRACE_TICKS then
    events[#events + 1] = insolvency.bankrupt(state, tick)
  end
  return events
end

--- Checks every force of `forces` ({[force_index] = state}) at `tick`, in force index order. Returns
--- the events as {force_index, event}, in order.
function insolvency.check_all(forces, tick)
  local indices = {}
  for force_index in pairs(forces) do indices[#indices + 1] = force_index end
  table.sort(indices)
  local reported = {}
  for _, force_index in ipairs(indices) do
    for _, event in ipairs(insolvency.check(forces[force_index], tick)) do
      reported[#reported + 1] = { force_index = force_index, event = event }
    end
  end
  return reported
end

local function earliest(a, b)
  if a and b then return math.min(a, b) end
  return a or b
end

local function latest(a, b)
  if a and b then return math.max(a, b) end
  return a or b
end

--- Folds a merged force's insolvency into the destination's, which keeps the stricter state: the
--- earliest insolvency (merging into a fresh force does not restart the clock), the latest credit ban
--- and the most bankruptcies.
function insolvency.merge(destination, source)
  insolvency.init(destination)
  insolvency.init(source)
  destination.insolvent_since = earliest(destination.insolvent_since, source.insolvent_since)
  destination.credit_ban_until = latest(destination.credit_ban_until, source.credit_ban_until)
  destination.bankruptcies = math.max(destination.bankruptcies, source.bankruptcies)
end

return insolvency
