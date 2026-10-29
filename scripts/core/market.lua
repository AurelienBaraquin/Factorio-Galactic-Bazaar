-- Price model of one tradeable key on the market (ADR-0003). Pure Lua.
--
-- The market state of a key is one number, its displacement `s` in units: positive after the market
-- bought from players (it holds a surplus, prices fall), negative after it sold to them (shortage,
-- prices rise). With V the base value and L the depth in units:
--   mid price      P(s) = V * exp(-s / L)
--   buy / sell     the player pays P * (1 + spread/2) and receives P * (1 - spread/2)
--   large orders   the exact integral of the price over the units traded, in one step
--   reversion      s decays towards 0 with a half-life
-- The depth is set in credits (`depth_credits / V` units), so a cheap item absorbs more units than an
-- expensive one before its price moves by the same factor. |s| is capped at `max_depths * L`, which
-- bounds every price between V / e^max_depths and V * e^max_depths.
local market = {}

market.DEFAULTS = {
  spread = 0.1,
  depth_credits = 20000,
  half_life_ticks = 36000,
  max_depths = 10,
}

-- exp(x) - 1 without losing precision for tiny orders.
local function expm1(x)
  if math.abs(x) < 1e-5 then return x + x * x / 2 end
  return math.exp(x) - 1
end

function market.depth(base_value, params)
  return params.depth_credits / base_value
end

function market.mid_price(base_value, displacement, params)
  return base_value * math.exp(-displacement / market.depth(base_value, params))
end

--- Price of the next unit bought by the player.
function market.buy_price(base_value, displacement, params)
  return market.mid_price(base_value, displacement, params) * (1 + params.spread / 2)
end

--- Price of the next unit sold by the player.
function market.sell_price(base_value, displacement, params)
  return market.mid_price(base_value, displacement, params) * (1 - params.spread / 2)
end

--- Most units the player can buy before the shortage bound.
function market.max_buy(base_value, displacement, params)
  return math.max(0, displacement + params.max_depths * market.depth(base_value, params))
end

--- Most units the player can sell before the surplus bound.
function market.max_sell(base_value, displacement, params)
  return math.max(0, params.max_depths * market.depth(base_value, params) - displacement)
end

--- Cost of buying `quantity` units, and the displacement after the trade; nil and a reason when the
--- quantity is not positive or exceeds `max_buy`.
function market.quote_buy(base_value, displacement, quantity, params)
  if quantity ~= quantity or quantity <= 0 then return nil, "invalid-quantity" end
  if quantity > market.max_buy(base_value, displacement, params) then return nil, "insufficient-liquidity" end
  local depth = market.depth(base_value, params)
  local cost = (1 + params.spread / 2) * market.mid_price(base_value, displacement, params) * depth
    * expm1(quantity / depth)
  return cost, displacement - quantity
end

--- Revenue of selling `quantity` units, and the displacement after the trade; nil and a reason when
--- the quantity is not positive or exceeds `max_sell`.
function market.quote_sell(base_value, displacement, quantity, params)
  if quantity ~= quantity or quantity <= 0 then return nil, "invalid-quantity" end
  if quantity > market.max_sell(base_value, displacement, params) then return nil, "insufficient-liquidity" end
  local depth = market.depth(base_value, params)
  local revenue = (1 - params.spread / 2) * market.mid_price(base_value, displacement, params) * depth
    * -expm1(-quantity / depth)
  return revenue, displacement + quantity
end

--- Displacement after `ticks` of reversion towards the base value.
function market.decay(displacement, ticks, params)
  return displacement * 0.5 ^ (ticks / params.half_life_ticks)
end

return market
