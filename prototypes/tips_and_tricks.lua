-- In-game help (#111): a Tips and tricks category with one entry per system of the mod. The title
-- is suggested once the Galactic Bazaar is researched; each entry is suggested once the research that
-- brings its system is done and the title has been read. Their texts are the locale's
-- [tips-and-tricks-item-name] and [tips-and-tricks-item-description]. The Space Age and quality
-- entries exist only when the game has them.
local CATEGORY = "gb-galactic-bazaar"
local TITLE = "gb-galactic-bazaar"

-- Entries in order, with the research that suggests each.
local ENTRIES = {
  { name = "gb-bazaar-window", technology = "gb-galactic-bazaar" },
  { name = "gb-trading-hub", technology = "gb-galactic-bazaar" },
  { name = "gb-prices", technology = "gb-galactic-bazaar" },
  { name = "gb-deliveries", technology = "gb-galactic-bazaar" },
  { name = "gb-account", technology = "gb-galactic-bazaar" },
  { name = "gb-insolvency", technology = "gb-galactic-bazaar" },
  { name = "gb-research", technology = "gb-galactic-bazaar" },
  { name = "gb-alerts", technology = "gb-galactic-bazaar" },
  { name = "gb-power-trading", technology = "gb-power-trading" },
  { name = "gb-circuits", technology = "gb-market-signals" },
  { name = "gb-contracts", technology = "gb-contracts" },
  { name = "gb-reputation", technology = "gb-contracts" },
  { name = "gb-rental", technology = "gb-capacity-rental" },
  { name = "gb-planets", technology = "gb-planetary-concessions" },
  { name = "gb-outsourcing", technology = "gb-outsourcing" },
  { name = "gb-loans", technology = "gb-credit" },
}
if feature_flags["quality"] then
  ENTRIES[#ENTRIES + 1] = { name = "gb-quality", technology = "gb-galactic-bazaar" }
end
if mods["space-age"] then
  ENTRIES[#ENTRIES + 1] = { name = "gb-space-age", technology = "gb-galactic-bazaar" }
end

local definitions = {
  { type = "tips-and-tricks-item-category", name = CATEGORY, order = "z-[galactic-bazaar]" },
  {
    type = "tips-and-tricks-item",
    name = TITLE,
    category = CATEGORY,
    order = "a",
    is_title = true,
    tag = "[item=gb-hub]",
    trigger = { type = "research", technology = "gb-galactic-bazaar" },
  },
}
for index, entry in ipairs(ENTRIES) do
  definitions[#definitions + 1] = {
    type = "tips-and-tricks-item",
    name = entry.name,
    category = CATEGORY,
    order = string.format("b-%02d", index),
    indent = 1,
    dependencies = { TITLE },
    trigger = { type = "research", technology = entry.technology },
  }
end

data:extend(definitions)
