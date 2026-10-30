-- Opening a trading hub: fires on the game's "open GUI" control (left click), with the entity under
-- the cursor, so the mod can open its own market window for a hub.
data:extend({
  {
    type = "custom-input",
    name = "gb-open-hub",
    key_sequence = "",
    linked_game_control = "open-gui",
    include_selected_prototype = true,
  },
})
