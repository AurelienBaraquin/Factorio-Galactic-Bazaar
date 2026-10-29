local market = require("scripts.core.market")
local npc_market = require("scripts.core.npc_market")

local market_params = market.DEFAULTS
local npc_params = npc_market.DEFAULTS
local STEP = npc_params.step_ticks
local V = 2

local function entry_at(displacement)
  local entry = npc_market.new_entry("item/iron-plate", 1, 0)
  entry.displacement = displacement
  return entry
end

describe("npc_market.new_entry", function()
  it("starts balanced, with a random sequence of its own per key and force", function()
    local a = npc_market.new_entry("item/iron-plate", 1, 100)
    assert.are.equal(0, a.displacement)
    assert.are.equal(100, a.tick)
    assert.are_not.equal(a.rng, npc_market.new_entry("item/copper-plate", 1, 100).rng)
    assert.are_not.equal(a.rng, npc_market.new_entry("item/iron-plate", 2, 100).rng)
    assert.are.equal(a.rng, npc_market.new_entry("item/iron-plate", 1, 0).rng)
  end)
end)

describe("npc_market.catch_up", function()
  it("does nothing before a whole step has passed", function()
    local entry = entry_at(1000)
    npc_market.catch_up(entry, V, STEP - 1, market_params, npc_params)
    assert.are.equal(1000, entry.displacement)
    assert.are.equal(0, entry.tick)
    assert.are.same({}, entry.history)
  end)

  it("runs one step per whole step elapsed, recording one price each, and keeps the remainder", function()
    local entry = entry_at(0)
    npc_market.catch_up(entry, V, 3 * STEP + 5, market_params, npc_params)
    assert.are.equal(3, #entry.history)
    assert.are.equal(3 * STEP, entry.tick)
    assert.are.equal(market.mid_price(V, entry.displacement, market_params), entry.history[3])
  end)

  it("drifts by at most the volatility around the decayed displacement", function()
    local depth = market.depth(V, market_params)
    local entry = entry_at(1000)
    npc_market.catch_up(entry, V, STEP, market_params, npc_params)
    local decayed = market.decay(1000, STEP, market_params)
    assert.is_true(math.abs(entry.displacement - decayed) <= npc_params.volatility * depth)
  end)

  it("pulls a large surplus back towards balance over time", function()
    local depth = market.depth(V, market_params)
    local entry = entry_at(5 * depth)
    npc_market.catch_up(entry, V, 20 * market_params.half_life_ticks, market_params, npc_params)
    assert.is_true(math.abs(entry.displacement) < depth)
  end)

  it("simulates at most history_size steps after a long gap, and stays in bounds", function()
    local bound = market_params.max_depths * market.depth(V, market_params)
    local entry = entry_at(bound)
    npc_market.catch_up(entry, V, 1000 * STEP, market_params, npc_params)
    assert.are.equal(npc_params.history_size, #entry.history)
    assert.are.equal(1000 * STEP, entry.tick)
    assert.is_true(math.abs(entry.displacement) <= bound)
  end)

  it("gives the same result whether it catches up at once or in pieces", function()
    local once, pieces = entry_at(500), entry_at(500)
    npc_market.catch_up(once, V, 6 * STEP, market_params, npc_params)
    npc_market.catch_up(pieces, V, 2 * STEP, market_params, npc_params)
    npc_market.catch_up(pieces, V, 6 * STEP, market_params, npc_params)
    assert.are.same(once, pieces)
  end)
end)
