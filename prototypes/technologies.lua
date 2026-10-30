-- Research that unlocks the terminal. Early in the tree and paid in red science only: the player
-- reaches the market as a local broker, then grows it through later technologies.
data:extend({
  {
    type = "technology",
    name = "gb-galactic-bazaar",
    icons = data.raw.item["gb-hub"].icons,
    icon_size = 64,
    prerequisites = { "electronics", "steel-processing" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-hub" },
      { type = "unlock-recipe", recipe = "gb-export-chest" },
      { type = "unlock-recipe", recipe = "gb-import-chest" },
    },
    unit = {
      count = 75,
      ingredients = { { "automation-science-pack", 1 } },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "gb-power-trading",
    icons = data.raw.item["gb-power-export"].icons,
    icon_size = 64,
    prerequisites = { "gb-galactic-bazaar", "electric-energy-distribution-1" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-power-export" },
      { type = "unlock-recipe", recipe = "gb-power-import" },
    },
    unit = {
      count = 150,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-power-trading-2",
    icons = data.raw.item["gb-power-import"].icons,
    icon_size = 64,
    prerequisites = { "gb-power-trading", "electric-energy-distribution-2" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-power-trading-2" } },
    },
    unit = {
      count = 300,
      ingredients = {
        { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 },
      },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-market-signals",
    icons = data.raw.item["gb-sell-price-combinator"].icons,
    icon_size = 64,
    prerequisites = { "gb-galactic-bazaar", "circuit-network" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-buy-price-combinator" },
      { type = "unlock-recipe", recipe = "gb-sell-price-combinator" },
    },
    unit = {
      count = 100,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "gb-market-orders",
    icons = data.raw.item["gb-order-combinator"].icons,
    icon_size = 64,
    prerequisites = { "gb-market-signals" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-order-combinator" },
    },
    unit = {
      count = 150,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 20,
    },
  },
})
