-- Notifications (#107): which kinds of event a force is told of, and how often. Pure Lua: the
-- adapter (scripts/notifications.lua) keeps one throttle log per force in storage and shows what this
-- module admits. A kind with a period is told at most once per period for each group (a hub, a
-- contract, a kind of offer); a kind without one is told every time, its events being rare or
-- bounded (state changes, the Contracts tab's rows). An event may stand for a count (shipments,
-- offers): the counts of throttled events are carried to the next event told for that group, so the
-- number told is always true.
local contracts = require("scripts.core.contracts")

local notifications = {}

-- Ticks before a contract's deadline at which an incomplete one is said to be due soon.
notifications.DUE_SOON_TICKS = 3600 * 2

-- What a player can turn off, each category one per-user setting.
notifications.CATEGORIES = {
  contracts = "gb-notify-contracts",
  deliveries = "gb-notify-deliveries",
  finance = "gb-notify-finance",
  market = "gb-notify-market",
}

local WARNING = { r = 1, g = 0.4, b = 0.3 }
local GOOD = { r = 0.4, g = 1, b = 0.4 }

local function virtual(name) return { type = "virtual", name = name } end

-- Each kind: its category, its alert icon (a SignalID, one per kind), its period in ticks (0: none),
-- and, when it also prints to the chat, the locale key of that line and its colour; with
-- `chat_always`, that line is printed even to players who turned the category off (the setting then
-- hides only the alert). The alert's message is "gb-notify.<kind>".
notifications.KINDS = {
  ["contract-offer"] = { category = "contracts", icon = virtual("signal-info"), period = 3600,
    chat = "gb-notify.contract-offer-chat" },
  -- Grouped by contract, with a period that outlasts the warning time: told once per contract.
  ["contract-due"] = { category = "contracts", icon = virtual("signal-hourglass"),
    period = notifications.DUE_SOON_TICKS + 3600, chat = "gb-notify.contract-due-chat", color = WARNING },
  ["contract-fulfilled"] = { category = "contracts", icon = virtual("signal-check"), period = 0,
    chat = "gb-notify.contract-fulfilled-chat", color = GOOD },
  ["contract-failed"] = { category = "contracts", icon = virtual("signal-deny"), period = 0,
    chat = "gb-notify.contract-failed-chat", color = WARNING },
  ["delivery-landed"] = { category = "deliveries", icon = { type = "item", name = "gb-hub" }, period = 1800 },
  ["loan-defaulted"] = { category = "finance", icon = virtual("signal-exclamation-mark"), period = 0,
    chat = "gb-notify.loan-defaulted-chat", color = WARNING },
  ["insolvent"] = { category = "finance", icon = virtual("signal-alert"), period = 0,
    chat = "gb-insolvency.insolvent", color = WARNING, chat_always = true },
  ["recovered"] = { category = "finance", icon = virtual("signal-green"), period = 0,
    chat = "gb-insolvency.recovered", color = GOOD },
  ["bankrupt"] = { category = "finance", icon = virtual("signal-skull"), period = 0,
    chat = "gb-insolvency.bankrupt", color = WARNING, chat_always = true },
  ["credit-restored"] = { category = "finance", icon = virtual("signal-unlock"), period = 0,
    chat = "gb-insolvency.credit-restored", color = GOOD },
  -- Market events (scripts/market_events.lua): rare and bounded by their draw, grouped by event.
  ["market-event-announced"] = { category = "market", icon = virtual("signal-question-mark"), period = 0,
    chat = "gb-notify.market-event-announced-chat" },
  ["market-event-started"] = { category = "market", icon = virtual("signal-alarm"), period = 0,
    chat = "gb-notify.market-event-started-chat" },
  ["market-event-cancelled"] = { category = "market", icon = virtual("signal-no-entry"), period = 0,
    chat = "gb-notify.market-event-cancelled-chat" },
  ["market-event-ended"] = { category = "market", icon = virtual("signal-white-flag"), period = 0,
    chat = "gb-notify.market-event-ended-chat" },
}

-- Drops the entries of a throttle log whose period has passed at `tick` and that have no count left
-- to tell: they no longer hold anything back, so the log only holds the groups told within their
-- period and those with a count waiting for their next event.
local function prune(log, tick)
  local gone = {}
  for key, entry in pairs(log) do
    if tick >= entry.tick + entry.period and not entry.pending then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do log[key] = nil end
end

--- Whether an event of `kind` for `group` (a string or number) may be told at `tick`, given a force's
--- throttle `log` (a plain table kept by the caller, {[key] = {tick, period, pending}}); records it
--- when so. `count` (optional) is how many things the event stands for: a throttled event keeps it
--- as `pending`, and an admitted one returns, second, its count plus what was pending. Errors on an
--- unknown kind (a programming error).
function notifications.admit(log, kind, group, tick, count)
  local spec = notifications.KINDS[kind]
  if not spec then error("unknown notification kind: " .. tostring(kind)) end
  if spec.period <= 0 then return true, count end
  prune(log, tick)
  local key = kind .. "/" .. tostring(group)
  local entry = log[key]
  if entry and tick < entry.tick + entry.period then
    if count and count > 0 then entry.pending = (entry.pending or 0) + count end
    return false
  end
  log[key] = { tick = tick, period = spec.period }
  return true, count and count + (entry and entry.pending or 0)
end

--- Folds a merged force's throttle log (`source`) into the destination's: a group told by either keeps
--- the latest tick, and both counts still to tell add up, so nothing is told twice or lost.
function notifications.merge(destination, source)
  for key, entry in pairs(source) do
    local kept = destination[key]
    if kept then
      kept.tick = math.max(kept.tick, entry.tick)
      if entry.pending then kept.pending = (kept.pending or 0) + entry.pending end
    else
      destination[key] = { tick = entry.tick, period = entry.period, pending = entry.pending }
    end
  end
end

--- Whether an active contract that requires goods is due within DUE_SOON_TICKS at `tick`, its
--- deadline not passed, with goods still owed; never for a custody contract, whose counterparty
--- collects the goods itself (ADR-0024).
function notifications.due_soon(contract, tick)
  if contract.state ~= contracts.ACTIVE or contract.charge or contract.custody then return false end
  local left = contract.due_tick - tick
  return left >= 0 and left <= notifications.DUE_SOON_TICKS and not contracts.complete(contract)
end

return notifications
