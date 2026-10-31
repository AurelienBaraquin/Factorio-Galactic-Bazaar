-- Opening a trading hub: fires on the game's "open GUI" control (left click), with the entity under
-- the cursor, so the mod can open its window on the hub's Market tab. The Galactic Bazaar hotkey
-- opens or closes that window anywhere (bindable in the game's controls settings).
data:extend({
  {
    type = "custom-input",
    name = "gb-open-hub",
    key_sequence = "",
    linked_game_control = "open-gui",
    include_selected_prototype = true,
  },
  {
    type = "custom-input",
    name = "gb-toggle-bazaar",
    key_sequence = "CONTROL + SHIFT + G",
    consuming = "none",
  },
})
