-- Incoming contract offers (#76, ADR-0015). Pure Lua: turns a recipe the force can craft into a
-- contract spec — a counterparty provides the ingredients for a batch, the force hands back the
-- products — priced from base values.
--
-- Pricing keeps the deal honest both ways: the reward pays the work — LABOR_SHARE of the products'
-- value, but never more than the value crafting adds (products minus ingredients) plus SPREAD_SHARE of
-- what the market's spread takes from buying the products and selling the ingredients, so that doing
-- so never pays on a balanced market (#122) — and the guarantee (deposit plus penalty) exceeds the
-- value of the ingredients provided, so taking them and failing costs more than they are worth (the
-- adapter raises the penalty to their market price at acceptance).
local market = require("scripts.core.market")

local contract_offers = {}

-- Value of the products a batch aims at, in credits.
contract_offers.TARGET_VALUE = 1000
contract_offers.MAX_BATCH = 1000
contract_offers.LABOR_SHARE = 0.3
-- Share of the spread a round trip through the market loses (spread / 2 on each side, at base values)
-- that the reward may add to the value crafting adds; the rest is the margin against price moves.
contract_offers.SPREAD_SHARE = 0.5
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
    reward = math.min(contract_offers.LABOR_SHARE * product_value, product_value - ingredient_value
      + contract_offers.SPREAD_SHARE * market.DEFAULTS.spread / 2 * (product_value + ingredient_value)) * batch,
    deposit = contract_offers.DEPOSIT_SHARE * ingredient_value * batch,
    penalty = contract_offers.PENALTY_SHARE * ingredient_value * batch,
    duration_ticks = math.ceil(recipe.energy * 60 * batch * contract_offers.TIME_FACTOR)
      + contract_offers.MARGIN_TICKS,
    accept_ticks = contract_offers.ACCEPT_TICKS,
  }
end

-- Machine rental (#78): a counterparty rents a machine for RENTAL_TICKS to craft one recipe, at
-- CAPACITY_SHARE of the machine's nominal speed, and pays the machine's time: RENT_PER_SECOND for each
-- second of crafting at speed 1 it promises, whatever the products are worth (#122), in installments
-- every INSTALLMENT_TICKS. Only products the script takes from the machine count, so buying them on
-- the market cannot fulfil a rental; the guarantee exceeds what the force could take from the machine
-- (the products or the ingredients, whichever is worth more). A rental is passive: the counterparty
-- supplies everything and the machine only runs, so it earns no reputation.
contract_offers.RENTAL_TICKS = 3600 * 30
contract_offers.INSTALLMENT_TICKS = 3600 * 5
contract_offers.CAPACITY_SHARE = 0.8
contract_offers.RENT_PER_SECOND = 0.5

--- Crafts a rental promises: CAPACITY_SHARE of what a machine of crafting speed `speed` makes in
--- RENTAL_TICKS of a recipe taking `energy` seconds; 0 when it cannot make one.
function contract_offers.rental_crafts(energy, speed)
  if not (energy > 0 and speed > 0) then return 0 end
  return math.floor(contract_offers.CAPACITY_SHARE * speed * contract_offers.RENTAL_TICKS / (energy * 60))
end

--- A rental contract spec for `crafts` crafts of `recipe` (as in `offer`), with base `values` by
--- key and the counterparty picked by `draw`; nil when a good has no value or no craft is promised.
function contract_offers.rental(recipe, values, draw, crafts)
  local product_value = value_of(recipe.products, values)
  local ingredient_value = value_of(recipe.ingredients, values)
  if not (product_value and ingredient_value) or product_value <= 0 or crafts < 1 then return nil end
  local at_stake = math.max(product_value, ingredient_value) * crafts
  local counterparties = contract_offers.COUNTERPARTIES
  return {
    kind = "rental", passive = true,
    counterparty = counterparties[math.min(#counterparties, math.floor(draw * #counterparties) + 1)],
    provides = scaled(recipe.ingredients, crafts),
    requires = scaled(recipe.products, crafts),
    reward = contract_offers.RENT_PER_SECOND * recipe.energy * crafts,
    deposit = contract_offers.DEPOSIT_SHARE * at_stake,
    penalty = contract_offers.PENALTY_SHARE * at_stake,
    duration_ticks = contract_offers.RENTAL_TICKS,
    accept_ticks = contract_offers.ACCEPT_TICKS,
    installment_ticks = contract_offers.INSTALLMENT_TICKS,
  }
end

-- Mining concessions (#85): the force leases slots of a planet's resource for CONCESSION_TICKS;
-- every CONCESSION_PERIOD_TICKS, each slot ships UNITS_PER_SLOT_MINUTE units a minute of the
-- period, charged at CONCESSION_PRICE times their base value (between the market's sell and buy
-- prices, so a concession neither undercuts selling nor beats buying with its fee). The guarantee is
-- one period's charge.
contract_offers.CONCESSION_TICKS = 3600 * 30
contract_offers.CONCESSION_PERIOD_TICKS = 3600 * 5
contract_offers.UNITS_PER_SLOT_MINUTE = 30
contract_offers.CONCESSION_PRICE = 1

--- Units a concession of `slots` slots ships every period.
function contract_offers.concession_units(slots)
  return slots * contract_offers.UNITS_PER_SLOT_MINUTE * contract_offers.CONCESSION_PERIOD_TICKS / 3600
end

-- A lease of planet slots of `kind` shipping `units` of `item` (base value `value`) every period;
-- nil without a positive value or a unit to ship.
local function lease_spec(kind, planet, item, units, value, price)
  if not (value and value > 0 and units >= 1) then return nil end
  local periods = contract_offers.CONCESSION_TICKS / contract_offers.CONCESSION_PERIOD_TICKS
  local charge = units * value * price
  return {
    kind = kind, counterparty = planet,
    provides = { { kind = "item", name = item, count = units * periods } },
    requires = {},
    reward = 0, deposit = charge, penalty = 0, charge = charge,
    duration_ticks = contract_offers.CONCESSION_TICKS, accept_ticks = 60,
    installment_ticks = contract_offers.CONCESSION_PERIOD_TICKS,
  }
end

--- A concession spec for `slots` slots of `resource` (an item) with base value `value`, from
--- `planet`; nil without a positive value.
function contract_offers.concession(planet, resource, value, slots)
  return lease_spec("concession", planet, resource, contract_offers.concession_units(slots), value,
    contract_offers.CONCESSION_PRICE)
end

-- Outsourced production (#86): the force books slots of a planet's crafting category for one recipe,
-- on the terms of a concession: the planet buys the ingredients itself, crafts at crafting speed 1
-- per slot and ships the products every period, charged at OUTSOURCING_PRICE times their base value:
-- the market's buy price when balanced, without the freight fee, so that products a force can pick
-- by the hundred do not undercut the market when its price drifts up (the force pays for products,
-- never for ingredients it does not see).
contract_offers.OUTSOURCING_PRICE = 1.05

--- Products a booking of `slots` slots ships every period, of a recipe taking `energy` seconds and
--- making `amount` of its product per craft (whole crafts only).
function contract_offers.outsourcing_units(energy, amount, slots)
  if energy ~= energy or energy <= 0 then return 0 end
  return math.floor(slots * contract_offers.CONCESSION_PERIOD_TICKS / 60 / energy) * amount
end

--- An outsourcing spec for `slots` slots of `recipe` = {energy, product, amount}, whose product has
--- base value `value`, on `planet`; nil without a positive value or a whole craft a period.
function contract_offers.outsourcing(planet, recipe, value, slots)
  local units = contract_offers.outsourcing_units(recipe.energy, recipe.amount, slots)
  return lease_spec("outsourcing", planet, recipe.product, units, value, contract_offers.OUTSOURCING_PRICE)
end

--- The recipe of `candidates` (a sorted list) that `draw` (a number in (0, 1)) picks.
function contract_offers.pick(candidates, draw)
  if #candidates == 0 then return nil end
  return candidates[math.min(#candidates, math.floor(draw * #candidates) + 1)]
end

-- Goods in shortage (#122): while a market event pushes the price of goods up by SHORTAGE_DEPTHS market
-- depths or more, counterparties ask for them: an offer names a recipe making such goods with chance
-- SHORTAGE_CHANCE. Its terms stay those of any offer, priced from base values, so the shortage adds
-- offers, not a reward that buying the goods could earn.
contract_offers.SHORTAGE_CHANCE = 0.5
contract_offers.SHORTAGE_DEPTHS = 0.1

--- The recipe of `candidates` (a sorted list) an offer names: when `choice` (in (0, 1)) is below
--- SHORTAGE_CHANCE, one of those whose product is in shortage (`depths(key)`, the shift of a market key
--- in depths, at most -SHORTAGE_DEPTHS), picked by `draw`; otherwise, or when none is, one of all.
function contract_offers.pick_short(candidates, depths, choice, draw)
  if choice < contract_offers.SHORTAGE_CHANCE then
    local short = {}
    for _, recipe in ipairs(candidates) do
      local product = recipe.products[1]
      if depths(product.kind .. "/" .. product.name) <= -contract_offers.SHORTAGE_DEPTHS then
        short[#short + 1] = recipe
      end
    end
    if #short > 0 then return contract_offers.pick(short, draw) end
  end
  return contract_offers.pick(candidates, draw)
end

return contract_offers
