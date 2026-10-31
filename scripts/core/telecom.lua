-- Telecommunications levels (ADR-0012). Pure Lua.
--
-- A force's research level sets how fresh the prices it sees are: the Market tab's list and the
-- price combinators show prices at most PERIOD_TICKS[level] old. Level 2 also shows price history
-- and trends. Trades always execute at the live price.
local telecom = {}

-- Ticks a displayed or emitted price may be old, by level (0: no research).
telecom.PERIOD_TICKS = { [0] = 1800, [1] = 600, [2] = 120 }
telecom.MAX_LEVEL = 2
-- Level that shows history and trends.
telecom.HISTORY_LEVEL = 2

local BARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

--- Ticks a price may be old at `level`.
function telecom.period(level)
  return telecom.PERIOD_TICKS[math.max(0, math.min(level, telecom.MAX_LEVEL))]
end

--- Whether `level` shows history and trends.
function telecom.shows_history(level)
  return level >= telecom.HISTORY_LEVEL
end

--- A one-line chart of the last `width` values of `history` (oldest first), scaled between their
--- minimum and maximum; empty for no values, flat bars when they are all equal.
function telecom.sparkline(history, width)
  local first = math.max(1, #history - width + 1)
  local low, high = math.huge, -math.huge
  for i = first, #history do
    low, high = math.min(low, history[i]), math.max(high, history[i])
  end
  local bars = {}
  for i = first, #history do
    local position = high > low and (history[i] - low) / (high - low) or 0.5
    bars[#bars + 1] = BARS[math.floor(position * (#BARS - 1) + 0.5) + 1]
  end
  return table.concat(bars)
end

return telecom
