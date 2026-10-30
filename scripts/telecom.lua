-- Telecommunications (ADR-0012): a force's research level sets how fresh the prices it sees are.
-- Displayed prices come from a per-force feed, storage.forces[i].feed[key] = {tick, buy, sell,
-- history}, quoted again only when older than the level's period; trades always use live prices.
local market = require("scripts.market")
local pricing = require("scripts.pricing")
local core = require("scripts.core.telecom")

local telecom = {}

telecom.TECHNOLOGIES = { "gb-telecommunications-1", "gb-telecommunications-2" }

--- The force's telecommunications level: the highest researched (0 without any).
function telecom.level(force)
  local level = 0
  for index, name in ipairs(telecom.TECHNOLOGIES) do
    local technology = force.technologies[name]
    if technology and technology.researched then level = index end
  end
  return level
end

--- Ticks a price seen by the force may be old.
function telecom.period(force)
  return core.period(telecom.level(force))
end

--- Whether the force sees price history and trends.
function telecom.shows_history(force)
  return core.shows_history(telecom.level(force))
end

--- Prices of `kind`/`name` as the force sees them: {buy, sell, history}, at most its period old
--- (`period`, optional, saves reading the force's research on every call); nil when it is not
--- tradeable. `history` is the market entry's own history table, live, not a copy.
function telecom.quote(force_index, kind, name, period)
  local state = storage.forces[force_index]
  if not state then return nil end
  state.feed = state.feed or {}
  local key = pricing.key(kind, name)
  local seen = state.feed[key]
  if seen and game.tick - seen.tick < (period or telecom.period(game.forces[force_index])) then return seen end
  local quote = market.quote(force_index, kind, name)
  if not quote then
    state.feed[key] = nil
    return nil
  end
  seen = { tick = game.tick, buy = quote.buy, sell = quote.sell, history = quote.history }
  state.feed[key] = seen
  return seen
end

return telecom
