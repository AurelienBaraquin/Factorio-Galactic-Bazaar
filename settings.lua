-- Settings stage: the mod's settings.
local market_events = require("scripts.core.market_events")
local limits = market_events.LIMITS

data:extend({
  {
    -- Scales every base value (and so every price); values fixed by other mods stay as they set them.
    type = "double-setting",
    name = "gb-value-multiplier",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.01,
    maximum_value = 100,
    order = "a",
  },
  -- Which notifications a player is shown (scripts/notifications.lua): one switch per category.
  { type = "bool-setting", name = "gb-notify-contracts", setting_type = "runtime-per-user", default_value = true,
    order = "b-a" },
  { type = "bool-setting", name = "gb-notify-deliveries", setting_type = "runtime-per-user", default_value = true,
    order = "b-b" },
  { type = "bool-setting", name = "gb-notify-finance", setting_type = "runtime-per-user", default_value = true,
    order = "b-c" },
  { type = "bool-setting", name = "gb-notify-market", setting_type = "runtime-per-user", default_value = true,
    order = "b-d" },
  -- Market events (scripts/market_events.lua): how often they come (0 turns them off) and how strong
  -- they are, scaling market_events.DEFAULTS; read at each draw.
  { type = "double-setting", name = "gb-market-events-frequency", setting_type = "runtime-global", default_value = 1,
    minimum_value = limits.min_frequency, maximum_value = limits.max_frequency, order = "c-a" },
  { type = "double-setting", name = "gb-market-events-magnitude", setting_type = "runtime-global", default_value = 1,
    minimum_value = limits.min_magnitude, maximum_value = limits.max_magnitude, order = "c-b" },
})
