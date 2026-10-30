-- What the market interface lists and how it shows numbers: search, pages, price trend and credit
-- formatting. Pure Lua.
local catalog = {}

-- Rows on one page of the market list; also the most keys the interface reads at once (ADR-0004).
catalog.PAGE_SIZE = 15
-- Relative change between the oldest and newest price samples under which a price counts as flat.
catalog.FLAT_TREND = 0.01

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

local SUFFIXES = { { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } }

--- A credit amount as short text: 2 decimals below 1000, then k / M / G / T with 3 significant
--- digits ("0.42", "999.99", "1.23k", "45.6M").
function catalog.format_credits(amount)
  local sign = amount < 0 and "-" or ""
  local value = math.abs(amount)
  for _, suffix in ipairs(SUFFIXES) do
    if value >= suffix[1] then
      local scaled = value / suffix[1]
      local decimals = scaled >= 100 and 0 or scaled >= 10 and 1 or 2
      return sign .. string.format("%." .. decimals .. "f", scaled) .. suffix[2]
    end
  end
  return sign .. string.format("%.2f", value)
end

--- A whole quantity typed by the player: a positive integer, or nil.
function catalog.parse_quantity(text)
  local n = tonumber(text)
  if not n or n ~= n or n < 1 or n == math.huge then return nil end
  return math.floor(n)
end

return catalog
