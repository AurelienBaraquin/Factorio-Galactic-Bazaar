-- Settings stage: the mod's settings.
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
})
