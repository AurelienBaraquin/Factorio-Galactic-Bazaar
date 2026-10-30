-- Value overrides by other mods and settings (ADR-0007). Pure Lua.
--
-- An override either fixes a key's value in credits ({value = v}) or scales the value the graph
-- gives it ({factor = f}). The global multiplier scales every value; a fixed value is final, so it
-- is divided by the multiplier before valuation and comes out exact.
local overrides = {}

local function is_positive_finite(n)
  return type(n) == "number" and n == n and n > 0 and n < math.huge
end

--- nil when `number` is a valid value or factor (positive and finite), else a reason.
function overrides.check_number(number)
  if not is_positive_finite(number) then return "must be a positive finite number" end
  return nil
end

--- Whether any override scales the graph's value (a second valuation pass is needed).
function overrides.has_factors(entries)
  for _, entry in pairs(entries) do
    if entry.factor then return true end
  end
  return false
end

--- Fixed values for the valuation, before the multiplier. `first_pass` (optional) holds the
--- values computed with fixed values only; factors are applied to it, and ignored without it or
--- when the key has no value there.
function overrides.fixed(entries, multiplier, first_pass)
  local fixed = {}
  for key, entry in pairs(entries) do
    if entry.value then
      fixed[key] = entry.value / multiplier
    elseif first_pass and first_pass[key] then
      fixed[key] = first_pass[key] * entry.factor
    end
  end
  return fixed
end

--- A copy of `values` scaled by `multiplier`; keys with a fixed value keep it exactly.
function overrides.apply_multiplier(values, entries, multiplier)
  local scaled = {}
  for key, value in pairs(values) do
    local entry = entries[key]
    scaled[key] = entry and entry.value or value * multiplier
  end
  return scaled
end

return overrides
