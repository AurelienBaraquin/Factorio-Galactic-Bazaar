-- Credit account of one force: its balance and a bounded journal of transactions (ADR-0001).
-- Pure Lua: operates on the force's state table from storage.forces.
local reputation = require("scripts.core.reputation")

local account = {}

-- Journal entries kept per force; older ones are dropped.
account.JOURNAL_SIZE = 100

-- Overdraft (ADR-0020): a force may spend down to -limit. Every INTEREST_TICKS, a force whose
-- balance went below zero in the period pays INTEREST_RATE of its deepest debt, counted up to the
-- limit, journaled as one entry per INTEREST_MERGE_TICKS; interest under INTEREST_MIN is waived.
account.BASE_OVERDRAFT_LIMIT = 10000
-- Limits the overdraft research raises it to (#98): at level n (gb-overdraft-n, the highest the force
-- researched, recorded by the adapter in `state.overdraft_level`), OVERDRAFT_LEVEL_LIMITS[n] at
-- reputation 0 and above; below, the extra over the base shrinks with the contract scale (half from
-- -5 down). The base is never scaled.
account.OVERDRAFT_LEVEL_LIMITS = { 25000, 100000 }
account.INTEREST_TICKS = 3600
account.INTEREST_RATE = 0.005
account.INTEREST_MIN = 0.005
account.INTEREST_MERGE_TICKS = 36000
account.INTEREST_KIND = "overdraft-interest"

--- Gives a force state its account fields if it lacks them (new force, or a save made before the
--- account, the overdraft or insolvency existed). `overdraft_low` is the lowest balance since the last
--- interest charge, `solvency_low` the lowest since the last insolvency check (ADR-0022).
function account.init(state)
  state.balance = state.balance or 0
  state.journal = state.journal or {}
  state.overdraft_low = state.overdraft_low or state.balance
  state.solvency_low = state.solvency_low or state.balance
end

--- The overdraft limit of a force: how far below zero its balance may go by spending. None while
--- credit is refused after a bankruptcy (`credit_ban_until`, ADR-0022, which lasts until the
--- bankruptcy debt is repaid). Otherwise the base limit at research level 0 (also when
--- `overdraft_level` is absent), the highest level's beyond the last; a level's extra over the base is
--- scaled by the reputation's contract scale, at most 1.
function account.overdraft_limit(state)
  if state.credit_ban_until then return 0 end
  local level = math.min(state.overdraft_level or 0, #account.OVERDRAFT_LEVEL_LIMITS)
  local limit = account.OVERDRAFT_LEVEL_LIMITS[level]
  if not limit then return account.BASE_OVERDRAFT_LIMIT end
  local scale = math.min(1, reputation.contract_scale(state.reputation or 0))
  return account.BASE_OVERDRAFT_LIMIT + (limit - account.BASE_OVERDRAFT_LIMIT) * scale
end

--- The funds a force can spend now: its balance plus its overdraft limit. Every check of a purchase,
--- guarantee, deposit or charge compares its cost to this, never to the balance alone. Negative when
--- interest has pushed the balance beyond the limit.
function account.available(state)
  return state.balance + account.overdraft_limit(state)
end

--- The part of the overdraft a force can still draw on, between 0 and its limit.
function account.overdraft_left(state)
  local limit = account.overdraft_limit(state)
  return math.max(0, math.min(limit, account.available(state)))
end

local function is_finite(n)
  return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The position of the entry a recurring transaction merges into: same kind and key, also mergeable,
-- and started less than `merge_ticks` before it. The whole journal is searched (JOURNAL_SIZE entries
-- at most), so any number of recurring transactions keep merging.
local function merge_target(journal, entry)
  for i = #journal, 1, -1 do
    local candidate = journal[i]
    if candidate.merge_ticks and candidate.kind == entry.kind and candidate.key == entry.key
      and entry.tick - candidate.first_tick < entry.merge_ticks then
      return i
    end
  end
  return nil
end

-- Adds `amount` to the balance and records `entry`, without any check.
local function record(state, amount, entry)
  local balance = state.balance + amount
  state.overdraft_low = math.min(state.overdraft_low or state.balance, balance)
  state.solvency_low = math.min(state.solvency_low or state.balance, balance)
  local journal = state.journal
  local position = entry.merge_ticks and merge_target(journal, entry)
  state.balance = balance
  if position then
    local target = table.remove(journal, position)
    journal[#journal + 1] = target
    target.amount = target.amount + amount
    target.quantity = (target.quantity or 0) + (entry.quantity or 0)
    target.tick = entry.tick
    target.balance = balance
    return
  end
  entry.amount = amount
  entry.balance = balance
  entry.first_tick = entry.merge_ticks and entry.tick or nil
  journal[#journal + 1] = entry
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
end

--- Adds `amount` credits (negative to spend) and records `entry` (a plain table, e.g.
--- {tick, kind, key, quantity}) with the amount and the resulting balance. A debit may take the
--- balance below zero down to the overdraft limit, no further; a credit is always accepted. An entry
--- with `merge_ticks` (a recurring transaction, such as power settlements) is added to a recent entry
--- of the same kind and key started less than `merge_ticks` before, which then holds the totals, its
--- last tick and the balance after it, and moves to the end so the journal stays in tick order.
--- Atomic: when it refuses (`invalid-amount`, `insufficient-funds`), the state is unchanged.
function account.apply(state, amount, entry)
  if not is_finite(amount) then return false, "invalid-amount" end
  if amount < 0 and amount + account.available(state) < 0 then return false, "insufficient-funds" end
  record(state, amount, entry)
  return true
end

--- Charges a force one period of interest at `tick`, on the lowest balance it had since the last
--- charge (a debt repaid within the period still pays), the debt counted up to the overdraft limit so
--- that a debt beyond it grows linearly, not without bound, until the force recovers or goes bankrupt
--- (ADR-0022). The charge may take the balance beyond the limit. Starts the next period. Returns the
--- credits charged (0 when none).
function account.charge_interest(state, tick)
  local low = math.min(state.overdraft_low or state.balance, state.balance)
  state.overdraft_low = state.balance
  if low >= 0 then return 0 end
  local interest = math.min(-low, account.overdraft_limit(state)) * account.INTEREST_RATE
  if interest < account.INTEREST_MIN then return 0 end
  record(state, -interest, {
    tick = tick, kind = account.INTEREST_KIND, key = "account/overdraft", merge_ticks = account.INTEREST_MERGE_TICKS,
  })
  state.overdraft_low = state.balance
  return interest
end

--- Folds `source` into `destination` when two forces merge: balances add up, and so do the lowest
--- balances of the period (each debt still pays its interest, and still counts towards insolvency);
--- journals are joined in tick order and trimmed to the newest entries.
function account.merge(destination, source)
  destination.overdraft_low = (destination.overdraft_low or destination.balance)
    + (source.overdraft_low or source.balance)
  destination.solvency_low = (destination.solvency_low or destination.balance)
    + (source.solvency_low or source.balance)
  destination.balance = destination.balance + source.balance
  local journal = destination.journal
  for _, entry in ipairs(source.journal) do journal[#journal + 1] = entry end
  table.sort(journal, function(a, b) return (a.tick or 0) < (b.tick or 0) end)
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
end

return account
