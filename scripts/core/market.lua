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

--- Most units the player can sell while the price of each unit stays at or above `min_price`
--- (and within `max_sell`). The sell price at displacement x is (1 - spread/2) V e^(-x/L), so the
--- last acceptable displacement is -L ln(min_price / ((1 - spread/2) V)).
function market.max_sell_at_or_above(base_value, displacement, min_price, params)
  if min_price <= 0 then return market.max_sell(base_value, displacement, params) end
  local depth = market.depth(base_value, params)
  local last = -depth * math.log(min_price / ((1 - params.spread / 2) * base_value))
  return math.max(0, math.min(last - displacement, market.max_sell(base_value, displacement, params)))
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

--- Displacement after the base value changes from `old_value` to `new_value` (and the parameters
--- from `old_params` to `new_params`, default the same): scaled so that the price stays the same
--- multiple of the base value (s / L is kept), then bounded again.
function market.rebase(displacement, old_value, new_value, old_params, new_params)
  new_params = new_params or old_params
  local new_depth = market.depth(new_value, new_params)
  local scaled = displacement * new_depth / market.depth(old_value, old_params)
  local bound = new_params.max_depths * new_depth
  return math.max(-bound, math.min(bound, scaled))
end

--- Displacement after `ticks` of reversion towards the base value.
function market.decay(displacement, ticks, params)
  return displacement * 0.5 ^ (ticks / params.half_life_ticks)
end

-- Prices under a market event (scripts/core/market_events.lua): the event shifts the displacement `s`
-- by `shift` units. The shifted displacement sets the mid price and the bounds, but a shift only ever
-- makes a price worse for the trader: a shortage (shift < 0) raises the buy price, the sell price
-- staying the plain one; a surplus (shift > 0) lowers the sell price, the buy price staying the plain
-- one. So every trade under an event is at most as good as the same trade on the plain market at the
-- same moment and the same displacement, and an event can add nothing to any strategy, whatever its
-- course and whatever a player knows of it. Prices are continuous in the shift.

--- Price of the next unit bought under a shift: the buy price at s + min(shift, 0).
function market.shifted_buy_price(base_value, displacement, shift, params)
  return market.buy_price(base_value, displacement + math.min(shift, 0), params)
end

--- Price of the next unit sold under a shift: the sell price at s + max(shift, 0).
function market.shifted_sell_price(base_value, displacement, shift, params)
  return market.sell_price(base_value, displacement + math.max(shift, 0), params)
end

--- Cost of buying `quantity` units under a shift, and the shifted displacement after the trade; nil
--- and a reason like market.quote_buy, the bound applying to the shifted displacement.
function market.quote_shifted_buy(base_value, displacement, shift, quantity, params)
  if quantity ~= quantity or quantity <= 0 then return nil, "invalid-quantity" end
  if quantity > market.max_buy(base_value, displacement + shift, params) then return nil, "insufficient-liquidity" end
  local depth = market.depth(base_value, params)
  local cost = (1 + params.spread / 2) * market.mid_price(base_value, displacement + math.min(shift, 0), params)
    * depth * expm1(quantity / depth)
  return cost, displacement + shift - quantity
end

--- Revenue of selling `quantity` units under a shift, and the shifted displacement after the trade.
function market.quote_shifted_sell(base_value, displacement, shift, quantity, params)
  if quantity ~= quantity or quantity <= 0 then return nil, "invalid-quantity" end
  if quantity > market.max_sell(base_value, displacement + shift, params) then return nil, "insufficient-liquidity" end
  local depth = market.depth(base_value, params)
  local revenue = (1 - params.spread / 2) * market.mid_price(base_value, displacement + math.max(shift, 0), params)
    * depth * -expm1(-quantity / depth)
  return revenue, displacement + shift + quantity
end

--- Most units sellable under a shift while each unit's price stays at or above `min_price`, within
--- the bound of the shifted displacement.
function market.max_shifted_sell_at_or_above(base_value, displacement, shift, min_price, params)
  local priced = displacement + math.max(shift, 0)
  local room = market.max_sell(base_value, displacement + shift, params)
  if min_price <= 0 then return room end
  local last = -market.depth(base_value, params) * math.log(min_price / ((1 - params.spread / 2) * base_value))
  return math.max(0, math.min(last - priced, room))
end

return market
