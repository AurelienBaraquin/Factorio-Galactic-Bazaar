-- Economic invariants of the balance pass (#122, docs/balance.md), checked through the balance simulation,
-- which drives the real pure modules on the game's own base values: no money pump across systems, a
-- progression that stays an economic challenge.
local contract_offers = require("scripts.core.contract_offers")
local freight = require("scripts.core.freight")
local loans = require("scripts.core.loans")
local market = require("scripts.core.market")
local reputation = require("scripts.core.reputation")
local sim = require("tools.balance.sim")

local SETS = { "vanilla", "space_age" }

describe("balance: the plain market", function()
  it("never pays a closed round trip from a balanced market, however large or long", function()
    local best = sim.round_trips({ 0.001, 0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5 }, { 0, 1, 5, 10, 30, 60, 180, 600 })
    assert.is_true(best.net < 0)
  end)

  it("lets the own-reversion trade recover only part of the price impact the force paid", function()
    for _, pushed in ipairs({ 0.1, 0.2, 0.5, 1 }) do
      for _, share in ipairs({ 0.1, 0.25, 0.5, 1 }) do
        local own = sim.own_reversion(pushed, pushed * share, 180)
        assert.is_true(own.cycle < own.sell_less)
      end
    end
  end)

  it("caps what one good earns an hour from exports, whatever its value", function()
    local ceiling = sim.export_ceiling()
    for _, set in ipairs(SETS) do
      local rows = sim.exports(set, { { "iron-plate", 20000 }, { "processing-unit", 2000 } }, 240)
      for _, row in ipairs(rows) do assert.is_true(row.income <= ceiling * 1.001) end
    end
  end)
end)

describe("balance: incoming contracts", function()
  it("never pay buying the products and selling the ingredients on a balanced market", function()
    for _, set in ipairs(SETS) do
      for _, score in ipairs({ reputation.MIN, 0, reputation.MAX }) do
        for tier in pairs(freight.TIERS) do
          for _, row in ipairs(sim.incoming(set, score, tier, 0)) do
            assert.is_true(row.arbitrage < 0, set .. " " .. row.recipe)
          end
        end
      end
    end
  end)

  it("pay more than the value crafting adds, so that crafting for them earns something", function()
    for _, set in ipairs(SETS) do
      for _, row in ipairs(sim.incoming(set, 0, "capsule", 0)) do
        assert.is_true(row.reward > 0, set .. " " .. row.recipe)
      end
    end
  end)
end)

describe("balance: machine rentals", function()
  it("pay the machine's time, bounded whatever the recipe is worth", function()
    local bound = contract_offers.RENT_PER_SECOND * contract_offers.CAPACITY_SHARE * sim.RENTAL_SPEED
      * contract_offers.RENTAL_TICKS / 60
    for _, set in ipairs(SETS) do
      for _, row in ipairs(sim.rentals(set)) do
        assert.is_true(row.rent <= bound + 1e-9, set .. " " .. row.recipe)
      end
    end
  end)

  it("earn no reputation, so that idle machines cannot farm it", function()
    for _, set in ipairs(SETS) do
      for _, row in ipairs(sim.rentals(set)) do assert.are.equal(0, row.reputation) end
    end
  end)

  it("earn under a quarter of a mid-game force's exports even when every listed contract is a rental", function()
    local per_hour = sim.MAX_LISTED * contract_offers.RENT_PER_SECOND * contract_offers.CAPACITY_SHARE
      * sim.RENTAL_SPEED * 3600
    local mid = sim.scenario(sim.SCENARIOS[2])
    assert.is_true(per_hour < mid.income / 4)
  end)
end)

describe("balance: warehouse rentals", function()
  it("never make keeping and selling the goods pay before an NPC drift of 4 standard deviations", function()
    local sigma = sim.drift_sigma()
    for _, set in ipairs(SETS) do
      local names = {}
      for name in pairs(require("tools.balance.values")[set].values) do names[#names + 1] = name end
      table.sort(names)
      for _, score in ipairs({ reputation.MIN, 0, reputation.MAX }) do
        for _, row in ipairs(sim.warehouses(set, names, score)) do
          assert.is_true(row.break_even > 4 * sigma, set .. " " .. row.good)
        end
      end
    end
  end)
end)

describe("balance: credit", function()
  it("makes the overdraft dearer than a loan, and a loan never free", function()
    for _, row in ipairs(sim.loans({ reputation.MIN, 0, reputation.MAX })) do
      assert.is_true(row.interest > 0)
      local hourly = row.interest * 3600 * 60 / loans.TERM_TICKS
      assert.is_true(sim.overdraft_interest(row.principal) > hourly)
    end
  end)
end)

describe("balance: leases", function()
  it("price concessions and outsourcing between a balanced market's sell and buy prices", function()
    local half_spread = market.DEFAULTS.spread / 2
    for _, price in ipairs({ contract_offers.CONCESSION_PRICE, contract_offers.OUTSOURCING_PRICE }) do
      assert.is_true(price > 1 - half_spread and price <= 1 + half_spread)
    end
  end)
end)

describe("balance: progression", function()
  it("keeps a positive net income in every scenario, with contracts a side channel of exports", function()
    for _, scenario in ipairs(sim.SCENARIOS) do
      local row = sim.scenario(scenario)
      assert.is_true(row.net > 0, scenario.name)
      assert.is_true(row.incoming + row.rentals < row.income / 4, scenario.name)
    end
  end)

  it("takes at least an hour and a half of contracts to reach the best reputation", function()
    for _, scenario in ipairs(sim.SCENARIOS) do
      local row = sim.scenario(scenario)
      assert.is_true(reputation.MAX / row.reputation >= 1.5, scenario.name)
    end
  end)
end)
