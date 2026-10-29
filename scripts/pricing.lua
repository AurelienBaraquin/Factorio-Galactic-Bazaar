-- Computes the base value of every item and fluid from the game's prototypes (ADR-0002) and keeps it
-- in storage.base_values. Base values depend only on prototypes, so they are shared by all forces and
-- recomputed whenever prototypes may have changed.
local raw_graph = require("scripts.recipe_graph")
local recipe_graph = require("scripts.core.recipe_graph")
local valuation = require("scripts.core.valuation")

local pricing = {}

--- on_init and on_configuration_changed: rebuilds storage.base_values.
function pricing.init()
  local result = valuation.compute(recipe_graph.build(raw_graph.extract()))
  storage.base_values = result.values
  if not result.converged then
    log("[galactic-bazaar] base values did not converge after " .. result.iterations .. " iterations")
  end
  if #result.unpriced > 0 then
    log("[galactic-bazaar] no base value (not tradeable): " .. table.concat(result.unpriced, ", "))
  end
end

--- Key of an item or fluid in base values and markets: "item/<name>" or "fluid/<name>".
function pricing.key(kind, name)
  return kind .. "/" .. name
end

--- Base value of an item or fluid in credits, or nil when it has none (not tradeable).
function pricing.base_value(kind, name)
  return storage.base_values[pricing.key(kind, name)]
end

return pricing
