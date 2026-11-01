-- Credit account of one force: its balance and a bounded journal of transactions (ADR-0001).
-- Pure Lua: operates on the force's state table from storage.forces.
local reputation = require("scripts.core.reputation")
local statement = require("scripts.core.statement")

local account = {}

-- Journal entries kept per force; older ones are dropped. Sized for the Statement tab (#108), whose
-- totals come from the ledger instead: about 7 minutes of a base trading 40 goods automatically and
-- buying twice a minute, far longer for a smaller one (docs/data-model.md).
account.JOURNAL_SIZE = 500

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
-- Bankruptcy debt (ADR-0022): what a bankrupt force still owes, taken from its positive balance at
-- every credit, journaled as one entry per DEBT_MERGE_TICKS.
account.DEBT_KIND = "bankruptcy-debt"
account.DEBT_MERGE_TICKS = 3600

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

local function merge_id(entry)
  return tostring(entry.kind) .. "\n" .. tostring(entry.key)
end

-- The index of the journal's recurring entries (`state.journal_index`): {journal = the journal table
-- it indexes, entries = {[merge_id] = the last entry of that kind and key in the journal}}. Kept by
-- `record`; rebuilt from the journal when missing (a save from 0.1.35 or older, a merge of forces) or
-- made for another journal table (one replaced whole).
local function journal_index(state)
  local index = state.journal_index
  if index and index.journal == state.journal then return index end
  local entries = {}
  for _, entry in ipairs(state.journal) do
    if entry.merge_ticks then entries[merge_id(entry)] = entry end
  end
  index = { journal = state.journal, entries = entries }
  state.journal_index = index
  return index
end

local function is_open(candidate, entry)
  return candidate.merge_ticks and candidate.kind == entry.kind and candidate.key == entry.key
    and entry.tick - candidate.first_tick < entry.merge_ticks
end

-- The position of the entry a recurring transaction (of merge_id `id`) merges into: the last entry of
-- the journal of the same kind and key started less than `merge_ticks` before it. The last one of that
-- kind and key comes from the index and is found by identity from the end of the journal, where
-- recurring entries move, without comparing the fields of each entry. Only when it is no longer open
-- are the entries before it searched, as an earlier one may still be (after forces merged, journals
-- joined in tick order). An index whose entry the journal no longer holds is rebuilt once.
local function merge_target(state, entry, id)
  for _ = 1, 2 do
    local candidate = journal_index(state).entries[id]
    if not candidate then return nil end
    local journal = state.journal
    for i = #journal, 1, -1 do
      if journal[i] == candidate then
        if is_open(candidate, entry) then return i end
        for j = i - 1, 1, -1 do
          if is_open(journal[j], entry) then return j end
        end
        return nil
      end
    end
    state.journal_index = nil
  end
  return nil
end

-- Adds `amount` to the balance and records `entry`, without any check.
local function record(state, amount, entry)
  local balance = state.balance + amount
  state.overdraft_low = math.min(state.overdraft_low or state.balance, balance)
  state.solvency_low = math.min(state.solvency_low or state.balance, balance)
  local journal = state.journal
  local id = entry.merge_ticks and merge_id(entry)
  local position = id and merge_target(state, entry, id)
  state.balance = balance
  local category = statement.record(state, entry, amount)
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
  entry.category = category
  entry.first_tick = id and entry.tick or nil
  journal[#journal + 1] = entry
  local entries = journal_index(state).entries
  if id then entries[id] = entry end
  while #journal > account.JOURNAL_SIZE do
    local dropped = table.remove(journal, 1)
    if dropped.merge_ticks and entries[merge_id(dropped)] == dropped then entries[merge_id(dropped)] = nil end
  end
end

--- Adds `amount` credits (negative to spend) and records `entry` (a plain table, e.g.
--- {tick, kind, key, quantity}) with the amount, the resulting balance and its statement category,
--- and counts the transaction in the force's ledger (scripts/core/statement.lua). A debit may take the
--- balance below zero down to the overdraft limit, no further; a credit is always accepted. An entry
--- with `merge_ticks` (a recurring transaction, such as power settlements) is added to a recent entry
--- of the same kind and key started less than `merge_ticks` before, which then holds the totals, its
--- last tick and the balance after it, and moves to the end so the journal stays in tick order.
--- Atomic: when it refuses (`invalid-amount`, `insufficient-funds`), the state is unchanged. A credit
--- to a force that owes a bankruptcy debt goes to that debt first, as far as the balance is positive
--- (`repay_debt`), so income cannot be spent before the debt is paid.
function account.apply(state, amount, entry)
  if not is_finite(amount) then return false, "invalid-amount" end
  if amount < 0 and amount + account.available(state) < 0 then return false, "insufficient-funds" end
  record(state, amount, entry)
  if amount > 0 then account.repay_debt(state, entry.tick) end
  return true
end

--- Takes what a force's positive balance can pay of its bankruptcy debt (`bankruptcy_debt`) at
--- `tick`, never into the overdraft, journaled as `bankruptcy-debt`. Returns the credits taken.
function account.repay_debt(state, tick)
  local paid = math.min(state.bankruptcy_debt or 0, math.max(0, state.balance))
  if paid <= 0 then return 0 end
  record(state, -paid, { tick = tick, kind = account.DEBT_KIND, key = "account/bankruptcy",
    merge_ticks = account.DEBT_MERGE_TICKS })
  state.bankruptcy_debt = state.bankruptcy_debt - paid
  return paid
end

--- The interest a charge would take now, without changing anything: INTEREST_RATE of the lowest
--- balance since the last charge (a debt repaid within the period still pays), the debt counted up to
--- the overdraft limit; 0 without debt in the period or under INTEREST_MIN.
function account.interest_due(state)
  local low = math.min(state.overdraft_low or state.balance, state.balance)
  if low >= 0 then return 0 end
  local interest = math.min(-low, account.overdraft_limit(state)) * account.INTEREST_RATE
  if interest < account.INTEREST_MIN then return 0 end
  return interest
end

--- Charges a force one period of interest at `tick` (`interest_due`); counting the debt up to the
--- overdraft limit makes a debt beyond it grow linearly, not without bound, until the force recovers
--- or goes bankrupt (ADR-0022). The charge may take the balance beyond the limit. Starts the next
--- period. Returns the credits charged (0 when none).
function account.charge_interest(state, tick)
  local interest = account.interest_due(state)
  state.overdraft_low = state.balance
  if interest <= 0 then return 0 end
  record(state, -interest, {
    tick = tick, kind = account.INTEREST_KIND, key = "account/overdraft", merge_ticks = account.INTEREST_MERGE_TICKS,
  })
  state.overdraft_low = state.balance
  return interest
end

--- Folds `source` into `destination` when two forces merge: balances add up, and so do the lowest
--- balances of the period (each debt still pays its interest, and still counts towards insolvency);
--- journals are joined in tick order and trimmed to the newest entries (the destination's journal index
--- is dropped, rebuilt at its next transaction), and ledgers are folded together.
function account.merge(destination, source)
  destination.overdraft_low = (destination.overdraft_low or destination.balance)
    + (source.overdraft_low or source.balance)
  destination.solvency_low = (destination.solvency_low or destination.balance)
    + (source.solvency_low or source.balance)
  destination.balance = destination.balance + source.balance
  statement.merge_ledger(destination, source)
  local journal = destination.journal
  for _, entry in ipairs(source.journal) do journal[#journal + 1] = entry end
  table.sort(journal, function(a, b) return (a.tick or 0) < (b.tick or 0) end)
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
  destination.journal_index = nil
end

return account
