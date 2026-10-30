-- The market of each force (ADR-0003, ADR-0004): quotes and trades for any key with a base value.
-- Market entries live in storage.forces[force_index].markets[key] and are brought up to date only
-- when read, so the simulation costs nothing while nobody trades or looks.
local account = require("scripts.core.account")
local market_model = require("scripts.core.market")
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

-- The up-to-date market entry of a key for a force, with its base value, the force state and the
-- key's market parameters; nil when the force has no state (being merged) or the key has no base
-- value (not tradeable).
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
  npc_market.catch_up(entry, base_value, game.tick, params, NPC_PARAMS)
  return entry, base_value, state, params
end

-- Every function below takes `quality_name` last, optional: an item quality other than normal
-- trades on its own market, priced from the normal value (ADR-0008).

--- Current prices of `kind`/`name` ("item"/"fluid") for a force: {buy, sell, mid, history}, or nil
--- when it is not tradeable.
function market.quote(force_index, kind, name, quality_name)
  local entry, base_value, _, params = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return nil end
  return {
    buy = market_model.buy_price(base_value, entry.displacement, params),
    sell = market_model.sell_price(base_value, entry.displacement, params),
    mid = market_model.mid_price(base_value, entry.displacement, params),
    history = entry.history,
  }
end

local function trade(force_index, key, quantity, side)
  local entry, base_value, state, params = current_entry(force_index, key)
  if not entry then return false, "not-tradeable" end
  local quote = side == "buy" and market_model.quote_buy or market_model.quote_sell
  local credits, displacement = quote(base_value, entry.displacement, quantity, params)
  if not credits then return false, displacement end
  local amount = side == "buy" and -credits or credits
  local ok, reason = account.apply(state, amount, { tick = game.tick, kind = side, key = key, quantity = quantity })
  if not ok then return false, reason end
  entry.displacement = displacement
  return true, credits
end

--- What trading `quantity` units would bring (`side` "sell") or cost (`side` "buy") right now,
--- without trading: the credits, or nil and a reason.
function market.preview(force_index, kind, name, side, quantity, quality_name)
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
  local entry, base_value, _, params = current_entry(force_index, pricing.key(kind, name, quality_name))
  if not entry then return 0 end
  return market_model.max_sell_at_or_above(base_value, entry.displacement, min_price_ratio * base_value, params)
end

--- The base values were rebuilt (prototypes, settings or overrides changed): every market entry is
--- brought up to date with its old value, then rebased on its new one so that its price stays the
--- same multiple of the base value and within bounds; entries of keys that lost their value go.
function market.rebase_all(old_values, old_levels)
  if not (old_values and storage.forces) then return end
  for _, state in pairs(storage.forces) do
    local gone = {}
    for key, entry in pairs(state.markets) do
      local old, old_ratio = pricing.key_value(key, old_values, old_levels)
      local new, new_ratio = pricing.key_value(key)
      if not new then
        gone[#gone + 1] = key
      elseif old and old ~= new then
        local old_params, new_params = params_for(old_ratio), params_for(new_ratio)
        npc_market.catch_up(entry, old, game.tick, old_params, NPC_PARAMS)
        entry.displacement = market_model.rebase(entry.displacement, old, new, old_params, new_params)
      end
    end
    for _, key in ipairs(gone) do state.markets[key] = nil end
  end
end

--- Buys `quantity` units for the force: debits the account and moves the market, or changes nothing.
--- Returns true and the cost, or false and a reason (not-tradeable, invalid-quantity,
--- insufficient-liquidity, insufficient-funds). Delivering the goods is the caller's job.
function market.buy(force_index, kind, name, quantity, quality_name)
  return trade(force_index, pricing.key(kind, name, quality_name), quantity, "buy")
end

--- Sells `quantity` units for the force: credits the account and moves the market, or changes
--- nothing. Returns true and the revenue, or false and a reason. Taking the goods is the caller's job.
function market.sell(force_index, kind, name, quantity, quality_name)
  return trade(force_index, pricing.key(kind, name, quality_name), quantity, "sell")
end

return market
