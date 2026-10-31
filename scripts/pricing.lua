-- Computes the base value of every item and fluid from the game's prototypes (ADR-0002) and keeps it
-- in storage.base_values. Base values depend only on prototypes, the startup multiplier and the
-- overrides set by other mods (ADR-0007, stored in storage.value_overrides by
-- scripts/value_overrides.lua), so they are shared by all forces and recomputed whenever one of
-- those may have changed.
local overrides = require("scripts.core.overrides")
local quality = require("scripts.core.quality")
local raw_graph = require("scripts.recipe_graph")
local recipe_graph = require("scripts.core.recipe_graph")
local valuation = require("scripts.core.valuation")

local pricing = {}

pricing.MULTIPLIER_SETTING = "gb-value-multiplier"

--- Key of an item or fluid in base values and markets: "item/<name>" or "fluid/<name>", with
--- "@<quality>" for an item of a quality other than normal (ADR-0008).
function pricing.key(kind, name, quality_name)
  return quality.key(kind .. "/" .. name, quality_name)
end

-- Overrides of keys that are still tradeable; the others are kept for when they come back.
-- Malformed entries (none can be stored through the remote checks) are dropped.
local function active_overrides(keys)
  local tradeable, active, malformed = {}, {}, {}
  for _, key in ipairs(keys) do tradeable[key] = true end
  for key, entry in pairs(storage.value_overrides) do
    if not overrides.is_valid(entry) then
      malformed[#malformed + 1] = key
    elseif tradeable[key] then
      active[key] = entry
    else
      log("[galactic-bazaar] value override of " .. key .. " ignored: not a tradeable item or fluid")
    end
  end
  for _, key in ipairs(malformed) do storage.value_overrides[key] = nil end
  return active
end

-- Base values with the multiplier and the overrides applied: one valuation pass with the fixed
-- values, and a second one when a factor needs the first pass's value of its key. Also returns the
-- source of each value before the multiplier (valuation.compute): a key scaled by a factor keeps the
-- source the first pass gave it, which the factor multiplies.
local function compute()
  local graph = recipe_graph.build(raw_graph.extract())
  local multiplier = settings.startup[pricing.MULTIPLIER_SETTING].value
  local entries = active_overrides(graph.keys)
  local result = valuation.compute(graph, graph.keys, overrides.fixed(entries, multiplier))
  local sources = result.sources
  if overrides.has_factors(entries) then
    local first_pass = result
    result = valuation.compute(graph, graph.keys, overrides.fixed(entries, multiplier, first_pass))
    sources = result.sources
    for key, entry in pairs(entries) do
      if entry.factor then sources[key] = first_pass.sources[key] end
    end
  end
  return overrides.apply_multiplier(result.values, entries, multiplier), result.unpriced, sources, result.tiers
end

--- Rebuilds storage.base_values (on_init, on_configuration_changed, after an override changes;
--- callers then rebase the markets, see scripts/value_overrides.lua).
function pricing.init()
  storage.value_overrides = storage.value_overrides or {}
  local values, unpriced, sources, tiers = compute()
  storage.base_values = values
  -- Why each value is what it is, for the Market tab's detail: kept for the keys with a value only.
  storage.value_sources = {}
  for key in pairs(values) do
    local source = sources[key]
    if source then
      source.tier = tiers[key]
      storage.value_sources[key] = source
    end
  end
  storage.tradeable_items = {}
  for key in pairs(values) do
    local name = key:match("^item/(.+)$")
    if name and prototypes.item[name] then table.insert(storage.tradeable_items, name) end
  end
  table.sort(storage.tradeable_items)
  storage.tradeable_fluids = {}
  for key in pairs(values) do
    local name = key:match("^fluid/(.+)$")
    if name and prototypes.fluid[name] then table.insert(storage.tradeable_fluids, name) end
  end
  table.sort(storage.tradeable_fluids)
  -- "normal" is hidden when no quality mod is active, but it is always the quality of plain items.
  storage.quality_levels = { [quality.NORMAL] = 0 }
  for name, prototype in pairs(prototypes.quality) do
    if not prototype.hidden then storage.quality_levels[name] = prototype.level end
  end
  if #unpriced > 0 then
    log("[galactic-bazaar] no base value (not tradeable): " .. table.concat(unpriced, ", "))
  end
end

--- Value in credits of a market key (any quality) and its ratio to the normal value, given the
--- normal base values `values` and quality levels `levels` (default: the current ones); nil when
--- it has none: not tradeable, a fluid with a quality, or a quality that does not exist (or is
--- hidden).
function pricing.key_value(key, values, levels)
  values = values or storage.base_values
  if values[key] then return values[key], 1 end
  local base_key, quality_name = quality.split(key)
  local normal_value = values[base_key]
  local level = (levels or storage.quality_levels or {})[quality_name]
  if not (normal_value and level) or base_key:sub(1, 5) ~= "item/" then return nil end
  local value = quality.value(normal_value, level)
  return value, value / normal_value
end

--- Why the normal key `key` is worth what it is: the valuation's record of the offer that set its value
--- before the multiplier, {recipe, cost, share, amount, inputs = {{key, amount, value}...}, tier};
--- nil for a value fixed by an override, a key without a value, or a save whose values were last
--- built before 0.1.34 (until its configuration change rebuilds them).
function pricing.value_source(key)
  return storage.value_sources and storage.value_sources[key]
end

--- Base value of an item or fluid in credits at a quality (default normal), or nil when it has none
--- (not tradeable).
function pricing.base_value(kind, name, quality_name)
  return pricing.key_value(pricing.key(kind, name, quality_name))
end

return pricing
