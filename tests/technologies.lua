-- In-game tests of the mod's research (#68): every Galactic Bazaar technology uses vanilla science
-- packs only, needs at least the packs of its prerequisites, and unlocks recipes whose ingredients
-- its own prerequisites (or the start of the game) already give.
local VANILLA_PACKS = {
  ["automation-science-pack"] = true, ["logistic-science-pack"] = true, ["military-science-pack"] = true,
  ["chemical-science-pack"] = true, ["production-science-pack"] = true, ["utility-science-pack"] = true,
  ["space-science-pack"] = true,
}

local function ours()
  local list = {}
  for name, technology in pairs(prototypes.technology) do
    if name:sub(1, 3) == "gb-" then list[#list + 1] = technology end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function packs(technology)
  local set = {}
  for _, ingredient in ipairs(technology.research_unit_ingredients) do set[ingredient.name] = true end
  return set
end

-- Every technology needed before `technology`, itself included.
local function ancestors(technology, seen)
  seen = seen or {}
  if seen[technology.name] then return seen end
  seen[technology.name] = true
  for _, prerequisite in pairs(technology.prerequisites) do ancestors(prerequisite, seen) end
  return seen
end

-- Whether an item can be made once `known` technologies are researched: a recipe making it is
-- enabled at the start or unlocked by one of them.
local function makeable(item, known)
  for _, recipe in pairs(prototypes.get_recipe_filtered({ { filter = "has-product-item", elem_filters = {
    { filter = "name", name = item } } } })) do
    if recipe.enabled and not recipe.hidden then return true end
    for name in pairs(known) do
      for _, effect in pairs(prototypes.technology[name].effects) do
        if effect.type == "unlock-recipe" and effect.recipe == recipe.name and not recipe.hidden then return true end
      end
    end
  end
  return false
end

describe("research", function()
  test("uses vanilla science packs only", function()
    for _, technology in ipairs(ours()) do
      for name in pairs(packs(technology)) do assert.is_true(VANILLA_PACKS[name], technology.name .. ": " .. name) end
    end
  end)

  test("never needs fewer science packs than a prerequisite", function()
    for _, technology in ipairs(ours()) do
      local own = packs(technology)
      for _, prerequisite in pairs(technology.prerequisites) do
        for name in pairs(packs(prerequisite)) do
          assert.is_true(own[name], technology.name .. " lacks " .. name .. " of " .. prerequisite.name)
        end
      end
    end
  end)

  test("unlocks recipes whose ingredients its prerequisites already give", function()
    for _, technology in ipairs(ours()) do
      local known = ancestors(technology)
      for _, effect in pairs(technology.effects) do
        if effect.type == "unlock-recipe" then
          for _, ingredient in ipairs(prototypes.recipe[effect.recipe].ingredients) do
            assert.is_true(makeable(ingredient.name, known), technology.name .. ": " .. ingredient.name)
          end
        end
      end
    end
  end)
end)
