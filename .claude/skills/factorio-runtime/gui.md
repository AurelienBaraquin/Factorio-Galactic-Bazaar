# GUI (Factorio 2.1.24)

Verified against `LuaGui`, `LuaGuiElement`, `GuiAnchor`, `defines.relative_gui_type` in
`runtime-api.json` 2.1.24 and style names in `core/prototypes/style.lua`.

## Principles

- GUIs are **per player** (`player.gui`) but part of the synchronised game state: create/destroy them
  only in event handlers (never in `on_load`).
- Roots: `player.gui.screen` (free, draggable windows), `.relative` (anchored to vanilla GUIs),
  `.top`, `.left`, `.center`, `.goal`. Root elements cannot be destroyed.
- Store **element references** per player in `storage.players[player_index].gui` (LuaObjects are
  allowed in storage). Check `.valid` before use — elements die when the player leaves or another code
  path destroys them. Store *GUI state* (selected tab, filter text) there too; store **economy state**
  only per force.
- Identify elements by `tags` (dictionary, read/write; reading returns a copy — reassign the whole
  table to change it) and `name`; dispatch from one handler per GUI event.
- Prefix element names with `gb_` to avoid clashes with other mods in shared roots.
- Accessing an attribute an element type does not support raises an error (e.g. `column_count` on a
  textfield).

## Element creation (`LuaGuiElement.add{...}`)

Common params: `type` (required), `name`, `caption`, `tooltip`, `elem_tooltip`, `enabled`, `visible`,
`locked`, `ignored_by_interaction`, `style`, `tags`, `index`, `anchor`, `game_controller_interaction`,
`raise_hover_events`. Type-specific (selection): `flow`/`frame`/`line` → `direction`;
`table` → `column_count`; `sprite-button` → `sprite`, `number`, `quality`, `toggled`;
`choose-elem-button` → `elem_type` (`"item"`, `"item-with-quality"`, `"fluid"`, `"signal"`, ...) plus
`elem_filters`; `textfield` → `text`, `numeric`, `allow_decimal`, `allow_negative`; `slider` →
`minimum_value`, `maximum_value`, `value`, `value_step`; `drop-down`/`list-box` → `items`,
`selected_index`; `progressbar` → `value`; 2.1 new type `inventory` (`inventory`, `slots_per_row`,
event `on_gui_inventory_action`).

Verified vanilla styles: `frame_title`, `draggable_space_header`, `frame_action_button`,
`inside_shallow_frame`, `inside_shallow_frame_with_padding`, `deep_frame_in_shallow_frame`,
`subheader_frame`, `slot_button`, `green_button`, `red_button`. Sprite paths use `"type/name"`
(`"item/iron-plate"`, `"fluid/water"`, `"virtual-signal/signal-A"`, `"utility/close"`); validate with
`helpers.is_valid_sprite_path`.

## Screen window with title bar

```lua
local function open_market(player)
  local pdata = storage.players[player.index]
  if pdata.gui and pdata.gui.window and pdata.gui.window.valid then pdata.gui.window.destroy() end

  local window = player.gui.screen.add{type = "frame", name = "gb_market", direction = "vertical"}
  local bar = window.add{type = "flow", direction = "horizontal"}
  bar.drag_target = window                                 -- only top-level screen frames
  bar.add{type = "label", caption = {"gb-gui.title"}, style = "frame_title", ignored_by_interaction = true}
  local spacer = bar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  bar.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
          tags = {gb_action = "close"}}

  local body = window.add{type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  local balance = body.add{type = "label", caption = {"gb-gui.balance", storage.forces[player.force_index].credits}}

  window.force_auto_center()
  player.opened = window                                   -- E/Esc now raise on_gui_closed for it
  pdata.gui = {window = window, balance = balance}
end
```

## Relative GUI attached to our entity's vanilla GUI

```lua
local function open_relative(player, entity)
  local root = player.gui.relative
  if root.gb_terminal_panel then root.gb_terminal_panel.destroy() end
  local panel = root.add{
    type = "frame", name = "gb_terminal_panel", caption = {"gb-gui.terminal"},
    anchor = {
      gui = defines.relative_gui_type.container_gui,      -- vanilla GUI of a container
      position = defines.relative_gui_position.right,     -- top | bottom | left | right
      name = "gb-terminal",                               -- only for this entity name (or names = {...}, type = ...)
      -- ghost_mode = "only_real" (default) | "only_ghosts" | "both"
    },
    tags = {unit_number = entity.unit_number},
  }
  -- fill panel...
end

script.on_event(defines.events.on_gui_opened, function(e)
  if e.gui_type == defines.gui_type.entity and e.entity and e.entity.valid and e.entity.name == "gb-terminal" then
    open_relative(game.get_player(e.player_index), e.entity)
  end
end)
```

Anchored GUIs show/hide automatically with the vanilla GUI; useful `relative_gui_type` values:
`container_gui`, `constant_combinator_gui`, `decider_combinator_gui`, `assembling_machine_gui`,
`electric_energy_interface_gui`, `linked_container_gui`, `proxy_container_gui`, `script_inventory_gui`.

## Events and dispatch

`on_gui_click` (`element`, `button`, `alt`, `control`, `shift`), `on_gui_confirmed`,
`on_gui_text_changed` (`text`), `on_gui_value_changed`, `on_gui_elem_changed`,
`on_gui_selection_state_changed`, `on_gui_checked_state_changed`, `on_gui_switch_state_changed`,
`on_gui_selected_tab_changed`, `on_gui_opened`/`on_gui_closed` (`gui_type`, `element`, `entity`, ...),
`on_gui_location_changed`. All carry `player_index`.

```lua
local actions = {}
function actions.close(e, player) local g = storage.players[player.index].gui; if g.window.valid then g.window.destroy() end end
function actions.buy(e, player, tags) market.buy(player, tags.item, tags.quality, tags.count) end

script.on_event(defines.events.on_gui_click, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  local handler = tags.gb_action and actions[tags.gb_action]
  if not handler then return end                           -- not ours
  handler(e, game.get_player(e.player_index), tags)
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if e.element and e.element.valid and e.element.name == "gb_market" then e.element.destroy() end
end)
```

- **Treat GUI events as untrusted input**: re-validate the item, quantity (numeric textfields still give
  strings; `tonumber` + bounds), the player's force owning the terminal (`entity.force == player.force`)
  and the balance before changing anything.
- Use tags for dispatch instead of parsing element names.

## Refreshing efficiently

- Do not rebuild GUIs every tick. Keep references to the few labels/numbers that change and update
  `caption`/`number` on an `on_nth_tick(30)` refresh, **only for players who have the window open**
  (keep `storage.open_guis[player_index] = true`).
- When prices change for a force, mark that force dirty and refresh only its players' open windows
  (`force.connected_players`).
- Large lists (hundreds of items): use a `scroll-pane` + `table`, rebuild only on filter change, and
  page it if needed.
- Clean up per-player data in `on_player_removed`; rebuild GUIs in `on_configuration_changed`
  (styles/prototypes may have changed: destroy and recreate rather than patch).
