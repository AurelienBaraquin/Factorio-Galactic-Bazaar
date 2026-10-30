-- Planning of circuit orders (ADR-0011). Pure Lua.
--
-- An order combinator reads its circuit input once per period: each positive normal-quality item
-- signal asks to buy that many units. Nothing is bought without a positive budget signal: its value
-- caps what the force spends through order combinators in the period (never more than the balance).
-- An input that carries the balance signal emitted by price combinators is refused whole, since its
-- item signals are prices, not orders.
local orders = {}

--- The buy requests in `signals` (an array of {signal = {type, name, quality}, count}, as the game
--- returns them): {name, units} for each positive item signal of normal quality, sorted by name;
--- the value of the `budget_signal` virtual signal (0 when absent); and whether the
--- `refused_signal` virtual signal is present.
function orders.requests(signals, budget_signal, refused_signal)
  local requests, budget, refused = {}, 0, false
  for _, entry in ipairs(signals or {}) do
    local signal = entry.signal
    local quality = signal.quality or "normal"
    if (signal.type or "item") == "item" and quality == "normal" and entry.count > 0 then
      requests[#requests + 1] = { name = signal.name, units = entry.count }
    elseif signal.type == "virtual" and signal.name == budget_signal then
      budget = entry.count
    elseif signal.type == "virtual" and signal.name == refused_signal then
      refused = true
    end
  end
  table.sort(requests, function(a, b) return a.name < b.name end)
  return requests, budget, refused
end

--- Credits a combinator may still spend: its budget signal minus what its force already spent
--- through order combinators this period, within the balance; 0 without a positive budget.
function orders.allowance(budget_signal_value, spent, balance)
  if budget_signal_value <= 0 then return 0 end
  return math.max(0, math.min(budget_signal_value - spent, balance))
end

return orders
