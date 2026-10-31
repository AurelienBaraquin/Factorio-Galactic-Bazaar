-- Planning of circuit orders (ADR-0011). Pure Lua.
--
-- An order combinator reads its circuit input once per period: each positive normal-quality item
-- or fluid signal asks to buy that many units. Nothing is bought without a positive budget signal: its value
-- caps what the force spends through order combinators in the period (never more than its available
-- funds, overdraft included).
-- An input that carries the balance signal emitted by price combinators is refused whole, since its
-- item signals are prices, not orders.
local orders = {}

--- The buy requests in `signals` (an array of {signal = {type, name, quality}, count}, as the game
--- returns them): {kind, name, units} for each positive item signal of normal quality and each
--- positive fluid signal, sorted by kind and name;
--- the value of the `budget_signal` virtual signal (0 when absent); and whether the
--- `refused_signal` virtual signal is present.
function orders.requests(signals, budget_signal, refused_signal)
  local requests, budget, refused = {}, 0, false
  for _, entry in ipairs(signals or {}) do
    local signal = entry.signal
    local quality = signal.quality or "normal"
    local kind = signal.type or "item"
    if (kind == "item" and quality == "normal" or kind == "fluid") and entry.count > 0 then
      requests[#requests + 1] = { kind = kind, name = signal.name, units = entry.count }
    elseif signal.type == "virtual" and signal.name == budget_signal then
      budget = entry.count
    elseif signal.type == "virtual" and signal.name == refused_signal then
      refused = true
    end
  end
  table.sort(requests, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.name < b.name
  end)
  return requests, budget, refused
end

--- Credits a combinator may still spend: its budget signal minus what its force already spent
--- through order combinators this period, within its available funds; 0 without a positive budget.
function orders.allowance(budget_signal_value, spent, funds)
  if budget_signal_value <= 0 then return 0 end
  return math.max(0, math.min(budget_signal_value - spent, funds))
end

return orders
