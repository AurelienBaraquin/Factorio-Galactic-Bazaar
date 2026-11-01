-- The market of each force (ADR-0003, ADR-0004): quotes and trades for any key with a base value.
-- Market entries live in storage.forces[force_index].markets[key] and are brought up to date only
-- when read, so the simulation costs nothing while nobody trades or looks. Market events (ADR-0025,
-- scripts/market_events.lua) shift every force's displacement of their goods: the mid price, the
-- bounds and the liquidity use the entry's displacement plus that shift (within the bounds), and
-- buy and sell prices are the shifted prices of scripts/core/market.lua, which a shift only ever
-- makes worse for the trader than the plain ones. A trade moves the entry's own part by what it
-- traded.
local account = require("scripts.core.account")
local market_model = require("scripts.core.market")
local market_events = require("scripts.market_events")
local npc_market = require("scripts.core.npc_market")
local pricing = require("scripts.pricing")

local market = {}

local MARKET_PARAMS = market_model.DEFAULTS
local NPC_PARAMS = npc_market.DEFAULTS

-- Market parameters of a quality worth `ratio` × normal: its depth in credits grows with its value,
-- so it is as deep in units as the normal market (ADR-0008). Derived from constants only, so the
-- cache is the same on every peer.
local params_by_ratio = { [1] = MARKET_PARAMS }
local function params_for(ratio)
  local params = params_by_ratio[ratio]
  if not params then
    params = {}
    for name, value in pairs(MARKET_PARAMS) do params[name] = value end
    params.depth_credits = MARKET_PARAMS.depth_credits * ratio
    params_by_ratio[ratio] = params
  end
  return params
end

-- Brings a market entry of `key` up to `tick`, its history sampled with the shift of market events
-- and its drift salted (scripts/core/market_events.lua); returns that shift at `tick`, in units.
local function catch_up(entry, key, base_value, tick, params)
  local shift, shift_at = market_events.shift(key, tick, market_model.depth(base_value, params))
  npc_market.catch_up(entry, base_value, tick, params, NPC_PARAMS, shift_at, market_events.salt_at)
  return shift
end

-- The up-to-date market entry of a key for a force, with its base value, the force state, the key's
-- market parameters, the shift of market events (units, what is left of it within the bounds, so
-- that the entry's displacement plus it is the shifted displacement) and the bound; nil when the
-- force has no state (being merged) or the key has no base value (not tradeable).
local function current_entry(force_index, key)
  local state = storage.forces[force_index]
  local base_value, ratio = pricing.key_value(key)
  if not (state and base_value) then return nil end
  local params = params_for(ratio)
  local entry = state.markets[key]
  if not entry then
    entry = npc_market.new_entry(key, force_index, game.tick)
    state.markets[key] = entry
  end
  local shift = catch_up(entry, key, base_value, game.tick, params)
  local bound = params.max_depths * market_model.depth(base_value, params)
  local shifted = math.max(-bound, math.min(bound, entry.displacement + shift))
  return entry, base_value, state, params, shifted - entry.displacement, bound
end

-- Every function below takes `quality_name`, optional: an item quality other than normal trades on
-- its own market, priced from the normal value (ADR-0008). `buy` and `sell` also take `merge_ticks`,
-- optional, for recurring trades whose journal entries merge over that period (core/account.lua).

--- Current prices of `kind`/`name` ("item"/"fluid") for a force: {buy, sell, mid, history}, or nil
--- when it is not tradeable.
function market.quote(force_index, kind, name, quality_name)
  local entry, base_value, _, params, shift = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return nil end
  local own = entry.displacement
  return {
    buy = market_model.shifted_buy_price(base_value, own, shift, params),
    sell = market_model.shifted_sell_price(base_value, own, shift, params),
    mid = market_model.mid_price(base_value, own + shift, params),
    history = entry.history,
  }
end

--- The live market position of `kind`/`name` for a force: its base value, its displacement (market
--- events included), the market parameters of its quality (scripts/core/market.lua) and the shift
--- market events make in it (units, what is left of it within the bounds), for figures computed from
--- them (the Market tab's detail); nil when it is not tradeable.
function market.position(force_index, kind, name, quality_name)
  local entry, base_value, _, params, shift = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return nil end
  return base_value, entry.displacement + shift, params, shift
end

local function shifted_quote(side)
  return side == "buy" and market_model.quote_shifted_buy or market_model.quote_shifted_sell
end

local function trade(force_index, key, quantity, side, merge_ticks, value_factor)
  local entry, base_value, state, params, shift, bound = current_entry(force_index, key)
  if not entry then return false, "not-tradeable" end
  local own = entry.displacement
  local credits, after = shifted_quote(side)(base_value, own, shift, quantity, params)
  if not credits then return false, after end
  credits = credits * value_factor
  local amount = side == "buy" and -credits or credits
  local journal_entry = { tick = game.tick, kind = side, key = key, quantity = quantity, merge_ticks = merge_ticks }
  local ok, reason = account.apply(state, amount, journal_entry)
  if not ok then return false, reason end
  -- The entry's own part moves by what was traded (the events' shift is added again at every read).
  -- The clamp only matters when the shift carried the shifted displacement past the bound: the trade
  -- was then checked against the bound, and its own part stays within it, which changes no price.
  entry.displacement = math.max(-bound, math.min(bound, own + after - (own + shift)))
  return true, credits
end

--- What trading `quantity` units would bring (`side` "sell") or cost (`side` "buy") right now,
--- without trading: the credits, or nil and a reason.
function market.preview(force_index, kind, name, side, quantity, quality_name)
  local entry, base_value, _, params, shift = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return nil, "not-tradeable" end
  local credits, reason = shifted_quote(side)(base_value, entry.displacement, shift, quantity, params)
  if not credits then return nil, reason end
  return credits
end

--- What trading `quantity` units would bring (`side` "sell") or cost (`side` "buy") right now on the
--- plain market: at the force's own displacement, without the shift of market events; the credits,
--- or nil and a reason.
function market.plain_preview(force_index, kind, name, side, quantity, quality_name)
  local entry, base_value, _, params = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return nil, "not-tradeable" end
  local quote = side == "buy" and market_model.quote_buy or market_model.quote_sell
  local credits, reason = quote(base_value, entry.displacement, quantity, params)
  if not credits then return nil, reason end
  return credits
end

--- Units of `kind`/`name` the force can sell while each unit still sells for at least
--- `min_price_ratio` × its base value; 0 when it is not tradeable.
function market.sellable(force_index, kind, name, min_price_ratio, quality_name)
  local entry, base_value, _, params, shift = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return 0 end
  return market_model.max_shifted_sell_at_or_above(base_value, entry.displacement, shift,
    min_price_ratio * base_value, params)
end

--- Units of `kind`/`name` the force can buy before the market's shortage bound (market events
--- included: a shortage leaves fewer); 0 when it is not tradeable. Funds are not checked.
function market.buyable(force_index, kind, name, quality_name)
  local entry, base_value, _, params, shift = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return 0 end
  return market_model.max_buy(base_value, entry.displacement + shift, params)
