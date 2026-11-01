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

  it("samples the history with the shift of market events, which the displacement does not hold", function()
    local depth = market.depth(V, market_params)
    local plain, shifted = entry_at(0), entry_at(0)
    local ticks = {}
    npc_market.catch_up(plain, V, 2 * STEP, market_params, npc_params)
    npc_market.catch_up(shifted, V, 2 * STEP, market_params, npc_params, function(tick)
      ticks[#ticks + 1] = tick
      return -depth
    end)
    assert.are.same({ STEP, 2 * STEP }, ticks)
    assert.are.equal(plain.displacement, shifted.displacement)
    assert.is_true(math.abs(shifted.history[2] - plain.history[2] * math.exp(1)) < 1e-9 * shifted.history[2])
  end)

  it("bounds a shifted history sample like any price", function()
    local bound = market_params.max_depths * market.depth(V, market_params)
    local entry = entry_at(-bound)
    npc_market.catch_up(entry, V, STEP, market_params, npc_params, function() return -bound end)
    assert.is_true(entry.history[1] <= V * math.exp(market_params.max_depths) * (1 + 1e-12))
  end)

  it("adds a salt of its step's tick to each drift roll, so the key and force alone do not give it", function()
    local plain, salted = entry_at(0), entry_at(0)
    local asked = {}
    npc_market.catch_up(plain, V, 2 * STEP, market_params, npc_params)
    npc_market.catch_up(salted, V, 2 * STEP, market_params, npc_params, nil, function(tick)
      asked[#asked + 1] = tick
      return 0.5
    end)
    assert.are.same({ STEP, 2 * STEP }, asked)
    assert.are_not.equal(plain.displacement, salted.displacement)
    assert.are.equal(plain.rng, salted.rng)
    local unsalted = entry_at(0)
    npc_market.catch_up(unsalted, V, 2 * STEP, market_params, npc_params, nil, function() return nil end)
    assert.are.equal(plain.displacement, unsalted.displacement)
  end)

  it("gives the same salted result whether it catches up at once or in pieces", function()
    local function salt(tick) return (tick / STEP * 0.37) % 1 end
    local once, pieces = entry_at(500), entry_at(500)
    npc_market.catch_up(once, V, 6 * STEP, market_params, npc_params, nil, salt)
    npc_market.catch_up(pieces, V, 2 * STEP, market_params, npc_params, nil, salt)
    npc_market.catch_up(pieces, V, 6 * STEP, market_params, npc_params, nil, salt)
    assert.are.same(once, pieces)
  end)

  it("gives the same result whether it catches up at once or in pieces", function()
    local once, pieces = entry_at(500), entry_at(500)
    npc_market.catch_up(once, V, 6 * STEP, market_params, npc_params)
    npc_market.catch_up(pieces, V, 2 * STEP, market_params, npc_params)
    npc_market.catch_up(pieces, V, 6 * STEP, market_params, npc_params)
    assert.are.same(once, pieces)
  end)
end)
