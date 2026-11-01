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
    -- Explicit keys: for a name ending in "-<number>" Factorio would look up the name without it.
    localised_name = { "technology-name.gb-power-trading-2" },
    localised_description = { "technology-description.gb-power-trading-2" },
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
  {
    type = "technology",
    name = "gb-telecommunications-1",
    localised_name = { "technology-name.gb-telecommunications-1" },
    localised_description = { "technology-description.gb-telecommunications-1" },
    icons = { { icon = "__base__/graphics/icons/radar.png", icon_size = 64 } },
    prerequisites = { "gb-galactic-bazaar", "logistic-science-pack" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-telecommunications-1" } },
    },
    unit = {
      count = 100,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "gb-telecommunications-2",
    localised_name = { "technology-name.gb-telecommunications-2" },
    localised_description = { "technology-description.gb-telecommunications-2" },
    icons = { { icon = "__base__/graphics/icons/radar.png", icon_size = 64 } },
    prerequisites = { "gb-telecommunications-1", "advanced-circuit" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-telecommunications-2" } },
      { type = "nothing", effect_description = { "technology-effect.gb-telecommunications-history" } },
    },
    unit = {
      count = 200,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-fluid-trading",
    icons = data.raw.item["gb-fluid-import"].icons,
    icon_size = 64,
    prerequisites = { "gb-galactic-bazaar", "fluid-handling" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-fluid-export" },
      { type = "unlock-recipe", recipe = "gb-fluid-import" },
    },
    unit = {
      count = 100,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "gb-cargo-shuttle",
    icons = data.raw.item["gb-docking-bay"].icons,
    icon_size = 64,
    prerequisites = { "gb-galactic-bazaar", "rocket-fuel", "electric-engine" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-docking-bay" },
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
    name = "gb-teleporter",
    icons = data.raw.item["gb-teleporter"].icons,
    icon_size = 64,
    prerequisites = { "gb-cargo-shuttle", "processing-unit", "low-density-structure", "production-science-pack",
      "utility-science-pack" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-teleporter" },
    },
    unit = {
      count = 500,
      ingredients = {
        { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 },
        { "production-science-pack", 1 }, { "utility-science-pack", 1 },
      },
      time = 60,
    },
  },
  {
    type = "technology",
    name = "gb-catapult",
    icons = data.raw.item["gb-catapult"].icons,
    icon_size = 64,
    prerequisites = { "gb-cargo-shuttle", "electric-energy-accumulators" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-catapult" },
    },
    unit = {
      count = 250,
      ingredients = {
        { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 },
      },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-contracts",
    icons = data.raw.item["gb-contract-chest"].icons,
    icon_size = 64,
    prerequisites = { "gb-galactic-bazaar", "logistic-science-pack" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-contract-chest" },
      { type = "nothing", effect_description = { "technology-effect.gb-contracts" } },
    },
    unit = {
      count = 100,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  {
    type = "technology",
    name = "gb-capacity-rental",
    icons = data.raw.item["gb-rental-assembler"].icons,
    icon_size = 64,
    prerequisites = { "gb-contracts", "automation-2" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-rental-assembler" },
    },
    unit = {
      count = 150,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  -- Storage rental (#119): both buildings, and both directions, scripts/vaults.lua and
  -- scripts/warehouses.lua read this technology.
  {
    type = "technology",
    name = "gb-storage-rental",
    icons = data.raw.item["gb-rental-warehouse"].icons,
    icon_size = 64,
    prerequisites = { "gb-contracts" },
    effects = {
      { type = "unlock-recipe", recipe = "gb-vault-uplink" },
      { type = "unlock-recipe", recipe = "gb-rental-warehouse" },
      { type = "nothing", effect_description = { "technology-effect.gb-storage-rental" } },
    },
    unit = {
      count = 150,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 15,
    },
  },
  -- Outsourcing branch (#88): NPC planets and their mining concessions, then slot booking in their
  -- foundries and assemblers. Effects are script-side: the scripts read these technologies.
  {
    type = "technology",
    name = "gb-planetary-concessions",
    icons = data.raw.item["gb-import-chest"].icons,
    icon_size = 64,
    prerequisites = { "gb-contracts" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-planetary-concessions" } },
    },
    unit = {
      count = 200,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-outsourcing",
    icons = data.raw.item["gb-rental-assembler"].icons,
    icon_size = 64,
    prerequisites = { "gb-planetary-concessions", "chemical-science-pack" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-outsourcing" } },
    },
    unit = {
      count = 300,
      ingredients = {
        { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 },
      },
      time = 30,
    },
  },
  -- Financial engineering branch (#98): credit unlocks loans, then each overdraft level raises the
  -- overdraft limit. Effects are script-side: scripts/finance.lua reads these technologies.
  {
    type = "technology",
    name = "gb-credit",
    icons = { { icon = "__base__/graphics/icons/coin.png", icon_size = 64 } },
    prerequisites = { "gb-contracts" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-credit" } },
    },
    unit = {
      count = 150,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-overdraft-1",
    localised_name = { "technology-name.gb-overdraft-1" },
    localised_description = { "technology-description.gb-overdraft-1" },
    icons = { { icon = "__base__/graphics/icons/coin.png", icon_size = 64 } },
    prerequisites = { "gb-credit" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-overdraft-1" } },
    },
    unit = {
      count = 200,
      ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
      time = 30,
    },
  },
  {
    type = "technology",
    name = "gb-overdraft-2",
    localised_name = { "technology-name.gb-overdraft-2" },
    localised_description = { "technology-description.gb-overdraft-2" },
    icons = { { icon = "__base__/graphics/icons/coin.png", icon_size = 64 } },
    prerequisites = { "gb-overdraft-1", "chemical-science-pack" },
    effects = {
      { type = "nothing", effect_description = { "technology-effect.gb-overdraft-2" } },
    },
    unit = {
      count = 300,
      ingredients = {
        { "automation-science-pack", 1 }, { "logistic-science-pack", 1 }, { "chemical-science-pack", 1 },
      },
      time = 30,
    },
  },
})
