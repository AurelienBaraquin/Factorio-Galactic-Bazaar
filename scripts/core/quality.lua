-- Value of items by quality (ADR-0008). Pure Lua.
--
-- A quality's value is the normal value times FACTOR_PER_LEVEL to the power of the quality's level
-- (Space Age: uncommon 1, rare 2, epic 3, legendary 5). Its market is as deep in units as the
-- normal one (its depth in credits grows with the same ratio), so a valuable quality still sells.
-- Without a quality mod only "normal" exists, so nothing changes.
local quality = {}

quality.FACTOR_PER_LEVEL = 3
quality.NORMAL = "normal"

--- Value of one item of a quality at `level`, from its normal value.
function quality.value(normal_value, level)
  return normal_value * quality.FACTOR_PER_LEVEL ^ level
end

--- Market key of an item at a quality: the normal key itself for normal quality (or none), so
--- existing saves and fluids keep their keys; "<key>@<quality>" otherwise.
function quality.key(base_key, quality_name)
  if quality_name == nil or quality_name == quality.NORMAL then return base_key end
  return base_key .. "@" .. quality_name
end

--- The normal key and the quality name of a market key, split at the last "@" (a modded item name
--- may contain one: callers check the quality exists).
function quality.split(key)
  local base_key, quality_name = key:match("^(.*)@([^@]+)$")
  if base_key then return base_key, quality_name end
  return key, quality.NORMAL
end

return quality
