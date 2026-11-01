-- Value overrides by other mods (ADR-0007): the remote interface "galactic-bazaar", and the rebuild
-- of base values that every change (and every configuration change) goes through, so that markets
-- are always rebased on the new values. Overrides persist in storage.value_overrides.
local market = require("scripts.market")
local market_events = require("scripts.market_events")
local overrides = require("scripts.core.overrides")
local pricing = require("scripts.pricing")
local raw_graph = require("scripts.recipe_graph")

local value_overrides = {}

--- Rebuilds the base values, rebases every market on them and updates the market events' goods.
function value_overrides.rebuild()
  local old_values, old_levels = storage.base_values, storage.quality_levels
  pricing.init()
  market.rebase_all(old_values, old_levels)
  market_events.on_values_rebuilt()
end

-- Raises an error for the calling mod: remote calls come from other mods' code. The message names
-- the mistake; no position is added, since the caller's line is not on this stack.
local function fail(message)
  error("galactic-bazaar: " .. message, 0)
end

-- Checks the call and returns the key; `check_number` (optional) validates the number argument.
local function checked_key(kind, name, number, check_number)
  if not game then fail("remote calls are not allowed during on_load") end
  if not raw_graph.is_tradeable(kind, name) then
    fail(tostring(kind) .. "/" .. tostring(name) .. " is not a tradeable item or fluid")
  end
  local reason = check_number and check_number(number)
  if reason then fail(tostring(number) .. ": " .. reason) end
  return pricing.key(kind, name)
end

-- Stores or removes an override and rebuilds. Works before this mod's own on_init (a mod without
-- a dependency on it may run first): the state is created here, and on_init keeps it.
local function set_override(key, entry)
  storage.value_overrides = storage.value_overrides or {}
  storage.value_overrides[key] = entry
  value_overrides.rebuild()
end

--- The remote interface "galactic-bazaar" (docs/pricing.md). Each change recomputes every base value.
value_overrides.REMOTE = {
  --- Fixes the base value of `kind`/`name` ("item"/"fluid") to `credits`; products follow.
  set_value = function(kind, name, credits)
    set_override(checked_key(kind, name, credits, overrides.check_value), { value = credits })
  end,
  --- Scales the base value the production graph gives `kind`/`name` by `factor`; products follow.
  scale_value = function(kind, name, factor)
    set_override(checked_key(kind, name, factor, overrides.check_factor), { factor = factor })
  end,
  --- Removes the override of `kind`/`name`, if any.
  clear_value = function(kind, name)
    set_override(checked_key(kind, name), nil)
  end,
  --- The current base value of `kind`/`name` in credits, or nil when it has none.
  get_value = function(kind, name)
    local key = checked_key(kind, name)
    if not storage.base_values then value_overrides.rebuild() end
    return storage.base_values[key]
  end,
}

return value_overrides
