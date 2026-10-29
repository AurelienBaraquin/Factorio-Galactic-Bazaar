local recipe_graph = require("scripts.core.recipe_graph")

local function item(name, amount) return { type = "item", name = name, amount = amount } end
local function fluid(name, amount) return { type = "fluid", name = name, amount = amount } end

local function recipe(fields)
  fields.energy = fields.energy or 1
  fields.categories = fields.categories or { "crafting" }
  fields.enabled = fields.enabled ~= false
  fields.ingredients = fields.ingredients or {}
  fields.products = fields.products or {}
  return fields
end

local function build(fields)
  return recipe_graph.build({
    recipes = fields.recipes or {}, mined = fields.mined or {}, tile_fluids = fields.tile_fluids or {},
  })
end

local function find(list, name)
  for _, entry in ipairs(list) do
    if entry.name == name then return entry end
  end
end

describe("recipe_graph.expected_amount", function()
  it("uses the fixed amount", function()
    assert.are.equal(3, recipe_graph.expected_amount(item("gear", 3)))
  end)

  it("uses the mean of an amount range", function()
    assert.are.equal(3, recipe_graph.expected_amount({ type = "item", name = "x", amount_min = 2, amount_max = 4 }))
  end)

  it("treats a maximum below the minimum as the minimum, like the game", function()
    assert.are.equal(5, recipe_graph.expected_amount({ type = "item", name = "x", amount_min = 5, amount_max = 1 }))
  end)

  it("weights by independent probability and shared range, like uranium processing", function()
    local u235 = { type = "item", name = "uranium-235", amount = 1, independent_probability = 1,
      shared_probability = { min = 0, max = 0.007 } }
    assert.is_true(math.abs(recipe_graph.expected_amount(u235) - 0.007) < 1e-12)
    local seed = { type = "item", name = "seed", amount = 1, independent_probability = 0.02 }
    assert.is_true(math.abs(recipe_graph.expected_amount(seed) - 0.02) < 1e-12)
  end)

  it("adds the extra count fraction before applying the chance", function()
    local product = { type = "item", name = "x", amount = 1, extra_count_fraction = 0.5, independent_probability = 0.5 }
    assert.are.equal(0.75, recipe_graph.expected_amount(product))
  end)
end)

