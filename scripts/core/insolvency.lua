-- Insolvency and bankruptcy (#97, ADR-0022). Pure Lua: operates on a force's state from
-- storage.forces. A force is insolvent from the check at which its available funds were below zero
-- at some point of the period (its balance beyond the overdraft limit, through interest) or its
-- arrears exceeded its available funds. It recovers once its available funds stayed at or above a
-- margin, with no arrears, for a whole interest period; still insolvent GRACE_TICKS after it became
-- so, it goes bankrupt: its open contracts end (offers declined, active ones failed, their guarantees
-- kept), everything it owes (a negative balance, arrears, the installments left on its loans) becomes
-- a frozen `bankruptcy_debt` that earns no interest and is taken from its positive balance at every
-- check, its reputation falls to the minimum, and credit (loans and the overdraft) is refused until a
-- ban that doubles with each bankruptcy has passed and that debt is repaid. Nothing is written off.
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
-- Share of the overdraft limit the available funds must stay above, with no arrears, for
-- RECOVERY_TICKS (an interest period) to recover, so that a force hovering at the limit is not
-- declared insolvent and solvent again every minute.
insolvency.RECOVERY_SHARE = 0.05
insolvency.RECOVERY_TICKS = account.INTEREST_TICKS
insolvency.RESTRUCTURED_KIND = "bankruptcy-restructured"
insolvency.DEBT_KIND = "bankruptcy-debt"
-- Ticks over which a force's bankruptcy debt payments share one journal entry.
insolvency.DEBT_MERGE_TICKS = 3600

--- Gives a force state its insolvency fields if it lacks them: `bankruptcies` (a count) and
--- `bankruptcy_debt` (credits); `insolvent_since`, `recovering_since` and `credit_ban_until` (ticks)
--- are nil while they do not apply.
function insolvency.init(state)
  state.bankruptcies = state.bankruptcies or 0
  state.bankruptcy_debt = state.bankruptcy_debt or 0
end

--- Whether a force is insolvent.
function insolvency.insolvent(state)
  return state.insolvent_since ~= nil
end

--- Whether credit (loans and the overdraft) is refused to a force after a bankruptcy.
function insolvency.credit_banned(state)
  return state.credit_ban_until ~= nil
end

--- The available funds an insolvent force must keep for RECOVERY_TICKS to recover.
function insolvency.recovery_margin(state)
  return account.overdraft_limit(state) * insolvency.RECOVERY_SHARE
end

--- The balance an insolvent force must keep for RECOVERY_TICKS to recover.
function insolvency.recovery_balance(state)
  return insolvency.recovery_margin(state) - account.overdraft_limit(state)
end

--- Ticks left at `tick` before an insolvent force goes bankrupt (at least 0), or nil.
function insolvency.grace_left(state, tick)
  if not state.insolvent_since then return nil end
  return math.max(0, state.insolvent_since + insolvency.GRACE_TICKS - tick)
end

--- Ticks left at `tick` of a credit ban's time (at least 0; credit also waits for the bankruptcy
--- debt to be repaid), or nil when credit is not refused.
function insolvency.ban_left(state, tick)
  if not state.credit_ban_until then return nil end
  return math.max(0, state.credit_ban_until - tick)
end

--- The credit ban of a force's `count`-th bankruptcy.
function insolvency.ban_ticks(count)
  return insolvency.BAN_TICKS * 2 ^ (math.min(count, insolvency.MAX_BAN_DOUBLINGS + 1) - 1)
end

--- Takes what the force's positive balance can pay of its bankruptcy debt at `tick` (never into the
--- overdraft), journaled as `bankruptcy-debt`. Returns the credits taken.
function insolvency.collect(state, tick)
  local paid = math.min(state.bankruptcy_debt or 0, math.max(0, state.balance))
  if paid <= 0 then return 0 end
  account.apply(state, -paid, { tick = tick, kind = insolvency.DEBT_KIND, key = "account/bankruptcy",
    merge_ticks = insolvency.DEBT_MERGE_TICKS })
  state.bankruptcy_debt = state.bankruptcy_debt - paid
  return paid
end

