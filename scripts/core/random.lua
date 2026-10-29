-- Deterministic pseudo-random numbers whose whole state is one number, so it lives in storage and
-- every multiplayer peer draws the same sequence. Park-Miller "minimal standard" generator:
-- state = state * 16807 mod (2^31 - 1); every product stays below 2^53, so doubles are exact.
local random = {}

local MODULUS = 2147483647
local MULTIPLIER = 16807

--- A valid state from any seed number.
function random.seed(n)
  local state = math.floor(math.abs(n)) % MODULUS
  if state == 0 then state = 1 end
  return state
end

--- Next state, and a number uniformly drawn in (0, 1).
function random.next(state)
  state = state * MULTIPLIER % MODULUS
  return state, state / MODULUS
end

return random
