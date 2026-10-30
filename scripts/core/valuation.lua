-- Base value of every item and fluid, from the production graph of scripts/core/recipe_graph.lua
-- (ADR-0002). Pure Lua.
--
-- A recipe offers a value to each of its outputs once all its inputs have one:
-- (recipe cost + sum of input values) / number of outputs / expected amount of that output. So a
-- recipe with several outputs gives each an equal share of its cost, whatever the amounts, and a
-- rare by-product (0.7 % uranium-235) is worth far more per unit than a common one. The value of a
-- key is the lowest offer it receives.
--
-- Every value remembers the keys it was derived from (its ancestors). A recipe never lowers an
-- output that is one of its inputs' ancestors, so a loop of recipes (melt and recast, fill and empty
-- a barrel) cannot pull a value below its real source; a cheaper path that does not go through the
-- key itself always can (Kovarex for uranium-235, coal liquefaction for heavy oil). Each accepted
-- offer strictly lowers a value along an acyclic derivation, so the process ends.
--
-- Sources tied to one place come in later passes, each of which may only price keys the previous
-- passes left without a value, so they never undercut a general production chain: first the
-- fallback (planet-bound processes, non-primary tile fluids), then natural sources (trees, rocks,
-- fish, plants, asteroid chunks), so that a process beats scavenging.
--
-- Fixed values (overrides by settings or other mods) are set before any recipe and never replaced:
-- they act as sources, and every product made from them follows.
local valuation = {}

-- No key is worth less than this: a recipe with no inputs and no cost must not create free goods.
valuation.MIN_VALUE = 1e-6

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- Freezes each recipe's key order so floating-point sums never depend on table iteration.
local function prepare(recipe)
  return {
    cost = recipe.cost, inputs = recipe.inputs, input_keys = sorted_keys(recipe.inputs),
    outputs = recipe.outputs, output_keys = sorted_keys(recipe.outputs),
  }
end

local function new_state(fixed)
  return { values = {}, ancestors = {}, consumers = {}, queue = {}, queued = {}, fixed = fixed or {} }
end

local function push(state, key)
  if not state.queued[key] then
    state.queued[key] = true
    state.queue[#state.queue + 1] = key
  end
end

-- Offers the recipe's outputs a value, if all its inputs have one. `allowed` (optional) limits the
-- outputs it may price.
local function offer(state, recipe, allowed)
  local total, ancestors = recipe.cost, {}
  for _, key in ipairs(recipe.input_keys) do
    local value = state.values[key]
    if not value then return end
    total = total + value * recipe.inputs[key]
    ancestors[key] = true
    for ancestor in pairs(state.ancestors[key]) do ancestors[ancestor] = true end
  end
  local share = total / #recipe.output_keys
  for _, key in ipairs(recipe.output_keys) do
    if not ancestors[key] and not state.fixed[key] and (not allowed or allowed[key]) then
      local candidate = math.max(share / recipe.outputs[key], valuation.MIN_VALUE)
      local current = state.values[key]
      if not current or candidate < current then
        state.values[key] = candidate
        state.ancestors[key] = ancestors
        push(state, key)
      end
    end
  end
end

local function add(state, recipe, allowed)
  for _, key in ipairs(recipe.input_keys) do
    state.consumers[key] = state.consumers[key] or {}
    table.insert(state.consumers[key], recipe)
  end
  offer(state, recipe, allowed)
end

-- Re-offers every recipe that consumes a key whose value changed, until nothing changes.
local function settle(state, allowed)
  local index = 1
  while index <= #state.queue do
    local key = state.queue[index]
    state.queued[key] = nil
    index = index + 1
    for _, recipe in ipairs(state.consumers[key] or {}) do offer(state, recipe, allowed) end
  end
  state.queue = {}
end

local function wanted_keys(graph, keys)
  local wanted = {}
  for _, key in ipairs(keys or {}) do wanted[key] = true end
  for _, list in ipairs({ graph.recipes, graph.fallback, graph.natural }) do
    for _, recipe in ipairs(list) do
      for key in pairs(recipe.inputs) do wanted[key] = true end
      for key in pairs(recipe.outputs) do wanted[key] = true end
    end
  end
  return sorted_keys(wanted)
end

--- Returns {values = {[key] = credits}, unpriced = sorted keys with no value}. `keys` lists every
--- key that should have a value (all items and fluids); keys only seen in recipes are added.
--- `fixed` (optional) maps keys to values that recipes may not change.
function valuation.compute(graph, keys, fixed)
  local state = new_state(fixed)
  for _, key in ipairs(sorted_keys(state.fixed)) do
    state.values[key] = math.max(state.fixed[key], valuation.MIN_VALUE)
    state.ancestors[key] = {}
  end
  local main = {}
  for i, recipe in ipairs(graph.recipes) do
    main[i] = prepare(recipe)
    add(state, main[i])
  end
  settle(state)

  local all_keys = wanted_keys(graph, keys)
  local earlier = main
  for _, tier in ipairs({ graph.fallback, graph.natural }) do
    local missing = {}
    for _, key in ipairs(all_keys) do
      if not state.values[key] then missing[key] = true end
    end
    local prepared = {}
    for i, recipe in ipairs(tier) do prepared[i] = prepare(recipe) end
    for _, recipe in ipairs(prepared) do add(state, recipe, missing) end
    for _, recipe in ipairs(earlier) do offer(state, recipe, missing) end
    settle(state, missing)
    for _, recipe in ipairs(prepared) do earlier[#earlier + 1] = recipe end
  end

  local unpriced = {}
  for _, key in ipairs(all_keys) do
    if not state.values[key] then unpriced[#unpriced + 1] = key end
  end
  return { values = state.values, unpriced = unpriced }
end

return valuation