-- Ends a force's open contracts at `tick`, in id order: offers are declined, active contracts fail
-- (journaled with nothing back, the guarantee kept). Returns the ids closed and what the force's
-- loans still had to repay.
local function end_contracts(state, tick)
  local ids = {}
  for id in pairs(state.contracts.open) do ids[#ids + 1] = id end
  table.sort(ids)
  local owed = 0
  for _, id in ipairs(ids) do
    local contract = state.contracts.open[id]
    if not contracts.decline(contract, tick) then
      local outcome = contracts.default(contract, tick, 0)
      owed = owed + (outcome.arrears or 0)
      account.apply(state, 0, { tick = tick, kind = "contract-" .. contracts.FAILED, key = "contract/" .. id })
    end
    contracts.close(state, id)
  end
  return ids, owed
end

--- Declares a force bankrupt at `tick`. Returns {name = "bankrupt", debt (what was moved into the
--- bankruptcy debt: a negative balance, the arrears and the installments left on its loans), ban_ticks,
--- contracts (the ids closed, in order)}.
function insolvency.bankrupt(state, tick)
  local ids, loans_owed = end_contracts(state, tick)
  local overdrawn = math.max(0, -state.balance)
  local debt = overdrawn + (state.arrears or 0) + loans_owed
  if debt > 0 then
    account.apply(state, overdrawn, { tick = tick, kind = insolvency.RESTRUCTURED_KIND, key = "account/bankruptcy",
      debt = debt })
  end
  state.arrears = 0
  state.bankruptcy_debt = (state.bankruptcy_debt or 0) + debt
  state.overdraft_low, state.solvency_low = state.balance, state.balance
  state.reputation = reputation.MIN
  state.bankruptcies = (state.bankruptcies or 0) + 1
  local ban = insolvency.ban_ticks(state.bankruptcies)
  state.credit_ban_until = math.max(state.credit_ban_until or 0, tick + ban)
  state.insolvent_since, state.recovering_since = nil, nil
  insolvency.collect(state, tick)
  return { name = "bankrupt", debt = debt, ban_ticks = ban, contracts = ids }
end

-- An insolvent force's check: recovery once the margin held for RECOVERY_TICKS, bankruptcy once the
-- grace has passed in a period that missed it. Returns the event, or nil.
local function check_insolvent(state, tick, lowest, arrears)
  if arrears <= 0 and lowest >= insolvency.recovery_margin(state) then
    state.recovering_since = state.recovering_since or tick
    if tick - state.recovering_since < insolvency.RECOVERY_TICKS then return nil end
    state.insolvent_since, state.recovering_since = nil, nil
    return { name = "recovered" }
  end
  state.recovering_since = nil
  if tick >= state.insolvent_since + insolvency.GRACE_TICKS then return insolvency.bankrupt(state, tick) end
  return nil
end

--- Checks a force at `tick`, once per CHECK_TICKS: takes what it can of its bankruptcy debt, ends a
--- credit ban whose time has passed once that debt is repaid, then starts, ends or concludes its
--- insolvency from its lowest balance since the previous check (`solvency_low`, kept by the account)
--- and its arrears, against the overdraft limit in force now. Starts the next period. Returns the
--- events, in order: tables named "credit-restored", "insolvent", "recovered" or "bankrupt" (see
--- `bankrupt`).
function insolvency.check(state, tick)
  local events = {}
  insolvency.collect(state, tick)
  if state.credit_ban_until and tick >= state.credit_ban_until and (state.bankruptcy_debt or 0) <= 0 then
    state.credit_ban_until = nil
    events[#events + 1] = { name = "credit-restored" }
  end
  local lowest = math.min(state.solvency_low or state.balance, state.balance) + account.overdraft_limit(state)
  state.solvency_low = state.balance
  local arrears = state.arrears or 0
  local event
  if state.insolvent_since then
    event = check_insolvent(state, tick, lowest, arrears)
  elseif lowest < 0 or arrears > account.available(state) then
    state.insolvent_since = tick
    event = { name = "insolvent" }
  end
  events[#events + 1] = event
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
--- earliest insolvency (merging into a fresh force does not restart the clock) with its recovery
--- started afresh, the latest credit ban and the most bankruptcies; bankruptcy debts add up.
function insolvency.merge(destination, source)
  insolvency.init(destination)
  insolvency.init(source)
  destination.insolvent_since = earliest(destination.insolvent_since, source.insolvent_since)
  destination.recovering_since = nil
  destination.credit_ban_until = latest(destination.credit_ban_until, source.credit_ban_until)
  destination.bankruptcies = math.max(destination.bankruptcies, source.bankruptcies)
  destination.bankruptcy_debt = destination.bankruptcy_debt + source.bankruptcy_debt
end

return insolvency
