-- Value overrides by other mods and settings (ADR-0007). Pure Lua.
--
-- An override either fixes a key's value in credits ({value = v}) or scales the value the graph
-- gives it ({factor = f}). The global multiplier scales every value; a fixed value is final, so it
-- is divided by the multiplier before valuation and comes out exact. A fixed value is a source from
-- the main tier on (the mod says what the key is worth); a factor keeps the tier the graph priced
-- the key in, so a factor of 1 changes nothing.
local valuation = require("scripts.core.valuation")

local overrides = {}

-- Accepted ranges. The smallest value stays at or above valuation.MIN_VALUE whatever the multiplier
-- (at most 100), and the largest keeps every sum of products finite.
overrides.VALUE_RANGE = { 1e-4, 1e12 }
overrides.FACTOR_RANGE = { 1e-6, 1e6 }

local function check(number, range)
  if type(number) ~= "number" or number ~= number or number < range[1] or number > range[2] then
    return "must be a number from " .. range[1] .. " to " .. range[2]
  end
  return nil
end

--- nil when `number` is a valid fixed value, else a reason.
function overrides.check_value(number)
  return check(number, overrides.VALUE_RANGE)
end

--- nil when `number` is a valid factor, else a reason.
function overrides.check_factor(number)
  return check(number, overrides.FACTOR_RANGE)
end

--- Whether a stored entry is well formed: exactly one valid value or factor.
function overrides.is_valid(entry)
  if type(entry) ~= "table" then return false end
  if entry.value ~= nil then return entry.factor == nil and overrides.check_value(entry.value) == nil end
  return entry.factor ~= nil and overrides.check_factor(entry.factor) == nil
end

--- Whether any override scales the graph's value (a second valuation pass is needed).
function overrides.has_factors(entries)
  for _, entry in pairs(entries) do
    if entry.factor then return true end
  end
  return false
end

--- Fixed values for valuation.compute, before the multiplier: {[key] = {value, tier}}. `first_pass`
--- (optional) is the result of a valuation with fixed values only; factors scale its value and
--- keep its tier, and are ignored without it or when the key has no value there.
function overrides.fixed(entries, multiplier, first_pass)
  local fixed = {}
  for key, entry in pairs(entries) do
    if entry.value then
      fixed[key] = { value = entry.value / multiplier, tier = valuation.MAIN }
    elseif first_pass and first_pass.values[key] then
      fixed[key] = { value = first_pass.values[key] * entry.factor, tier = first_pass.tiers[key] }
    end
  end
  return fixed
end

--- A copy of `values` scaled by `multiplier` and floored at valuation.MIN_VALUE; keys with a fixed
--- value keep it exactly.
function overrides.apply_multiplier(values, entries, multiplier)
  local scaled = {}
  for key, value in pairs(values) do
    local entry = entries[key]
    scaled[key] = entry and entry.value or math.max(value * multiplier, valuation.MIN_VALUE)
  end
  return scaled
end

return overrides