describe("recipe_graph.build", function()
  it("keys items and fluids separately and charges crafting time", function()
    local graph = build({ recipes = {
      recipe({ name = "barrel-fill", energy = 0.2, ingredients = { item("barrel", 1), fluid("water", 50) },
        products = { item("water-barrel", 1) } }),
    } })
    local built = graph.recipes[1]
    assert.are.same({ ["item/barrel"] = 1, ["fluid/water"] = 50 }, built.inputs)
    assert.are.same({ ["item/water-barrel"] = 1 }, built.outputs)
    assert.is_true(math.abs(built.cost - 0.2 * recipe_graph.TIME_COST) < 1e-12)
  end)

  it("nets out catalysts, like the Kovarex process", function()
    local graph = build({ recipes = {
      recipe({ name = "kovarex", energy = 60, ingredients = { item("u235", 40), item("u238", 5) },
        products = { item("u235", 41), item("u238", 2) } }),
    } })
    local built = graph.recipes[1]
    assert.are.same({ ["item/u238"] = 3 }, built.inputs)
    assert.are.same({ ["item/u235"] = 1 }, built.outputs)
  end)

  it("excludes recycling, parameter, hidden and unreachable recipes with their reason", function()
    local graph = build({ recipes = {
      recipe({ name = "gear-recycling", categories = { "recycling" }, products = { item("plate", 1) } }),
      recipe({ name = "parameter-0", parameter = true, products = { item("plate", 1) } }),
      recipe({ name = "pistol", hidden = true, products = { item("pistol", 1) } }),
      recipe({ name = "loader", enabled = false, unlocked = false, products = { item("loader", 1) } }),
      recipe({ name = "unlocked-later", enabled = false, unlocked = true, products = { item("x", 1) } }),
    } })
    assert.are.same({ ["gear-recycling"] = "recycling", ["parameter-0"] = "parameter", pistol = "hidden",
      loader = "unreachable" }, graph.excluded)
    assert.are.equal(1, #graph.recipes)
    assert.are.equal("unlocked-later", graph.recipes[1].name)
  end)

  it("excludes an unpacking recipe that exactly undoes a packing one, like emptying a barrel", function()
    local graph = build({ recipes = {
      recipe({ name = "water-barrel", energy = 0.2, ingredients = { item("barrel", 1), fluid("water", 50) },
        products = { item("water-barrel", 1) } }),
      recipe({ name = "empty-water-barrel", energy = 0.2, ingredients = { item("water-barrel", 1) },
        products = { item("barrel", 1), fluid("water", 50) } }),
      recipe({ name = "uranium-processing", ingredients = { item("uranium-ore", 10) },
        products = { item("uranium-235", 1), item("uranium-238", 9) } }),
    } })
    assert.are.equal("inverse", graph.excluded["empty-water-barrel"])
    assert.is_nil(graph.excluded["water-barrel"])
    assert.is_nil(graph.excluded["uranium-processing"])
    assert.are.equal(2, #graph.recipes)
  end)

  it("excludes a recipe that gives back everything it consumes", function()
    local graph = build({ recipes = {
      recipe({ name = "loop", ingredients = { item("a", 2) }, products = { item("a", 2) } }),
    } })
    assert.are.equal("no-net-output", graph.excluded.loop)
  end)

  it("turns resources into mining recipes, with their fluid counted per 10 operations", function()
    local graph = build({ mined = {
      { name = "uranium-ore", kind = "resource", mining_time = 2, required_fluid = "sulfuric-acid", fluid_amount = 10,
        products = { item("uranium-ore", 1) } },
      { name = "crude-oil", kind = "resource", mining_time = 1, products = { fluid("crude-oil", 10) } },
    } })
    local uranium = find(graph.recipes, "mine/uranium-ore")
    assert.are.same({ ["fluid/sulfuric-acid"] = 1 }, uranium.inputs)
    assert.are.equal(2 * recipe_graph.MINING_COST, uranium.cost)
    assert.are.same({ ["fluid/crude-oil"] = 10 }, find(graph.recipes, "mine/crude-oil").outputs)
  end)

  it("keeps natural sources as fallback and ignores buildings that return their item", function()
    local graph = build({ mined = {
      { name = "tree-01", kind = "tree", mining_time = 0.5, products = { item("wood", 4) } },
      { name = "big-rock", kind = "simple-entity", mining_time = 2, products = { item("stone", 20) } },
      { name = "iron-chest", kind = "container", mining_time = 0.1, products = { item("iron-chest", 1) } },
    } })
    assert.are.equal(0, #graph.recipes)
    assert.are.equal(2, #graph.fallback)
    assert.are.equal("mine/big-rock", graph.fallback[1].name)
    assert.are.equal("mine/tree-01", graph.fallback[2].name)
  end)

  it("pumps primary tile fluids in the main graph and the others as fallback", function()
    local graph = build({ tile_fluids = { water = true, lava = true } })
    assert.are.equal(1, #graph.recipes)
    assert.are.same({ ["fluid/water"] = 1 }, graph.recipes[1].outputs)
    assert.are.equal(recipe_graph.TILE_FLUID_COST, graph.recipes[1].cost)
    assert.are.equal("pump/lava", graph.fallback[1].name)
  end)

  it("sorts recipes by name, whatever the input order", function()
    local graph = build({ recipes = {
      recipe({ name = "b", products = { item("b", 1) } }), recipe({ name = "a", products = { item("a", 1) } }),
    } })
    assert.are.equal("a", graph.recipes[1].name)
    assert.are.equal("b", graph.recipes[2].name)
  end)
end)
