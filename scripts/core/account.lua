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

-- Recent entries searched for one to merge a recurring transaction into.
account.MERGE_WINDOW = 4

-- The recent entry a recurring transaction merges into: same kind and key, also mergeable, and
-- started less than `merge_ticks` before it.
local function merge_target(journal, entry)
  for i = #journal, math.max(1, #journal - account.MERGE_WINDOW + 1), -1 do
    local candidate = journal[i]
    if candidate.merge_ticks and candidate.kind == entry.kind and candidate.key == entry.key
      and entry.tick - candidate.first_tick < entry.merge_ticks then
      return candidate
    end
  end
  return nil
end

--- Adds `amount` credits (negative to spend) and records `entry` (a plain table, e.g.
--- {tick, kind, key, quantity}) with the amount and the resulting balance. An entry with
--- `merge_ticks` (a recurring transaction, such as power settlements) is added to a recent entry of
--- the same kind and key started less than `merge_ticks` before, which then holds the totals, its
--- last tick and the balance after it. Atomic: when it refuses (`invalid-amount`,
--- `insufficient-funds`), the state is unchanged.
function account.apply(state, amount, entry)
  if not is_finite(amount) then return false, "invalid-amount" end
  local balance = state.balance + amount
  if balance < 0 then return false, "insufficient-funds" end
  local journal = state.journal
  local target = entry.merge_ticks and merge_target(journal, entry)
  state.balance = balance
  if target then
    target.amount = target.amount + amount
    target.quantity = (target.quantity or 0) + (entry.quantity or 0)
    target.tick = entry.tick
    target.balance = balance
    return true
  end
  entry.amount = amount
  entry.balance = balance
  entry.first_tick = entry.merge_ticks and entry.tick or nil
  journal[#journal + 1] = entry
  while #journal > account.JOURNAL_SIZE do table.remove(journal, 1) end
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
