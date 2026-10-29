-- Copies the recipe, item, fluid and mining prototypes into plain tables for
-- scripts/core/recipe_graph.lua. Makes no pricing decision: it only reads the game.
local recipe_graph = {}

local function copy_amounts(entries)
  local copies = {}
  for i, entry in ipairs(entries or {}) do
    copies[i] = {
      type = entry.type,
      name = entry.name,
      amount = entry.amount,
      amount_min = entry.amount_min,
      amount_max = entry.amount_max,
      independent_probability = entry.independent_probability,
      shared_probability = entry.shared_probability,
      extra_count_fraction = entry.extra_count_fraction,
    }
  end
  return copies
end

local function unlocked_recipes()
  local unlocked = {}
  for _, technology in pairs(prototypes.technology) do
    for _, effect in pairs(technology.effects) do
      if effect.type == "unlock-recipe" then unlocked[effect.recipe] = true end
    end
  end
  return unlocked
end

local function copy_recipes()
  local unlocked = unlocked_recipes()
  local recipes = {}
  for name, recipe in pairs(prototypes.recipe) do
    recipes[#recipes + 1] = {
      name = name,
      energy = recipe.energy,
      categories = recipe.categories,
      hidden = recipe.hidden,
      parameter = recipe.parameter,
      enabled = recipe.enabled,
      unlocked = unlocked[name] == true,
      ingredients = copy_amounts(recipe.ingredients),
      products = copy_amounts(recipe.products),
    }
  end
  return recipes
end

local function copy_mining(name, kind, properties)
  if not (properties and properties.minable and properties.products) then return nil end
  return {
    name = name,
    kind = kind,
    mining_time = properties.mining_time,
    products = copy_amounts(properties.products),
    required_fluid = properties.required_fluid,
    fluid_amount = properties.fluid_amount,
  }
end

local function copy_mined_sources()
  local sources = {}
  for name, entity in pairs(prototypes.entity) do
    local source = copy_mining(name, entity.type, entity.mineable_properties)
    if source then
      source.infinite = entity.type == "resource" and entity.infinite_resource or nil
      sources[#sources + 1] = source
    end
  end
  for name, chunk in pairs(prototypes.asteroid_chunk) do
    local source = copy_mining(name, "asteroid-chunk", chunk.mineable_properties)
    if source then sources[#sources + 1] = source end
  end
  return sources
end

local function copy_tile_fluids()
  local fluids = {}
  for _, tile in pairs(prototypes.tile) do
    if tile.fluid then fluids[tile.fluid.name] = true end
  end
  return fluids
end

local function copy_item_results()
  local items = {}
  for name, item in pairs(prototypes.item) do
    items[name] = {
      hidden = item.hidden,
      parameter = item.parameter,
      spoil_result = item.spoil_result and item.spoil_result.name,
      burnt_result = item.burnt_result and item.burnt_result.name,
    }
  end
  return items
end

local function copy_fluids()
  local fluids = {}
  for name, fluid in pairs(prototypes.fluid) do
    fluids[name] = { hidden = fluid.hidden, parameter = fluid.parameter }
  end
  return fluids
end

--- Returns the raw graph as plain tables (see scripts/core/recipe_graph.lua for the format).
function recipe_graph.extract()
  return {
    recipes = copy_recipes(),
    mined = copy_mined_sources(),
    tile_fluids = copy_tile_fluids(),
    items = copy_item_results(),
    fluids = copy_fluids(),
  }
end

return recipe_graph
