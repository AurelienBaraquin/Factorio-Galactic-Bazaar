-- What the market interface lists and how it shows numbers: search, pages, price trend, credit and
-- duration formatting. Pure Lua.
local catalog = {}

-- Rows on one page of the market list; also the most keys the interface reads at once (ADR-0004).
catalog.PAGE_SIZE = 15
-- Relative change between the oldest and newest price samples under which a price counts as flat.
catalog.FLAT_TREND = 0.01
-- Largest quantity a player can type for one trade.
catalog.MAX_QUANTITY = 1e9

local function normalise(text)
  return (text:lower():gsub("[%s_]", "-"))
end

--- The names (sorted) that contain every word of `filter` (case and separators ignored).
function catalog.search(names, filter)
  local words = {}
  for word in normalise(filter or ""):gmatch("[^%-]+") do words[#words + 1] = word end
  local found = {}
  for _, name in ipairs(names) do
    local text = normalise(name)
    local match = true
    for _, word in ipairs(words) do
      if not text:find(word, 1, true) then
        match = false
        break
      end
    end
    if match then found[#found + 1] = name end
  end
  table.sort(found)
  return found
end

--- One page of `names`: {names = slice, page, pages}, with `page` clamped to the existing pages.
function catalog.page(names, page)
  local pages = math.max(1, math.ceil(#names / catalog.PAGE_SIZE))
  page = math.max(1, math.min(math.floor(page or 1), pages))
  local slice = {}
  for i = (page - 1) * catalog.PAGE_SIZE + 1, math.min(page * catalog.PAGE_SIZE, #names) do
    slice[#slice + 1] = names[i]
  end
  return { names = slice, page = page, pages = pages }
end

--- "up", "down" or "flat", from the oldest to the newest sample of a price history.
function catalog.trend(history)
  local first, last = history[1], history[#history]
  if not (first and last) or first <= 0 then return "flat" end
  local change = (last - first) / first
  if change > catalog.FLAT_TREND then return "up" end
  if change < -catalog.FLAT_TREND then return "down" end
  return "flat"
end

local UNITS = { { 1, "" }, { 1e3, "k" }, { 1e6, "M" }, { 1e9, "G" }, { 1e12, "T" } }

-- `scaled` with 3 significant digits (2 decimals under 10, 1 under 100, none above).
local function round_short(scaled)
  local decimals = scaled >= 99.95 and 0 or scaled >= 9.995 and 1 or 2
  return string.format("%." .. decimals .. "f", scaled), decimals
end

--- A duration in ticks as "m:ss" (whole seconds, at least 0:00).
function catalog.format_duration(ticks)
  local seconds = math.max(0, math.floor(ticks / 60))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

--- A credit amount as short text: 2 decimals below 1000, then k / M / G / T with 3 significant
--- digits ("0.42", "999.99", "1.23k", "45.6M"). A value that rounds up to 1000 of a unit is shown
--- in the next one ("1.00k", not "1000.00").
function catalog.format_credits(amount)
  if amount ~= amount then return "?" end
  if amount == math.huge then return "∞" end
  if amount == -math.huge then return "-∞" end
  if math.abs(amount) < 0.005 then amount = 0 end
  local sign = amount < 0 and "-" or ""
  local value = math.abs(amount)
  for i = #UNITS, 1, -1 do
    local unit = UNITS[i]
    if value >= unit[1] or i == 1 then
      local scaled = value / unit[1]
      local text = i == 1 and string.format("%.2f", scaled) or round_short(scaled)
      if tonumber(text) >= 1000 and UNITS[i + 1] then
        return sign .. (round_short(value / UNITS[i + 1][1])) .. UNITS[i + 1][2]
      end
      return sign .. text .. unit[2]
    end
  end
end

--- A whole quantity typed by the player: a positive integer up to MAX_QUANTITY, or nil.
function catalog.parse_quantity(text)
  local n = tonumber(text)
  if not n or n ~= n or n < 1 or n > catalog.MAX_QUANTITY then return nil end
  return math.floor(n)
end

return catalog
