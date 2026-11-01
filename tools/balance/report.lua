-- Prints the balance simulation's tables (docs/balance.md) as Markdown. From the repository root:
--   .lua/bin/lua tools/balance/report.lua
package.path = "./?.lua;" .. package.path
local market_events = require("scripts.core.market_events")
local reputation = require("scripts.core.reputation")
local sim = require("tools.balance.sim")

-- Keys with a base value in the snapshot's game (2.1.24): the candidates of market events.
local CANDIDATES = { vanilla = 218, space_age = 320 }

local function n(x, digits)
  return string.format("%." .. (digits or 0) .. "f", x)
end

local function pct(x)
  return string.format("%.1f %%", x * 100)
end

local function table_out(header, rows)
  print("| " .. table.concat(header, " | ") .. " |")
  local line = {}
  for i = 1, #header do line[i] = "---" end
  print("|" .. table.concat(line, "|") .. "|")
  for _, row in ipairs(rows) do print("| " .. table.concat(row, " | ") .. " |") end
  print()
end

print("### Scenarios: an hour at steady state (credits)\n")
local rows = {}
for _, scenario in ipairs(sim.SCENARIOS) do
  local r = sim.scenario(scenario)
  local to_max = (reputation.MAX - scenario.reputation) / r.reputation
  local incoming = n(r.incoming) .. " (mean " .. n(r.incoming_mean) .. ")"
  rows[#rows + 1] = { r.name, n(r.income), n(r.imports), n(r.fees), incoming, n(r.rentals), n(r.interest), n(r.net),
    n(r.reputation, 1), scenario.reputation < reputation.MAX and n(to_max * 60) .. " min" or "—" }
end
table_out({ "Scenario", "Exports", "Imports", "Fees", "Incoming contracts: median (mean)", "Rentals",
  "Loan interest", "Net", "Reputation / h", "To reputation 20" }, rows)

print("### Exports: share of production sold and price ratio, last hour\n")
rows = {}
for _, scenario in ipairs(sim.SCENARIOS) do
  local goods = sim.exports(scenario.set, scenario.exports)
  local sold, made = 0, 0
  for i, row in ipairs(goods) do
    sold = sold + row.sold_share * scenario.exports[i][2]
    made = made + scenario.exports[i][2]
  end
  local worst = goods[1]
  for _, row in ipairs(goods) do if row.sold_share < worst.sold_share then worst = row end end
  rows[#rows + 1] = { scenario.name, pct(sold / made), worst.good .. " " .. pct(worst.sold_share),
    n(sim.max(goods, "income")) }
end
table_out({ "Scenario", "Units sold", "Least sold", "Best good / h" }, rows)
print("Ceiling of one good's export income: " .. n(sim.export_ceiling()) .. " credits an hour.\n")

local sigma = sim.drift_sigma()
print("### Contracts (reputation 0, capsule)\n")
print("NPC drift: stationary standard deviation " .. n(sigma, 3) .. " depths.\n")
rows = {}
for _, set in ipairs({ "vanilla", "space_age" }) do
  local incoming = sim.incoming(set, 0, "capsule", 2 * sigma)
  for _, row in ipairs(incoming) do
    row.share, row.per_second = row.reward / row.products, row.reward / row.seconds
  end
  rows[#rows + 1] = { set, n(sim.median(incoming, "reward"), 1), pct(sim.median(incoming, "share")),
    n(sim.median(incoming, "per_second"), 2), n(sim.max(incoming, "arbitrage"), 1),
    n(sim.max(incoming, "arbitrage_drift"), 1) }
end
table_out({ "Set", "Incoming reward (median)", "Reward / products (median)", "Reward / crafting second (median)",
  "Best buy-and-deliver net", "Same, drift 2σ" }, rows)

