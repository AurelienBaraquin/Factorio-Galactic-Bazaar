-- The figures of the Market tab's item detail (#110): what a key's prices are, why, and what an
-- order would do. Pure Lua: takes a base value, a market displacement and the parameters of
-- scripts/core/market.lua and scripts/core/npc_market.lua, or the source record the valuation kept
-- (scripts/core/valuation.lua), and changes nothing.
local market = require("scripts.core.market")
local quality = require("scripts.core.quality")
local recipe_graph = require("scripts.core.recipe_graph")

local item_detail = {}

--- The market figures of a key with base value `base_value` and displacement `displacement`:
--- prices (`buy`, `sell`, `mid`), the gap of the mid price from the base value (`gap`, a ratio, +0.1
--- for 10 % above), the displacement in units and in depths, the spread, the units left before each
--- bound and the price bounds, the NPC drift per step (in units, and the largest rise and fall of
--- the mid price it causes) and the mid price after one half-life without trades. `shift` (optional,
--- units) is the part of `displacement` market events make: buy and sell prices are then the capped
--- shifted prices of scripts/core/market.lua.
function item_detail.market(base_value, displacement, params, npc_params, shift)
  shift = shift or 0
  local depth = market.depth(base_value, params)
  local mid = market.mid_price(base_value, displacement, params)
  local buy = market.shifted_buy_price(base_value, displacement - shift, shift, params)
  local sell = market.shifted_sell_price(base_value, displacement - shift, shift, params)
  return {
    base_value = base_value,
    buy = buy,
    sell = sell,
    mid = mid,
    gap = mid / base_value - 1,
    displacement = displacement,
    depth = depth,
    depths = displacement / depth,
    spread = params.spread,
    spread_credits = buy - sell,
    max_buy = market.max_buy(base_value, displacement, params),
    max_sell = market.max_sell(base_value, displacement, params),
    bound_units = params.max_depths * depth,
    ceiling = base_value * math.exp(params.max_depths),
    floor = base_value * math.exp(-params.max_depths),
    step_ticks = npc_params.step_ticks,
    drift_units = npc_params.volatility * depth,
    drift_up = math.exp(npc_params.volatility) - 1,
    drift_down = 1 - math.exp(-npc_params.volatility),
    half_life_ticks = params.half_life_ticks,
    reverted_mid = market.mid_price(base_value, market.decay(displacement, params.half_life_ticks, params), params),
  }
end

--- What market events (scripts/core/market_events.lua) add to a key's displacement, `shift` units:
--- {units, depths, effect}, `effect` the change of the mid price they make (+0.5 for 50 % above what
--- it would be without them).
function item_detail.event(base_value, shift, params)
  local depth = market.depth(base_value, params)
  return { units = shift, depths = shift / depth, effect = math.exp(-shift / depth) - 1 }
end

--- The displacement at which the next unit bought costs `buy`: the inverse of market.buy_price, to
--- read the market figures from a price seen through telecommunications (ADR-0012). With a market
--- event's `shift` (units, optional; the shift when the price was seen) the buy price is the plain
--- one moved by the shortage part only (market.shifted_buy_price), so the surplus part is added back.
function item_detail.displacement_from_buy(base_value, buy, params, shift)
  local mid = buy / (1 + params.spread / 2)
  return -market.depth(base_value, params) * math.log(mid / base_value) + math.max(shift or 0, 0)
end

local function side(quote, next_price, base_value, own, shift, quantity, params)
  local total, after = quote(base_value, own, shift, quantity, params)
  if not total then return { reason = after } end
  return { total = total, average = total / quantity,
    next_price = next_price(base_value, after - shift, shift, params) }
end

--- What an order of `quantity` units would do, on each side: {buy = {total, average, next_price},
--- sell = {...}}, `next_price` being the price of the next unit after the order; a side beyond the
--- market's liquidity is {reason}. `shift` (optional, units) is the part of `displacement` market
--- events make, as in item_detail.market.
function item_detail.impact(base_value, displacement, quantity, params, shift)
  shift = shift or 0
  local own = displacement - shift
  return {
    buy = side(market.quote_shifted_buy, market.shifted_buy_price, base_value, own, shift, quantity, params),
    sell = side(market.quote_shifted_sell, market.shifted_sell_price, base_value, own, shift, quantity, params),
  }
end

--- The scale of a price history (oldest first): {low, high, first, last, change}, `change` the ratio
--- from the first to the last price; nil below two points.
function item_detail.history(history)
  if #history < 2 then return nil end
  local low, high = math.huge, -math.huge
  for _, price in ipairs(history) do
    low, high = math.min(low, price), math.max(high, price)
  end
  local first, last = history[1], history[#history]
  return { low = low, high = high, first = first, last = last, change = first > 0 and last / first - 1 or 0 }
end

-- The kind of source from the name the production graph gives it (scripts/core/recipe_graph.lua),
-- and the name of what it acts on.
local PREFIXES = { "mine", "pump", "launch", "burn" }
local function kind_of(recipe_name)
  for _, prefix in ipairs(PREFIXES) do
    local name = recipe_name:match("^" .. prefix .. "/(.+)$")
    if name then return prefix, name end
  end
  return "recipe", recipe_name
end

-- Credits per second of the time a source takes, by kind.
local TIME_COSTS = { recipe = recipe_graph.TIME_COST, mine = recipe_graph.MINING_COST }

--- Why a key is worth what it is. `source` is the valuation's record of the offer that set its
--- normal value (nil for a fixed value or when unknown); `options` = {value = normal base value,
--- multiplier = the startup multiplier, override = the key's override ({value} or {factor}), tier,
--- ratio = the quality's value ratio (default 1)}. Returns {kind ("recipe", "mine", "pump",
--- "launch", "burn", "fixed" or "unknown"), name, tier, inputs = {{key, amount, value, total}},
--- cost, seconds (crafting or mining time), share, amount, graph_value (what the recipe gives),
--- factor, fixed, multiplier, ratio, normal_value, value}. Credits include the multiplier.
function item_detail.breakdown(source, options)
  local multiplier, ratio = options.multiplier or 1, options.ratio or 1
  local override = options.override or {}
  local result = { inputs = {}, tier = options.tier, multiplier = multiplier, ratio = ratio,
    normal_value = options.value, value = options.value * ratio, factor = override.factor, fixed = override.value }
  if override.value then
    result.kind = "fixed"
    return result
  end
  if not source then
    result.kind = "unknown"
    return result
  end
  result.kind, result.name = kind_of(source.recipe)
  local total = source.cost * multiplier
  for i, input in ipairs(source.inputs) do
    local value = input.value * multiplier
    result.inputs[i] = { key = input.key, amount = input.amount, value = value, total = input.amount * value }
    total = total + result.inputs[i].total
  end
  result.cost = source.cost * multiplier
  result.seconds = TIME_COSTS[result.kind] and source.cost / TIME_COSTS[result.kind]
  result.share, result.amount = source.share, source.amount
  result.graph_value = total / source.share / source.amount
  return result
end

--- The qualities above normal, by level: {{name, level, ratio}...}, from {[name] = level}.
function item_detail.quality_ladder(levels)
  local ladder = {}
  for name, level in pairs(levels) do
    if name ~= quality.NORMAL then
      ladder[#ladder + 1] = { name = name, level = level, ratio = quality.value(1, level) }
    end
  end
  table.sort(ladder, function(a, b) return a.level < b.level or (a.level == b.level and a.name < b.name) end)
  return ladder
end

return item_detail
