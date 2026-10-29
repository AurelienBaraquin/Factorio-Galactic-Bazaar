-- Credit account of one force: its balance and a bounded journal of transactions (ADR-0001).
-- Pure Lua: operates on the force's state table from storage.forces.
local account = {}

-- Journal entries kept per force; older ones are dropped.
account.JOURNAL_SIZE = 100

--- Gives a force state its account fields if it lacks them (new force, or a save made before the
--- account existed).
function account.init(state)
  state.balance = state.balance or 0
  state.journal = state.journal or {}
end

local function is_finite(n)
  return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

--- Adds `amount` credits (negative to spend) and records `entry` (a plain table, e.g.
--- {tick, kind, key, quantity}) with the amount and the resulting balance. Atomic: when it refuses
--- (`invalid-amount`, `insufficient-funds`), the state is unchanged.
function account.apply(state, amount, entry)
  if not is_finite(amount) then return false, "invalid-amount" end
  local balance = state.balance + amount
  if balance < 0 then return false, "insufficient-funds" end
  local journal = state.journal
  entry.amount = amount
  entry.balance = balance
  journal[#journal + 1] = entry
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
  state.balance = balance
  return true
end

--- Folds `source` into `destination` when two forces merge: balances add up, journals are joined
--- in tick order and trimmed to the newest entries.
function account.merge(destination, source)
  destination.balance = destination.balance + source.balance
  local journal = destination.journal
  for _, entry in ipairs(source.journal) do journal[#journal + 1] = entry end
  table.sort(journal, function(a, b) return (a.tick or 0) < (b.tick or 0) end)
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
end

return account