rows = {}
for _, set in ipairs({ "vanilla", "space_age" }) do
  local rentals = sim.rentals(set)
  local hourly = 0
  for _, row in ipairs(rentals) do hourly = hourly + row.ratio * 2 end
  rows[#rows + 1] = { set, n(sim.mean(rentals, "rent")), n(sim.max(rentals, "rent")),
    pct(hourly / #rentals), n(sim.mean(rentals, "reputation"), 0) }
end
table_out({ "Set", "Rent per term (mean)", "Rent per term (max)", "Rent / guarantee an hour (mean)",
  "Reputation per rental" }, rows)

print("### Warehouse rentals (reputation 0)\n")
rows = {}
for _, entry in ipairs({ { "vanilla", "wood" }, { "vanilla", "iron-plate" }, { "vanilla", "electronic-circuit" },
  { "vanilla", "processing-unit" }, { "space_age", "tungsten-plate" } }) do
  local row = sim.warehouses(entry[1], { entry[2] })[1]
  rows[#rows + 1] = { entry[1] .. " " .. row.good, n(row.units), n(row.rent), n(row.worth), n(row.guarantee),
    pct(row.ratio), n(row.break_even, 3) .. " (" .. n(row.break_even / sigma, 1) .. "σ)" }
end
table_out({ "Goods", "Units", "Rent", "Worth", "Guarantee", "Rent / guarantee", "Drift to keep and sell" }, rows)

print("### Credit\n")
rows = {}
for _, row in ipairs(sim.loans({ -20, 0, 10, 20 })) do
  rows[#rows + 1] = { n(row.reputation), n(row.principal), n(row.interest), row.allowed and "yes" or "no (debt cap)" }
end
table_out({ "Reputation", "Principal", "Interest over the term", "Allowed from no debt" }, rows)
print("Overdraft interest on 10 000 credits of debt held an hour: " .. n(sim.overdraft_interest(10000)) .. ".\n")

print("### Exploit checks\n")
local best = sim.round_trips({ 0.01, 0.05, 0.1, 0.2, 0.5, 1, 2 }, { 0, 1, 10, 30, 60, 180 })
local own = sim.own_reversion(0.2, 0.05, 180)
local leases = sim.lease_resale()
local loss = sim.surplus_loss("iron-plate", "vanilla", 600, 0.7, 14)
local events = market_events.DEFAULTS
local draws = 60 * 3600 / events.interval_ticks
local surplus = draws * events.kinds.surplus.weight * (1 - events.announce_chance * events.cancel_chance)
rows = {
  { "Best closed round trip from balance", pct(best.net) .. " (" .. best.side .. ", " .. best.quantity
    .. " depths, " .. best.wait .. " min)" },
  { "Own reversion: buy 0.05 depths at own +0.2, sell 3 h later", pct(own.trade_return) },
  { "Same, whole cycle against selling less at once", n(own.cycle, 0) .. " vs " .. n(own.sell_less, 0)
    .. " credits per depth of base value" },
  { "Concession resale pays from NPC drift", n(leases.concession, 3) .. " depths (" .. n(leases.concession / sigma, 1)
    .. "σ)" },
  { "Outsourcing resale pays from NPC drift", n(leases.outsourcing, 3) .. " depths ("
    .. n(leases.outsourcing / sigma, 1) .. "σ)" },
  { "Surplus of 0.7 depths for 14 min on a saturated export", pct(loss) .. " of its income over 3 h" },
  { "Surpluses an hour on one exported good (vanilla, frequency 1)", n(surplus / CANDIDATES.vanilla, 4) },
}
table_out({ "Check", "Result" }, rows)

print("### Research bought with credits (science at a balanced market, capsule, reputation 0)\n")
local technologies = sim.technologies()
local names = {}
for name in pairs(technologies) do names[#names + 1] = name end
table.sort(names)
local early = sim.scenario(sim.SCENARIOS[1]).net
local mid = sim.scenario(sim.SCENARIOS[2]).net
rows = {}
for _, name in ipairs(names) do
  local vanilla = sim.research_cost("vanilla", technologies[name], "capsule", 0)
  local space_age = sim.research_cost("space_age", technologies[name], "capsule", 0)
  rows[#rows + 1] = { name, n(vanilla), n(space_age), n(vanilla / early * 60) .. " min",
    n(vanilla / mid * 60) .. " min" }
end
table_out({ "Technology", "Vanilla", "Space Age", "Early net income", "Mid net income" }, rows)
