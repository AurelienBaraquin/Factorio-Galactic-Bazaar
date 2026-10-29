-- Base value of every item and fluid, from the production graph of scripts/core/recipe_graph.lua
-- (ADR-0002). Pure Lua.
--
-- The value of a key is the cheapest way to make one unit of it: over every recipe producing it,
-- (recipe cost + sum of input values) shared among the recipe's outputs. A recipe with several
-- outputs gives each output an equal share of its cost, whatever the amounts, so a rare by-product
-- (0.7 % uranium-235) is worth far more per unit than a common one, and another recipe can still
-- undercut that share (Kovarex for uranium-235). The share does not depend on values, which keeps
-- the problem a monotone least fixed point (ADR-0002).
--
-- Two passes: the main graph first, then the fallback sources (natural sources and tile fluids),
-- which may only price keys the main graph left without a value, so that a source tied to one place
-- (an asteroid field, a heavy-oil sea) never undercuts a general production chain.
local valuation = {}

valuation.MAX_ITERATIONS = 500
-- Relative change under which a value is considered stable.
valuation.TOLERANCE = 1e-9
-- No key is worth less than this: a recipe with no inputs and no cost must not create free goods.
valuation.MIN_VALUE = 1e-6

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- Freezes each recipe's key order so floating-point sums never depend on table iteration.
local function prepare(recipes, allowed_outputs)
  local prepared = {}
  for _, recipe in ipairs(recipes) do
    local outputs = {}
    for _, key in ipairs(sorted_keys(recipe.outputs)) do
      if not allowed_outputs or allowed_outputs[key] then outputs[#outputs + 1] = key end
    end
    if #outputs > 0 then
      prepared[#prepared + 1] = {
        cost = recipe.cost, inputs = recipe.inputs, input_keys = sorted_keys(recipe.inputs),
        outputs = recipe.outputs, output_keys = outputs,
      }
    end
  end
  return prepared
end

local function recipe_total(recipe, values)
  local total = recipe.cost
  for _, key in ipairs(recipe.input_keys) do
    local value = values[key]
    if not value then return nil end
    total = total + value * recipe.inputs[key]
  end
  return total
end

local function offer(candidates, recipe, values)
  local total = recipe_total(recipe, values)
  if not total then return end
  local share = total / #recipe.output_keys
  for _, key in ipairs(recipe.output_keys) do
    local candidate = math.max(share / recipe.outputs[key], valuation.MIN_VALUE)
    if not candidates[key] or candidate < candidates[key] then candidates[key] = candidate end
  end
end

local function stable(previous, current)
  for key, value in pairs(current) do
    local before = previous[key]
    if not before or math.abs(value - before) > valuation.TOLERANCE * math.max(value, before) then return false end
  end
  return true
end

-- Values only ever decrease from one iteration to the next (each candidate is a non-decreasing
-- function of input values, and the set of usable recipes only grows), so the iteration converges
-- to the least fixed point, whatever the recipe order. `pinned` values (from an earlier pass) are
-- kept as they are and only feed the recipes.
local function iterate(prepared, pinned)
  local previous = {}
  for key, value in pairs(pinned) do previous[key] = value end
  for iteration = 1, valuation.MAX_ITERATIONS do
    local candidates = {}
    for key, value in pairs(pinned) do candidates[key] = value end
    for _, recipe in ipairs(prepared) do offer(candidates, recipe, previous) end
    if stable(previous, candidates) then return candidates, iteration, true end
    previous = candidates
  end
  return previous, valuation.MAX_ITERATIONS, false
end

local function collect_keys(recipes, keys)
  for _, recipe in ipairs(recipes) do
    for key in pairs(recipe.inputs) do keys[key] = true end
    for key in pairs(recipe.outputs) do keys[key] = true end
  end
  return keys
end

--- Returns {values = {[key] = credits}, unpriced = sorted keys with no value, iterations, converged}.
function valuation.compute(graph)
  local recipes = prepare(graph.recipes)
  local values, iterations, converged = iterate(recipes, {})
  local all_keys = collect_keys(graph.fallback, collect_keys(graph.recipes, {}))
  local missing = {}
  for key in pairs(all_keys) do
    if not values[key] then missing[key] = true end
  end
  if next(missing) then
    local second_pass = prepare(graph.recipes, missing)
    for _, recipe in ipairs(prepare(graph.fallback, missing)) do second_pass[#second_pass + 1] = recipe end
    local more_iterations, fallback_converged
    values, more_iterations, fallback_converged = iterate(second_pass, values)
    iterations, converged = iterations + more_iterations, converged and fallback_converged
  end
  local unpriced = {}
  for _, key in ipairs(sorted_keys(all_keys)) do
    if not values[key] then unpriced[#unpriced + 1] = key end
  end
  return { values = values, unpriced = unpriced, iterations = iterations, converged = converged }
end

return valuation
