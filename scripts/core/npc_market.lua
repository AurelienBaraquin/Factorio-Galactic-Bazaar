-- What non-player traders do to one key's market between player trades (ADR-0004). Pure Lua.
--
-- A key's market entry is {displacement, tick, rng, history}. It is brought up to date lazily, when
-- it is read: every whole step since `tick`, its displacement decays towards balance, drifts by a
-- random amount, and the resulting mid price is appended to a short history. A long gap is first
-- decayed in one go, so catching up never costs more than `history_size` steps.
local market = require("scripts.core.market")
local random = require("scripts.core.random")

local npc_market = {}

npc_market.DEFAULTS = {
  -- Ticks between two NPC steps (and two history samples).
  step_ticks = 3600,
  -- Largest random drift per step, as a fraction of the market depth.
  volatility = 0.05,
  -- Price samples kept per key; also the most steps simulated in one catch-up.
  history_size = 30,
}

-- A stable number from a key name and a force index, to seed that market's own random sequence.
local function seed_of(key, force_index)
  local hash = force_index
  for i = 1, #key do hash = (hash * 31 + key:byte(i)) % 2147483647 end
  return random.seed(hash)
end

function npc_market.new_entry(key, force_index, tick)
  return { displacement = 0, tick = tick, rng = seed_of(key, force_index), history = {} }
end

local function step(entry, base_value, market_params, npc_params)
  local roll
  entry.rng, roll = random.next(entry.rng)
  local depth = market.depth(base_value, market_params)
  local bound = market_params.max_depths * depth
  local displacement = market.decay(entry.displacement, npc_params.step_ticks, market_params)
    + (2 * roll - 1) * npc_params.volatility * depth
  entry.displacement = math.max(-bound, math.min(bound, displacement))
  local history = entry.history
  history[#history + 1] = market.mid_price(base_value, entry.displacement, market_params)
  while #history > npc_params.history_size do table.remove(history, 1) end
end

--- Brings `entry` up to `tick`: runs every whole step since its last update.
function npc_market.catch_up(entry, base_value, tick, market_params, npc_params)
  local steps = math.floor((tick - entry.tick) / npc_params.step_ticks)
  if steps <= 0 then return end
  local skipped = steps - npc_params.history_size
  if skipped > 0 then
    entry.displacement = market.decay(entry.displacement, skipped * npc_params.step_ticks, market_params)
    steps = npc_params.history_size
  end
  for _ = 1, steps do step(entry, base_value, market_params, npc_params) end
  entry.tick = entry.tick + math.floor((tick - entry.tick) / npc_params.step_ticks) * npc_params.step_ticks
end

return npc_market
