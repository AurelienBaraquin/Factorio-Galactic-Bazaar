-- Transit from NPC planets (#84, ADR-0018). Pure Lua: goods shipped from a planet travel longer the
-- farther it is, and lose a share on the way, drawn from (0, max_loss] of the planet — the terms a
-- service announces before the force commits. The draw comes from a seed the caller derives from
-- game state (a contract id and a tick), so every peer computes the same loss.
local random = require("scripts.core.random")

local transit = {}

-- Ticks of travel per distance unit, added to the capsule's landing delay.
transit.TICKS_PER_DISTANCE = 3600
-- Share lost per distance unit, at most, and the cap on that share.
transit.LOSS_PER_DISTANCE = 0.02
transit.MAX_LOSS = 0.25

--- The terms of transit from a planet at `distance`: its extra delay in ticks and the largest share
--- of a shipment that may be lost.
function transit.terms(distance)
  return {
    delay_ticks = transit.TICKS_PER_DISTANCE * distance,
    max_loss = math.min(transit.MAX_LOSS, transit.LOSS_PER_DISTANCE * distance),
  }
end

--- Share of a shipment from `distance` lost on the way, for `seed` (any number): from just above 0
--- to the planet's max_loss.
function transit.loss_share(distance, seed)
  local _, draw = random.next(random.seed(seed))
  return transit.terms(distance).max_loss * draw
end

--- What arrives of `count` units once `share` is lost, in whole units rounded down (freight ships
--- whole units of items and fluids alike).
function transit.arriving(count, share)
  return math.floor(count * (1 - share))
end

return transit
