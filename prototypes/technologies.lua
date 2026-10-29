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
    },
    unit = {
      count = 75,
      ingredients = { { "automation-science-pack", 1 } },
      time = 15,
    },
  },
})
