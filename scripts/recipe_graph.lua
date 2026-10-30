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
    if not technology.hidden then
      for _, effect in pairs(technology.effects) do
        if effect.type == "unlock-recipe" then unlocked[effect.recipe] = true end
      end
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
    if source then sources[#sources + 1] = source end
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

local GROUPS = { item = "item", fluid = "fluid" }

--- Whether `kind`/`name` ("item"/"fluid") is an item or fluid a player could trade: it exists, is
--- not hidden, not a blueprint parameter, and not a tool that only exists in the cursor
--- (blueprints, planners, remotes and wires are all "spawnable").
function recipe_graph.is_tradeable(kind, name)
  local group = GROUPS[kind] and prototypes[GROUPS[kind]]
  local prototype = group and type(name) == "string" and group[name]
  if not prototype then return false end
  local spawnable = kind == "item" and prototype.flags and prototype.flags.spawnable
  return not (prototype.hidden or prototype.parameter or spawnable)
end

local function tradeable_keys()
  local keys = {}
  for kind, group in pairs({ item = prototypes.item, fluid = prototypes.fluid }) do
    for name in pairs(group) do
      if recipe_graph.is_tradeable(kind, name) then keys[#keys + 1] = kind .. "/" .. name end
    end
  end
  table.sort(keys)
  return keys
end

-- Items that yield something when launched in a rocket, with the rocket parts one launch needs: the
-- silo needing the fewest parts, and the product of its fixed recipe.
local function copy_launches()
  local silo
  for _, entity in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "rocket-silo" } })) do
    if entity.fixed_recipe and (not silo or entity.rocket_parts_required < silo.rocket_parts_required) then
      silo = entity
    end
  end
  if not silo then return {} end
  local part = silo.fixed_recipe.products[1]
  local launches = {}
  for name, item in pairs(prototypes.item) do
    local products = item.rocket_launch_products
    if products and #products > 0 then
      launches[#launches + 1] = {
        item = name, products = copy_amounts(products), part = part.name, parts = silo.rocket_parts_required,
      }
    end
  end
  return launches
end

--- Returns the raw graph as plain tables (see scripts/core/recipe_graph.lua for the format).
function recipe_graph.extract()
  return {
    recipes = copy_recipes(),
    mined = copy_mined_sources(),
    tile_fluids = copy_tile_fluids(),
    launches = copy_launches(),
    keys = tradeable_keys(),
  }
end

return recipe_graph
