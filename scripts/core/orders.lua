-- Planning of circuit orders (ADR-0011). Pure Lua.
--
-- An order combinator reads its circuit input once per period: each positive normal-quality item
-- signal asks to buy that many units. Spending per period is capped by a budget: the value of the
-- budget signal when present and positive, otherwise BUDGET_SHARE of the balance, never more than
-- the balance.
local orders = {}

orders.BUDGET_SHARE = 0.1

--- The buy requests in `signals` (an array of {signal = {type, name, quality}, count}, as the game
--- returns them): {name, units} for each positive item signal of normal quality, sorted by name; and
--- the value of the `budget_signal` virtual signal (0 when absent).
function orders.requests(signals, budget_signal)
  local requests, budget = {}, 0
  for _, entry in ipairs(signals or {}) do
    local signal = entry.signal
    local quality = signal.quality or "normal"
    if (signal.type or "item") == "item" and quality == "normal" and entry.count > 0 then
      requests[#requests + 1] = { name = signal.name, units = entry.count }
    elseif signal.type == "virtual" and signal.name == budget_signal then
      budget = entry.count
    end
  end
  table.sort(requests, function(a, b) return a.name < b.name end)
  return requests, budget
end

--- Credits an order combinator may spend this period.
function orders.budget(balance, budget_signal_value)
  local cap = budget_signal_value > 0 and budget_signal_value or orders.BUDGET_SHARE * balance
  return math.max(0, math.min(balance, cap))
end

return orders
