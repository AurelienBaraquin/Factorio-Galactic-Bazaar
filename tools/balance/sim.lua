-- Balance simulation (#122, docs/balance.md). Plays the typical progressions written below through the
-- real pure modules of scripts/core/ — market, contract offers, storage rental, loans, reputation,
-- freight — so that every figure comes from the code the game runs, and returns plain tables:
-- `tools/balance/report.lua` prints them, `spec/balance_spec.lua` checks the economic invariants.
-- Base values come from a snapshot of the game's own valuation (tools/balance/values.lua).
local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")
local contract_offers = require("scripts.core.contract_offers")
local freight = require("scripts.core.freight")
local loans = require("scripts.core.loans")
local market = require("scripts.core.market")
local npc_market = require("scripts.core.npc_market")
local planets = require("scripts.core.planets")
local reputation = require("scripts.core.reputation")
local storage_rental = require("scripts.core.storage_rental")
local transit = require("scripts.core.transit")
local snapshot = require("tools.balance.values")

local sim = {}

local PARAMS = market.DEFAULTS
local MINUTE = 3600
-- Figures of the adapters and prototypes, which need the game API: cargo.DEFAULT_MIN_PRICE_RATIO (export
-- chests), the rental assembler's crafting speed and the rental warehouse's slots (prototypes/),
-- incoming.OFFER_TICKS and incoming.MAX_OFFERS, contracts.MAX_LISTED (scripts/).
sim.EXPORT_MIN_PRICE_RATIO = 0.5
sim.RENTAL_SPEED = 0.75
sim.WAREHOUSE_SLOTS = 48
sim.OFFERS_PER_HOUR = 60 / 5
sim.MAX_LISTED = 8

-- The typical progressions (docs/balance.md, "Scenarios"): what a force exports and imports every
-- minute, the delivery tier it buys by, its reputation, its rental assemblers and its loan.
sim.SCENARIOS = {
  { name = "vanilla early", set = "vanilla", tier = "capsule", reputation = 0, rentals = 0, loan = 5000,
    exports = { { "iron-plate", 240 }, { "copper-plate", 240 }, { "stone", 60 }, { "coal", 60 },
      { "iron-gear-wheel", 30 }, { "electronic-circuit", 30 } },
    imports = { { "steel-plate", 10 } } },
  { name = "vanilla mid", set = "vanilla", tier = "shuttle", reputation = 10, rentals = 4, loan = 20000,
    exports = { { "iron-plate", 900 }, { "copper-plate", 900 }, { "steel-plate", 120 }, { "plastic-bar", 300 },
      { "electronic-circuit", 300 }, { "advanced-circuit", 30 }, { "sulfur", 60 }, { "battery", 30 },
      { "engine-unit", 10 } },
    imports = { { "chemical-science-pack", 10 }, { "electric-engine-unit", 5 } } },
  { name = "vanilla late", set = "vanilla", tier = "teleporter", reputation = 20, rentals = 5, loan = 100000,
    exports = { { "iron-plate", 2700 }, { "copper-plate", 2700 }, { "steel-plate", 450 }, { "plastic-bar", 900 },
      { "electronic-circuit", 900 }, { "advanced-circuit", 180 }, { "processing-unit", 20 },
      { "low-density-structure", 20 }, { "rocket-fuel", 40 }, { "speed-module", 4 } },
    imports = { { "production-science-pack", 5 }, { "utility-science-pack", 5 } } },
  { name = "Space Age mid", set = "space_age", tier = "shuttle", reputation = 10, rentals = 4, loan = 20000,
    exports = { { "iron-plate", 900 }, { "copper-plate", 900 }, { "steel-plate", 150 }, { "plastic-bar", 300 },
      { "electronic-circuit", 300 }, { "advanced-circuit", 60 }, { "tungsten-plate", 20 },
      { "holmium-plate", 60 }, { "battery", 30 } },
    imports = { { "chemical-science-pack", 10 } } },
  { name = "Space Age late", set = "space_age", tier = "teleporter", reputation = 20, rentals = 5, loan = 100000,
    exports = { { "iron-plate", 2700 }, { "copper-plate", 2700 }, { "steel-plate", 450 }, { "plastic-bar", 900 },
      { "electronic-circuit", 900 }, { "advanced-circuit", 180 }, { "processing-unit", 40 },
      { "low-density-structure", 40 }, { "tungsten-plate", 40 }, { "holmium-plate", 180 },
      { "carbon-fiber", 60 }, { "supercapacitor", 20 }, { "quantum-processor", 5 } },
    imports = { { "production-science-pack", 5 }, { "utility-science-pack", 5 } } },
}

--- Base values of a snapshot set by market key ("item/<name>").
function sim.values_by_key(set)
  local values = {}
  for name, value in pairs(snapshot[set].values) do values["item/" .. name] = value end
  return values
end

local function goods(list)
  local copy = {}
  for i, entry in ipairs(list) do copy[i] = { kind = "item", name = entry[1], count = entry[2] } end
  return copy
end

--- The incoming-contract recipes of a snapshot set, as scripts/incoming_contracts.lua lists them.
function sim.recipes(set)
  local list = {}
  for i, recipe in ipairs(snapshot[set].recipes) do
    list[i] = { name = recipe.name, energy = recipe.energy, ingredients = goods(recipe.ingredients),
      products = goods(recipe.products) }
  end
  return list
end

--- Stationary standard deviation of a key's NPC drift, in market depths: each step adds a uniform
--- drift of at most `volatility` depths after decaying by a factor a, so the variance is
--- volatility² / 3 / (1 - a²).
function sim.drift_sigma()
  local a = 0.5 ^ (npc_market.DEFAULTS.step_ticks / PARAMS.half_life_ticks)
  return math.sqrt(npc_market.DEFAULTS.volatility ^ 2 / 3 / (1 - a * a))
end

-- A good sold by an export chest every second for `minutes`, at `per_minute` units a minute, while the
-- next unit fetches at least EXPORT_MIN_PRICE_RATIO of its base value; what is not sold waits in the
-- chest. Returns the revenue, units sold and units produced in the last hour.
local function export_good(value, per_minute, minutes, shift_at)
  local s, held, revenue, sold = 0, 0, 0, 0
  local min_price = sim.EXPORT_MIN_PRICE_RATIO * value
  for second = 1, minutes * 60 do
    held = held + per_minute / 60
    local shift = shift_at and shift_at(second) or 0
    local q = math.min(held, market.max_shifted_sell_at_or_above(value, s, shift, min_price, PARAMS))
    if q > 1e-9 then
      local r, after = market.quote_shifted_sell(value, s, shift, q, PARAMS)
      s = after - shift
      held = held - q
      if second > (minutes - 60) * 60 then
        revenue, sold = revenue + r, sold + q
      end
    end
    s = market.decay(s, 60, PARAMS)
  end
  return revenue, sold, per_minute * 60
end

--- Export income of a list of {good, units a minute} over `minutes` (the last hour is measured, at
--- steady state): rows {good, income, sold share, price ratio} and the total income an hour.
function sim.exports(set, list, minutes)
  local values = snapshot[set].values
  local rows, total = {}, 0
  for _, entry in ipairs(list) do
    local value = values[entry[1]]
    local revenue, sold, made = export_good(value, entry[2], minutes or 180)
    rows[#rows + 1] = { good = entry[1], value = value, income = revenue, sold_share = sold / made,
      ratio = sold > 0 and revenue / (sold * value) or 0 }
    total = total + revenue
  end
  return rows, total
end

--- The most a single good earns an hour from export chests at steady state, whatever its value and
--- volume: what selling it as fast as its own reversion allows, at the export chests' floor, brings.
function sim.export_ceiling()
  local depths = math.log((1 - PARAMS.spread / 2) / sim.EXPORT_MIN_PRICE_RATIO)
  local per_hour = depths * PARAMS.depth_credits * math.log(2) * 60 * MINUTE / PARAMS.half_life_ticks
  return per_hour * sim.EXPORT_MIN_PRICE_RATIO
end

--- Cost and freight fees an hour of buying a list of {good, units a minute} every minute, by `tier`,
--- at reputation `score` (the last hour of `minutes`).
function sim.imports(set, list, tier, score, minutes)
  local values = snapshot[set].values
  minutes = minutes or 180
  local cost, fees = 0, 0
  for _, entry in ipairs(list) do
    local value, s = values[entry[1]], 0
    for minute = 1, minutes do
      local c, after = market.quote_buy(value, s, entry[2], PARAMS)
      s = market.decay(after, MINUTE, PARAMS)
      if minute > minutes - 60 then
        cost = cost + c
        fees = fees + freight.fee(c, freight.TIERS[tier]) * reputation.fee_factor(score)
      end
    end
  end
  return cost, fees
end

-- What buying `units` of every good of `list` costs (each displaced by `shift` depths, negative raising
-- its price) and selling them brings, on the force's market.
local function buy_cost(values, list, shift)
  local total = 0
  for _, entry in ipairs(list) do
    local value = values[entry.kind .. "/" .. entry.name]
    total = total + market.quote_buy(value, shift * market.depth(value, PARAMS), entry.count, PARAMS)
  end
  return total
end

local function sell_revenue(values, list, shift)
  local total = 0
  for _, entry in ipairs(list) do
    local value = values[entry.kind .. "/" .. entry.name]
    total = total + market.quote_sell(value, shift * market.depth(value, PARAMS), entry.count, PARAMS)
  end
  return total
end

local function value_of(values, list)
  local total = 0
  for _, entry in ipairs(list) do total = total + values[entry.kind .. "/" .. entry.name] * entry.count end
  return total
end

--- Incoming contracts of a set at reputation `score`: per recipe, the offer's reward, guarantee, crafting
--- seconds, and what fulfilling it by buying the products and selling the ingredients received nets
--- (fee by `tier`), with prices at balance and with NPC drift of `drift` depths against the force
--- (products cheaper, ingredients dearer).
function sim.incoming(set, score, tier, drift)
  local values = sim.values_by_key(set)
  local scale = reputation.contract_scale(score)
  local fee = freight.TIERS[tier].fee_rate * reputation.fee_factor(score)
  local rows = {}
  for _, recipe in ipairs(sim.recipes(set)) do
    local spec = contract_offers.offer(recipe, values, 0.5, scale)
    if spec then
      local function arbitrage(x)
        return spec.reward + sell_revenue(values, spec.provides, -x) - buy_cost(values, spec.requires, x) * (1 + fee)
      end
      rows[#rows + 1] = {
        recipe = recipe.name, reward = spec.reward, guarantee = spec.deposit + spec.penalty,
        products = value_of(values, spec.requires), ingredients = value_of(values, spec.provides),
        seconds = recipe.energy * spec.requires[1].count / recipe.products[1].count,
        arbitrage = arbitrage(0), arbitrage_drift = arbitrage(drift or 0),
      }
    end
  end
  return rows
end

-- The reputation a contract of `spec` earns when every required unit is delivered: the engine's own
-- settlement outcome.
local function fulfilment_reputation(spec)
  local contract = contracts.new(spec, 0)
  contracts.accept(contract, 0)
  for _, required in ipairs(contract.requires) do
    contracts.deliver(contract, contracts.key(required), required.count, 1)
  end
  return contracts.settle(contract, 2).reputation
end

--- Machine rentals of a set by a rental assembler: per recipe, the rent over the term, the guarantee
--- (at base values; the adapter raises it to market values at acceptance), their ratio and the
--- reputation a fulfilled rental earns.
function sim.rentals(set)
  local values = sim.values_by_key(set)
  local rows = {}
  for _, recipe in ipairs(sim.recipes(set)) do
    local crafts = contract_offers.rental_crafts(recipe.energy, sim.RENTAL_SPEED)
    local spec = contract_offers.rental(recipe, values, 0.5, crafts)
    if spec then
      rows[#rows + 1] = { recipe = recipe.name, crafts = crafts, rent = spec.reward,
        guarantee = spec.deposit + spec.penalty, ratio = spec.reward / (spec.deposit + spec.penalty),
        reputation = fulfilment_reputation(spec) }
    end
  end
  return rows
end

-- The rows' mean of `field`.
function sim.mean(rows, field)
  local total = 0
  for _, row in ipairs(rows) do total = total + row[field] end
  return #rows > 0 and total / #rows or 0
end

-- The rows' median `field`.
function sim.median(rows, field)
  local values = {}
  for i, row in ipairs(rows) do values[i] = row[field] end
  table.sort(values)
  local middle = (#values + 1) / 2
  return (values[math.floor(middle)] + values[math.ceil(middle)]) / 2
end

-- The rows' largest `field`.
function sim.max(rows, field)
  local best = -math.huge
  for _, row in ipairs(rows) do best = math.max(best, row[field]) end
  return best
end

--- Warehouse rentals of `goods` (names) in a set: rent, the goods' worth, the guarantee at acceptance
--- on a balanced market, and the NPC drift (in depths) at which keeping and selling the goods would
--- pay more than handing them back (sell price up, the rent forgone).
function sim.warehouses(set, names, score)
  local values, stacks = snapshot[set].values, snapshot[set].stack_sizes
  local rows = {}
  for _, name in ipairs(names) do
    local value = values[name]
    local spec = storage_rental.warehouse(name, value, stacks[name], sim.WAREHOUSE_SLOTS, 0.5,
      reputation.contract_scale(score or 0))
    local units = spec.provides[1].count
    local penalty = storage_rental.warehouse_penalty(spec.penalty, market.quote_buy(value, 0, units, PARAMS))
    local guarantee = spec.deposit + penalty
    -- Selling `units` at displacement -x L brings e^x times what it brings at balance.
    local at_balance = market.quote_sell(value, 0, units, PARAMS)
    local break_even = math.log((guarantee + spec.reward) / at_balance)
    rows[#rows + 1] = { good = name, units = units, rent = spec.reward, worth = value * units,
      guarantee = guarantee, ratio = spec.reward / guarantee, break_even = break_even }
  end
  return rows
end

--- Loans: for each tier and reputation in `scores`, the interest over the term and whether the debt
--- cap allows it from no debt.
function sim.loans(scores)
  local rows = {}
  for _, score in ipairs(scores) do
    for _, principal in ipairs(loans.TIERS) do
      local spec = loans.spec(principal, score)
      rows[#rows + 1] = { reputation = score, principal = principal,
        interest = spec.charge * loans.periods() - principal, allowed = loans.refusal(principal, score, {}, 0) == nil }
    end
  end
  return rows
end

--- Overdraft interest an hour on a debt of `debt` held all hour.
function sim.overdraft_interest(debt)
  return debt * account.INTEREST_RATE * 60 * MINUTE / account.INTEREST_TICKS
end

--- The best net, in credits per credit of base value traded, of a closed round trip on one key from a
--- balanced market: buy then sell, or sell then buy back, `quantity` depths each way, `wait` minutes
--- apart, over the grids given; and the best of each.
function sim.round_trips(quantities, waits)
  local value = 1
  local depth = market.depth(value, PARAMS)
  local best = { net = -math.huge }
  for _, q in ipairs(quantities) do
    for _, wait in ipairs(waits) do
      local units = q * depth
      local cost, s = market.quote_buy(value, 0, units, PARAMS)
      local back = market.quote_sell(value, market.decay(s, wait * MINUTE, PARAMS), units, PARAMS)
      local buy_first = (back - cost) / (value * units)
      local revenue, s2 = market.quote_sell(value, 0, units, PARAMS)
      local rebuy = market.quote_buy(value, market.decay(s2, wait * MINUTE, PARAMS), units, PARAMS)
      local sell_first = (revenue - rebuy) / (value * units)
      local cases = { { net = buy_first, side = "buy, then sell" }, { net = sell_first, side = "sell, then buy back" } }
      for _, case in ipairs(cases) do
        if case.net > best.net then best = { net = case.net, side = case.side, quantity = q, wait = wait } end
      end
    end
  end
  return best
end

--- The own-reversion trade (ADR-0003): a force that sold `pushed` depths of a good at once (own
--- displacement +pushed) buys `bought` depths back at its depressed price and sells them once its
--- displacement has decayed (`wait` minutes). Returns that trade's return on what it paid, and the
--- whole cycle (the first sale, the buy-back, the later sale) against selling only what it keeps for
--- good at once and the rest after the wait: the trade recovers part of the price impact the force
--- paid, never more.
function sim.own_reversion(pushed, bought, wait)
  local value = 1
  local depth = market.depth(value, PARAMS)
  local first, s = market.quote_sell(value, 0, pushed * depth, PARAMS)
  local cost, s2 = market.quote_buy(value, s, bought * depth, PARAMS)
  local later = market.quote_sell(value, market.decay(s2, wait * MINUTE, PARAMS), bought * depth, PARAMS)
  local cycle = first - cost + later
  local kept, s3 = 0, 0
  if pushed > bought then kept, s3 = market.quote_sell(value, 0, (pushed - bought) * depth, PARAMS) end
  local rest = market.quote_sell(value, market.decay(s3, wait * MINUTE, PARAMS), bought * depth, PARAMS)
  return { trade_return = later / cost - 1, cycle = cycle, sell_less = kept + rest }
end

--- Mining concessions and outsourcing: the NPC drift (in depths, up) at which reselling what a lease
--- ships on the market pays, after the mean transit loss from the nearest planet.
function sim.lease_resale()
  local nearest = math.huge
  for _, planet in ipairs(planets.CATALOG) do nearest = math.min(nearest, planet.distance) end
  local kept = 1 - transit.terms(nearest).max_loss / 2
  local sell = 1 - PARAMS.spread / 2
  return {
    concession = math.log(contract_offers.CONCESSION_PRICE / (sell * kept)),
    outsourcing = math.log(contract_offers.OUTSOURCING_PRICE / (sell * kept)),
  }
end

--- A surplus on one exported good (market events, ADR-0025): the share of that good's income lost over
--- 3 hours when an event of goal `goal` depths lasts `minutes`, against the plain market; the shift
--- rises towards the goal and fades with the market's half-life.
function sim.surplus_loss(good, set, per_minute, goal, minutes)
  local value = snapshot[set].values[good]
  local depth = market.depth(value, PARAMS)
  local h = PARAMS.half_life_ticks / 60
  local start, stop = 3600, 3600 + minutes * 60
  local at_stop = goal * (1 - 0.5 ^ ((stop - start) / h))
  local function shift_at(second)
    if second < start then return 0 end
    if second < stop then return goal * (1 - 0.5 ^ ((second - start) / h)) * depth end
    return at_stop * 0.5 ^ ((second - stop) / h) * depth
  end
  local plain = 0
  local with_event = 0
  -- The 3 hours after the event's start, measured as three last hours of runs ending then.
  for hour = 2, 4 do
    plain = plain + export_good(value, per_minute, hour * 60)
    with_event = with_event + export_good(value, per_minute, hour * 60, shift_at)
  end
  return 1 - with_event / plain
end

--- Credits the science packs of a research cost when bought on a balanced market by `tier` at
--- reputation `score`; nil when a pack has no value in the set.
function sim.research_cost(set, technology, tier, score)
  local values = snapshot[set].values
  local total = 0
  for _, ingredient in ipairs(technology.unit.ingredients) do
    local value = values[ingredient[1]]
    if not value then return nil end
    local cost = market.quote_buy(value, 0, technology.unit.count * ingredient[2], PARAMS)
    total = total + cost * (1 + freight.TIERS[tier].fee_rate * reputation.fee_factor(score))
  end
  return total
end

--- The mod's technologies, read from prototypes/technologies.lua with a stand-in `data` (the data
--- stage is not available outside the game).
function sim.technologies()
  local captured
  local icons = setmetatable({}, { __index = function() return { icons = {} } end })
  local previous = rawget(_G, "data")
  rawset(_G, "data", { raw = setmetatable({}, { __index = function() return icons end }),
    extend = function(_, list) captured = list end })
  package.loaded["prototypes.technologies"] = nil
  require("prototypes.technologies")
  rawset(_G, "data", previous)
  local by_name = {}
  for _, technology in ipairs(captured) do by_name[technology.name] = technology end
  return by_name
end

--- Per scenario, an hour at steady state: export income, import cost, freight fees, contract income
--- (an offer every 5 minutes at its reputation, each paying the median reward of the snapshot's recipes,
--- and the same with the mean; its rentals), loan interest and the reputation an hour earns.
function sim.scenario(scenario)
  local _, income = sim.exports(scenario.set, scenario.exports)
  local cost, fees = sim.imports(scenario.set, scenario.imports, scenario.tier, scenario.reputation)
  local incoming = sim.incoming(scenario.set, scenario.reputation, scenario.tier)
  local rentals = sim.rentals(scenario.set)
  local incoming_hour = sim.median(incoming, "reward") * sim.OFFERS_PER_HOUR
  local rental_hour = sim.mean(rentals, "rent") * scenario.rentals * 60 * MINUTE / contract_offers.RENTAL_TICKS
  local interest = 0
  if scenario.loan > 0 then interest = loans.spec(scenario.loan, scenario.reputation).charge * loans.periods()
    - scenario.loan end
  local rentals_per_hour = scenario.rentals * 60 * MINUTE / contract_offers.RENTAL_TICKS
  return {
    reputation = sim.OFFERS_PER_HOUR + rentals_per_hour * sim.mean(rentals, "reputation"),
    name = scenario.name, income = income, imports = cost, fees = fees, incoming = incoming_hour,
    incoming_mean = sim.mean(incoming, "reward") * sim.OFFERS_PER_HOUR,
    rentals = rental_hour, interest = interest * 60 * MINUTE / loans.TERM_TICKS,
    net = income - cost - fees + incoming_hour + rental_hour - interest * 60 * MINUTE / loans.TERM_TICKS,
  }
end

return sim
