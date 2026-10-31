-- The account statement of the central window's Statement tab (#108). Pure Lua, on a force's state
-- from storage.forces:
-- - it tells, for each journal entry (scripts/core/account.lua), its label and category and what it
--   was about, and which entries a page of the tab shows;
-- - it keeps the force's ledger (`state.ledger`): the income, spending and number of transactions of
--   each category, since records began and per minute of game time over the last hour, so that the
--   totals of a period cost the same whatever the journal holds. account.lua records every
--   transaction in it.
local catalog = require("scripts.core.catalog")
local quality = require("scripts.core.quality")

local statement = {}

-- Rows of the journal shown per page.
statement.PAGE_SIZE = 12

-- Categories, in display order; the filter ALL shows every one.
statement.CATEGORIES = {
  "sales", "purchases", "freight", "power", "contracts", "loans", "interest", "bankruptcy", "other",
}
statement.ALL = "all"

-- The ledger counts by minutes of game time and keeps the last LEDGER_MINUTES of them.
statement.MINUTE_TICKS = 3600
statement.LEDGER_MINUTES = 60

-- Periods the totals can cover, in display order: the current minute and the `minutes` - 1 before
-- it, or everything since the ledger began.
statement.PERIODS = {
  { name = "ten-minutes", minutes = 10 },
  { name = "hour", minutes = statement.LEDGER_MINUTES },
  { name = "all" },
}

-- Labels of journal entries, in display order, and the category of each. A label is the entry's
-- `kind`, except purchases and sales of electricity (`power-buy`, `power-sell`) and unknown kinds
-- (`other`). Contract kinds are in "contracts" unless the entry is a loan's (`statement.category`).
statement.LABELS = {
  "sell", "buy", "freight", "freight-refund", "power-sell", "power-buy",
  "contract-guarantee", "contract-installment", "contract-charge", "contract-fulfilled", "contract-failed",
  "contract-voided", "contract-advance", "contract-repaid", "loan-arrears",
  "overdraft-interest", "bankruptcy-restructured", "bankruptcy-debt", "other",
}
statement.LABEL_CATEGORY = {
  sell = "sales", buy = "purchases",
  freight = "freight", ["freight-refund"] = "freight",
  ["power-sell"] = "power", ["power-buy"] = "power",
  ["contract-guarantee"] = "contracts", ["contract-installment"] = "contracts", ["contract-charge"] = "contracts",
  ["contract-fulfilled"] = "contracts", ["contract-failed"] = "contracts", ["contract-voided"] = "contracts",
  ["contract-advance"] = "loans", ["contract-repaid"] = "loans", ["loan-arrears"] = "loans",
  ["overdraft-interest"] = "interest",
  ["bankruptcy-restructured"] = "bankruptcy", ["bankruptcy-debt"] = "bankruptcy",
  other = "other",
}

local POWER_LABEL = { buy = "power-buy", sell = "power-sell" }

local function is_energy(key)
  return type(key) == "string" and key:find("energy/", 1, true) == 1
end

--- The label of a journal entry (one of LABELS).
function statement.label(entry)
  local kind = entry.kind
  if POWER_LABEL[kind] and is_energy(entry.key) then return POWER_LABEL[kind] end
  return statement.LABEL_CATEGORY[kind] and kind or "other"
end

--- The category of a journal entry (one of CATEGORIES): its label's, except that a contract entry of
--- a loan (`contract_kind` "loan") is in "loans".
function statement.category(entry)
  local kind = entry.kind
  local category = statement.LABEL_CATEGORY[kind]
  if not category then return "other" end
  if POWER_LABEL[kind] and is_energy(entry.key) then return "power" end
  if category == "contracts" and entry.contract_kind == "loan" then return "loans" end
  return category
end

--- What a journal entry was about, from its key: {type = "item"|"fluid"|"energy", name, quality} for
--- goods, {type = "contract", id, contract_kind} for a contract, nil for the account itself.
function statement.subject(entry)
  local key = entry.key
  if type(key) ~= "string" then return nil end
  local id = key:match("^contract/(%d+)$")
  if id then return { type = "contract", id = tonumber(id), contract_kind = entry.contract_kind } end
  local base_key, quality_name = quality.split(key)
  local kind, name = base_key:match("^(%a+)/(.+)$")
  if kind == "item" or kind == "fluid" or kind == "energy" then
    return { type = kind, name = name, quality = quality_name }
  end
  return nil
end

local function known_filter(filter)
  for _, category in ipairs(statement.CATEGORIES) do
    if category == filter then return true end
  end
  return false
end

