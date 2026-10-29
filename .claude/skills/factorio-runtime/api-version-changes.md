# API version changes that bite (1.1 → 2.0 → 2.1)

Target: **Factorio 2.1.24**. Sources: game changelog (`wube/factorio-data/changelog.txt`, 2.1.7
"Scripting"/"Modding" sections — 2.1.7, dated 2026-06-23, is the first 2.1 release), and a mechanical
diff of `runtime-api.json` / `prototype-api.json` 2.0.77 vs 2.1.24 from lua-api.factorio.com. Most
tutorials, forum posts and LLM memory describe 1.1 or 2.0: check every name here before using it.

## 1.1 → 2.0 (still relevant: old code and docs online)

| 1.1 | 2.0+ (verified present in 2.1.24) |
|---|---|
| `global` | `storage` |
| `game.item_prototypes`, `game.recipe_prototypes`, `game.entity_prototypes`, ... | `prototypes.item`, `prototypes.recipe`, `prototypes.entity`, ... (`LuaPrototypes`) |
| `game.table_to_json`, `game.json_to_table`, `game.write_file`, `game.remove_path`, `game.is_valid_sprite_path`, `game.active_mods` | `helpers.*` (`LuaHelpers`); `script.active_mods` |
| `script.register_on_entity_destroyed` / `on_entity_destroyed` | `script.register_on_object_destroyed` / `on_object_destroyed` (`useful_id`, `type`) |
| `entity.get_circuit_network(wire_type, circuit_connector_id)` | `entity.get_circuit_network(defines.wire_connector_id.*)` |
| `entity.connect_neighbour{...}` wires | `entity.get_wire_connector(id, true).connect_to(other_connector)` |
| constant combinator `parameters` | `LuaConstantCombinatorControlBehavior` **sections** → `LuaLogisticSection.set_slot/filters` |
| `inventory.get_contents()` → `{[name]=count}` | returns **array** of `{name, quality, count}` (`ItemWithQualityCount`) |
| items identified by name only | items have **quality**: `{name=..., quality="normal"}`, `get_item_quality_counts` |
| recipe `result = "x"`, ingredients `{"iron-plate", 2}` | `results = {{type="item", name="x", amount=1}}`, typed ingredients |
| technology unit only | `research_trigger` (craft-item, mine-entity, build-entity, scripted, ...) |

## 2.0 → 2.1 changes that matter for Galactic Bazaar

### Packaging / data
- `info.json` `factorio_version` must be `"2.1"` (one major per mod). New dependency prefix `+`
  (optional, recommended, enabled by default). New `migrates_from`.
- `RecipePrototype.category`/`additional_categories` → `categories` (array). Runtime
  `LuaRecipePrototype.category` and `LuaRecipe.category` reads removed → `.categories`,
  `has_category(name)`. Many combined categories deleted; `hand-crafting` added; `recycling`
  category now belongs to the `recycler` mod.
- `LuaRecipePrototype.is_parameter` removed → `LuaPrototypeBase.parameter`.
- Product `probability` → `independent_probability` (+ `shared_probability`), data and runtime.
- All science packs are now plain `item` prototypes (were `tool`).
- `ItemPrototype.fuel_category` → `fuel_categories`; `LuaItemPrototype.inventory_size` → `get_inventory_size(quality?)`.
- Quality: effect values ÷10 in prototypes, `next_probability` ×10, new `chain_probability`,
  `previous`, `previous_probability`.
- Space Age split: `space-age` requires `recycler` and `elevated-rails`, only recommends `quality`.
- Space Age recipe renames: `molten-iron` → `iron-ore-melting`, `molten-copper` → `copper-ore-melting`.

### Runtime
- **`LuaEntity.fluidbox` and `LuaFluidBox` removed.** Fluids are accessed on `LuaEntity`:
  `get_fluid(i)`, `set_fluid(i, fluid)` (second argument now mandatory, returns FluidAmount),
  `add_fluid(i, fluid)`, `remove_fluid(i, amount)`, `clear_fluid(i)`, `clear_fluids()`,
  `get_fluid_capacity(i)`, `get_fluid_filter(i)`, `set_fluid_filter(i, filter)`, `fluids_count`,
  `insert_fluid(fluid)`, `get_fluid_count(name?)`, `get_fluid_contents()`, segment functions
  (`get_fluid_segment_fluid`, ...).
- **Semantic trap: the old name-based `LuaEntity.remove_fluid{name=..., amount=...}` was renamed
  `extract_fluid`**; the new `remove_fluid(index, amount)` takes a storage index. Old code calling
  `remove_fluid{...}` now misbehaves/errors.
- `game.create_profiler` removed → `helpers.create_profiler`.
- `defines.inventory.assembling_machine_*`, `furnace_*`, `rocket_silo_input/output/modules` removed →
  `defines.inventory.crafter_input`, `crafter_output`, `crafter_modules`, `crafter_trash`.
- `defines.control_behavior.type.storage_tank` → `single_fluid_box`; `LuaStorageTankControlBehavior`
  → `LuaSingleFluidBoxControlBehavior`; `defines.relative_gui_type.storage_tank_gui` removed.
- `LuaLogisticContainerControlBehavior.circuit_exclusive_mode_of_operation` and
  `defines.control_behavior.logistic_container.exclusive_mode` removed → `set_requests`, `read_contents`.
- New `LuaControlBehavior.input_networks` / `output_networks`; new
  `LuaEntity.get_signals_changed(connector, tick?)`.
- `LuaEntity.neighbours` removed (use `fluidbox_neighbours`, `belt_neighbours`, ...);
  `LuaEntity.active` write removed → `disabled_by_script`; `LuaEntity.minable` write removed →
  `minable_flag`; `LuaEntity.mining_progress` moved to `LuaControl`.
- Electric: new `LuaElectricNetwork`/`LuaElectricSubNetwork`, `LuaEntity.electric_network(s)`,
  `LuaEntity.electric_interface_mode` + `defines.electric_interface_mode`, `LuaEntity.input_flow_limit`
  / `output_flow_limit` read/write.
- `LuaGroup` → `LuaItemGroup` / `LuaItemSubGroup`.
- GUI: new element type `"inventory"` + `on_gui_inventory_action`; more `choose-elem-button` types.
- `LuaPlayer.request_translation(s)` can be requested while offline and always arrive eventually.
- `LuaDeciderCombinatorControlBehavior`: `add_else_output`, `get_else_output`, `set_else_output`,
  `remove_else_output`.
- `defines.target_type` gained `force`, `electric_network`, `electric_sub_network`.
- New events: `on_blueprint_settings_pasted`, `on_gui_inventory_action`, `on_player_color_changed`,
  `on_player_music_changed`, selection-area events, `on_next_day_started`.
- `LuaPlayer.spectator` and `pipette_entity` removed.

### Unchanged (checked in the diff)
`LuaCircuitNetwork`, `LuaConstantCombinatorControlBehavior`, `LuaLogisticSection(s)`, `LuaRemote`,
`LuaCommandProcessor`, `LuaSettings`, `LuaProfiler`, `LuaTechnology`, `LuaGui`, `LuaRendering` (only
`light_mode` param additions), storage rules, lifecycle.

### Not verified
- Whether any 2.1 change affects save compatibility of `storage` contents from a 2.0 save of this mod
  (irrelevant until a 2.0 version exists).
- FFF posts were not read for this list; the game changelog is the authority used.