end

--- The base values were rebuilt (prototypes, settings or overrides changed): every market entry is
--- brought up to date with its old value, then rebased on its new one so that its price stays the
--- same multiple of the base value and within bounds; entries of keys that lost their value go.
function market.rebase_all(old_values, old_levels)
  if not (old_values and storage.forces) then return end
  for _, state in pairs(storage.forces) do
    -- Prices a force saw before the change are no longer right (ADR-0012).
    state.feed = nil
    local gone = {}
    for key, entry in pairs(state.markets) do
      local old, old_ratio = pricing.key_value(key, old_values, old_levels)
      local new, new_ratio = pricing.key_value(key)
      if not new then
        gone[#gone + 1] = key
      elseif old and old ~= new then
        local old_params, new_params = params_for(old_ratio), params_for(new_ratio)
        catch_up(entry, key, old, game.tick, old_params)
        entry.displacement = market_model.rebase(entry.displacement, old, new, old_params, new_params)
      end
    end
    for _, key in ipairs(gone) do state.markets[key] = nil end
  end
end

--- Buys `quantity` units for the force: debits the account and moves the market, or changes nothing.
--- Returns true and the cost, or false and a reason (not-tradeable, invalid-quantity,
--- insufficient-liquidity, insufficient-funds). Delivering the goods is the caller's job.
function market.buy(force_index, kind, name, quantity, quality_name, merge_ticks)
  return trade(force_index, pricing.key(kind, name, quality_name), quantity, "buy", merge_ticks, 1)
end

--- Sells `quantity` units for the force: credits the account and moves the market, or changes
--- nothing. Returns true and the revenue, or false and a reason. Taking the goods is the caller's job.
--- `merge_ticks` (optional) merges the journal entries of recurring sales; `value_factor` (default
--- 1) scales the revenue, not the market move: the share of a fresh unit's value the goods keep
--- (spoilage, ADR-0013).
function market.sell(force_index, kind, name, quantity, quality_name, merge_ticks, value_factor)
  value_factor = value_factor or 1
  if not (value_factor >= 0 and value_factor <= 1) then return false, "invalid-value-factor" end
  return trade(force_index, pricing.key(kind, name, quality_name), quantity, "sell", merge_ticks, value_factor)
end

return market