--- Page `page` of the journal entries of `filter` (a category, or ALL; an unknown one counts as
--- ALL), newest first: {entries (at most PAGE_SIZE, the journal's own tables), page (clamped into
--- range), pages (at least 1), count (entries in the filter)}. An entry's category is the one
--- account.lua recorded on it (`category`), computed for entries of older saves.
function statement.page(journal, filter, page)
  local positions
  if known_filter(filter) then
    positions = {}
    for i = #journal, 1, -1 do
      local entry = journal[i]
      if (entry.category or statement.category(entry)) == filter then positions[#positions + 1] = i end
    end
  end
  local count = positions and #positions or #journal
  local pages = math.max(1, math.ceil(count / statement.PAGE_SIZE))
  page = math.max(1, math.min(pages, math.floor(tonumber(page) or 1)))
  local entries = {}
  for rank = (page - 1) * statement.PAGE_SIZE + 1, math.min(count, page * statement.PAGE_SIZE) do
    entries[#entries + 1] = journal[positions and positions[rank] or #journal + 1 - rank]
  end
  return { entries = entries, page = page, pages = pages, count = count }
end

-- Adds a transaction of `amount` to the sums of `category` in `sums` ({[category] = {income,
-- spending, count}}).
local function add(sums, category, amount)
  local sum = sums[category]
  if not sum then
    sum = { income = 0, spending = 0, count = 0 }
    sums[category] = sum
  end
  if amount > 0 then sum.income = sum.income + amount else sum.spending = sum.spending - amount end
  sum.count = sum.count + 1
end

-- Adds every sum of `from` to `into`.
local function add_all(into, from)
  for category, sum in pairs(from) do
    local target = into[category]
    if not target then
      target = { income = 0, spending = 0, count = 0 }
      into[category] = target
    end
    target.income, target.spending = target.income + sum.income, target.spending + sum.spending
    target.count = target.count + sum.count
  end
end

--- Records a transaction of `amount` described by journal entry `entry` (its `tick`, `kind`, `key`,
--- `contract_kind`) in the force's ledger, created at the transaction's tick when the force has none
--- (a new force, or a save from before #108): {start_tick, total = sums since start_tick, minutes =
--- {[minute of game time] = sums}}, sums being {[category] = {income, spending, count}}. Minutes
--- older than LEDGER_MINUTES are dropped when a new minute begins. Returns the entry's category.
function statement.record(state, entry, amount)
  local tick = entry.tick or 0
  local ledger = state.ledger
  if not ledger then
    ledger = { start_tick = tick, total = {}, minutes = {} }
    state.ledger = ledger
  end
  local category = statement.category(entry)
  add(ledger.total, category, amount)
  local minute = math.floor(tick / statement.MINUTE_TICKS)
  local minutes = ledger.minutes
  if not minutes[minute] then
    for old in pairs(minutes) do
      if old <= minute - statement.LEDGER_MINUTES then minutes[old] = nil end
    end
    minutes[minute] = {}
  end
  add(minutes[minute], category, amount)
  return category
end

--- Folds the ledger of `source` into the one of `destination` when two forces merge: sums add up,
--- minute by minute, and records begin at the earlier start.
function statement.merge_ledger(destination, source)
  local from, into = source.ledger, destination.ledger
  if not from then return end
  if not into then
    destination.ledger = from
    return
  end
  into.start_tick = math.min(into.start_tick, from.start_tick)
  add_all(into.total, from.total)
  for minute, sums in pairs(from.minutes) do
    into.minutes[minute] = into.minutes[minute] or {}
    add_all(into.minutes[minute], sums)
  end
end

--- The totals of period `period` (a name of PERIODS; an unknown one counts as "all") at `tick`, from a
--- force's ledger (nil before its first transaction): {categories = {[category] = {income, spending,
--- net, count}} for every category, all (the same over every category), since_tick (the first tick
--- the totals cover: the period's first minute, or the ledger's start when later; nil without a
--- ledger)}. A period of n minutes counts by whole minutes of game time: the current one and the
--- n - 1 before it.
function statement.totals(ledger, period, tick)
  local categories, all = {}, { income = 0, spending = 0, net = 0, count = 0 }
  for _, category in ipairs(statement.CATEGORIES) do
    categories[category] = { income = 0, spending = 0, net = 0, count = 0 }
  end
  local minutes
  for _, known in ipairs(statement.PERIODS) do
    if known.name == period then minutes = known.minutes end
  end
  local since_tick
  if ledger and minutes then
    local first = math.floor(tick / statement.MINUTE_TICKS) - minutes + 1
    for minute, sums in pairs(ledger.minutes) do
      if minute >= first then add_all(categories, sums) end
    end
    since_tick = math.max(first * statement.MINUTE_TICKS, ledger.start_tick)
  elseif ledger then
    add_all(categories, ledger.total)
    since_tick = ledger.start_tick
  end
  for _, total in pairs(categories) do
    total.net = total.income - total.spending
    all.income, all.spending, all.count = all.income + total.income, all.spending + total.spending,
      all.count + total.count
  end
  all.net = all.income - all.spending
  return { categories = categories, all = all, since_tick = since_tick }
end

--- A map tick as game time, "h:mm:ss" (whole seconds; a negative tick as 0:00:00).
function statement.format_time(tick)
  local seconds = math.max(0, math.floor(tick / 60))
  return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

--- A credit amount as short text (catalog.format_credits) in rich-text green when received, red when
--- paid, plain when 0: one caption to write, where a colour would take a second write to the style.
function statement.format_signed(amount)
  local text = catalog.format_credits(amount)
  if amount > 0 then return "[color=0.5,1,0.5]" .. text .. "[/color]" end
  if amount < 0 then return "[color=1,0.5,0.4]" .. text .. "[/color]" end
  return text
end

--- A journal quantity as short text: whole numbers in full below 1000, then like credits ("1.00k");
--- fractions (fluids, energy) with decimals; "" without a quantity.
function statement.format_quantity(quantity)
  if type(quantity) ~= "number" then return "" end
  if quantity % 1 == 0 and math.abs(quantity) < 1000 then return string.format("%d", quantity) end
  return catalog.format_credits(quantity)
end

return statement
