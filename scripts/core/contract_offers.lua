-- Incoming contract offers (#76, ADR-0015). Pure Lua: turns a recipe the force can craft into a
-- contract spec — a counterparty provides the ingredients for a batch, the force hands back the
-- products — priced from base values.
--
-- Pricing keeps the deal honest both ways: the reward pays the work — LABOR_SHARE of the products'
-- value, but never more than the value crafting adds (products minus ingredients), so buying the
-- products on the market and selling the ingredients received never pays — and the guarantee
-- (deposit plus penalty) exceeds the value of the ingredients provided, so taking them and failing
-- costs more than they are worth (the adapter raises the penalty to their market price at
-- acceptance).
local contract_offers = {}

-- Value of the products a batch aims at, in credits.
contract_offers.TARGET_VALUE = 1000
contract_offers.MAX_BATCH = 1000
contract_offers.LABOR_SHARE = 0.3
-- Deposit and penalty, as shares of the value of the ingredients provided.
contract_offers.DEPOSIT_SHARE = 0.2
contract_offers.PENALTY_SHARE = 1
-- Time given per craft at crafting speed 1, as a multiple of the recipe's time, plus a fixed margin
-- for deliveries; and how long an offer stands.
contract_offers.TIME_FACTOR = 4
contract_offers.MARGIN_TICKS = 3600 * 5
contract_offers.ACCEPT_TICKS = 3600 * 5

contract_offers.COUNTERPARTIES = {
  "Nauvis Prime Holdings", "Kepler Orbital Works", "Aldebaran Foundry", "Tau Ceti Assembly Guild",
  "Vega Freight Union", "Proxima Trade Combine",
}

-- Value of a goods list given base values by key; nil when a key has none.
local function value_of(list, values)
  local total = 0
  for _, goods in ipairs(list) do
    local value = values[goods.kind .. "/" .. goods.name]
    if not value then return nil end
    total = total + value * goods.count
  end
  return total
end

local function scaled(list, batch)
  local copy = {}
  for i, goods in ipairs(list) do
    copy[i] = { kind = goods.kind, name = goods.name, count = goods.count * batch }
  end
  return copy
end

--- A contract spec from `recipe` = {energy, ingredients = {{kind, name, count}}, products =
--- {{kind, name, count}}} and base `values` by key, with the counterparty picked by `draw` (a number
--- in (0, 1)), its products worth TARGET_VALUE × `scale` (optional, 1 by default: the force's
--- reputation, core/reputation.lua); nil when a good has no value or crafting adds no value.
function contract_offers.offer(recipe, values, draw, scale)
  local product_value = value_of(recipe.products, values)
  local ingredient_value = value_of(recipe.ingredients, values)
  if not (product_value and ingredient_value) or product_value <= ingredient_value then return nil end
  local batch = math.max(1, math.min(contract_offers.MAX_BATCH,
    math.ceil(contract_offers.TARGET_VALUE * (scale or 1) / product_value)))
  local counterparties = contract_offers.COUNTERPARTIES
  return {
    kind = "incoming",
    counterparty = counterparties[math.min(#counterparties, math.floor(draw * #counterparties) + 1)],
    provides = scaled(recipe.ingredients, batch),
    requires = scaled(recipe.products, batch),
    reward = math.min(contract_offers.LABOR_SHARE * product_value, product_value - ingredient_value) * batch,
    deposit = contract_offers.DEPOSIT_SHARE * ingredient_value * batch,
    penalty = contract_offers.PENALTY_SHARE * ingredient_value * batch,
    duration_ticks = math.ceil(recipe.energy * 60 * batch * contract_offers.TIME_FACTOR)
      + contract_offers.MARGIN_TICKS,
    accept_ticks = contract_offers.ACCEPT_TICKS,
  }
end

--- The recipe of `candidates` (a sorted list) that `draw` (a number in (0, 1)) picks.
function contract_offers.pick(candidates, draw)
  if #candidates == 0 then return nil end
  return candidates[math.min(#candidates, math.floor(draw * #candidates) + 1)]
end

return contract_offers
