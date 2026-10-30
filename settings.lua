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
})
