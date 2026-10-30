-- Computes the base value of every item and fluid from the game's prototypes (ADR-0002) and keeps it
-- in storage.base_values. Base values depend only on prototypes, the startup multiplier and the
-- overrides set by other mods (ADR-0007), so they are shared by all forces and recomputed whenever
-- one of those may have changed. Overrides persist in storage.value_overrides.
local overrides = require("scripts.core.overrides")
local raw_graph = require("scripts.recipe_graph")
local recipe_graph = require("scripts.core.recipe_graph")
local valuation = require("scripts.core.valuation")

local pricing = {}

pricing.MULTIPLIER_SETTING = "gb-value-multiplier"

--- Key of an item or fluid in base values and markets: "item/<name>" or "fluid/<name>".
function pricing.key(kind, name)
  return kind .. "/" .. name
end

-- Overrides of keys that are still tradeable; the others are kept for when they come back.
local function active_overrides(keys)
  local tradeable, active = {}, {}
  for _, key in ipairs(keys) do tradeable[key] = true end
  for key, entry in pairs(storage.value_overrides) do
    if tradeable[key] then
      active[key] = entry
    else
      log("[galactic-bazaar] value override of " .. key .. " ignored: not a tradeable item or fluid")
    end
  end
  return active
end

-- Base values with the multiplier and the overrides applied: one valuation pass with the fixed
-- values, and a second one when a factor needs the first pass's value of its key.
local function compute()
  local graph = recipe_graph.build(raw_graph.extract())
  local multiplier = settings.startup[pricing.MULTIPLIER_SETTING].value
  local entries = active_overrides(graph.keys)
  local result = valuation.compute(graph, graph.keys, overrides.fixed(entries, multiplier))
  if overrides.has_factors(entries) then
    result = valuation.compute(graph, graph.keys, overrides.fixed(entries, multiplier, result.values))
  end
  return overrides.apply_multiplier(result.values, entries, multiplier), result.unpriced
end

--- on_init, on_configuration_changed and after an override changes: rebuilds storage.base_values.
function pricing.init()
  storage.value_overrides = storage.value_overrides or {}
  local values, unpriced = compute()
  storage.base_values = values
  storage.tradeable_items = {}
  for key in pairs(values) do
    local name = key:match("^item/(.+)$")
    if name and prototypes.item[name] then table.insert(storage.tradeable_items, name) end
  end
  table.sort(storage.tradeable_items)
  if #unpriced > 0 then
    log("[galactic-bazaar] no base value (not tradeable): " .. table.concat(unpriced, ", "))
  end
end

--- Base value of an item or fluid in credits, or nil when it has none (not tradeable).
function pricing.base_value(kind, name)
  return storage.base_values[pricing.key(kind, name)]
end

-- Raises an error naming the caller's mistake: remote calls come from other mods' code.
local function check(kind, name, number)
  if not raw_graph.is_tradeable(kind, name) then
    error("galactic-bazaar: " .. tostring(kind) .. "/" .. tostring(name) .. " is not a tradeable item or fluid", 3)
  end
  local reason = number ~= nil and overrides.check_number(number)
  if reason then error("galactic-bazaar: " .. tostring(number) .. " " .. reason, 3) end
end

local function set_override(kind, name, entry)
  storage.value_overrides[pricing.key(kind, name)] = entry
  pricing.init()
end

--- The remote interface "galactic-bazaar" (ADR-0007, docs/pricing.md). Each change recomputes
--- every base value.
pricing.REMOTE = {
  --- Fixes the base value of `kind`/`name` ("item"/"fluid") to `credits`; products follow.
  set_value = function(kind, name, credits)
    check(kind, name, credits)
    set_override(kind, name, { value = credits })
  end,
  --- Scales the base value the production graph gives `kind`/`name` by `factor`; products follow.
  scale_value = function(kind, name, factor)
    check(kind, name, factor)
    set_override(kind, name, { factor = factor })
  end,
  --- Removes the override of `kind`/`name`, if any.
  clear_value = function(kind, name)
    check(kind, name)
    set_override(kind, name, nil)
  end,
  --- The current base value of `kind`/`name` in credits, or nil when it has none.
  get_value = function(kind, name)
    check(kind, name)
    return pricing.base_value(kind, name)
  end,
}

return pricing
