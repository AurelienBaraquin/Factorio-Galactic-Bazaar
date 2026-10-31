---
name: factorio-runtime
description: Use when writing or reviewing control.lua / runtime scripts of the Galactic Bazaar Factorio mod - lifecycle (on_init, on_load, on_configuration_changed), the storage table and force-keyed economy state, determinism and multiplayer desyncs, event registration (on_tick, on_nth_tick, build/mine/destroy events, filters, register_on_object_destroyed), UPS batching, inventories and item counts with quality, fluids on entities (2.1 API), electric-energy-interface power trading, circuit network reading/writing (wire connectors, constant combinator logistic sections, int32 signals), custom GUIs (relative GUIs, tags, refs in storage), remote interfaces, commands, logging, helpers, profiling. Triggers - "control.lua", "event handler", "storage", "desync", "multiplayer", "on_tick", "UPS", "inventory", "insert/remove items", "fluid", "electricity", "power", "circuit", "signal", "combinator", "GUI", "button", "remote interface", "command", "profiler".
---

# Factorio runtime scripting (control stage)

Documented against **Factorio 2.1.24** (project target; `factorio_version: "2.1"`; Space Age optional).
Every name below was checked in https://lua-api.factorio.com/2.1.24 (`runtime-api.json`). If you
need something not listed, look it up there — never trust memory: 2.0 → 2.1 removed `LuaEntity.fluidbox`,
`game.create_profiler`, `defines.inventory.assembling_machine_*`, `LuaRecipePrototype.category`...

Reference files in this folder:
- [api-version-changes.md](api-version-changes.md) — 1.1 → 2.0 and **2.0 → 2.1 changes that matter**.
- [entities-io.md](entities-io.md) — inventories/items with quality, fluids, electric energy interface.
- [circuit-network.md](circuit-network.md) — reading signals, writing constant combinator sections, int32.
- [gui.md](gui.md) — GUI construction, events, tags, relative GUIs, per-player state.
Static side (info.json, prototypes, locale, migrations): `factorio-mod-structure` skill.

## Lifecycle (exact order)

| Step | When | Allowed |
|---|---|---|
| 1. `control.lua` file scope | every load / join | register handlers (`script.on_*`), `remote.add_interface`, `commands.add_command`, `script.register_metatable`, `require`. **No `game`, no `rendering`; `storage` not yet restored.** |
| 2. `on_init` | new save, or mod added to a save | full `game` + `storage` access; create initial state |
| 3. migrations | files not yet applied to the save | JSON then Lua; `game` + `storage` |
| 4. `on_load` | existing save loaded, **and every MP join** | read `storage`, re-set unregistered metatables, re-register conditional handlers, cache local refs. **No `game`. Writing `storage` raises an error.** |
| 5. `on_configuration_changed(data)` | game/mod version, mod set, startup setting or prototypes changed (for all mods or none) | full access; rebuild prices, validate refs, upgrade schema |

- New mod: 1 → `on_init` → migrations (no `on_load`). Existing: 1 → migrations → `on_load` → maybe `on_configuration_changed`.
- A joining MP client runs only steps 1 and 4 — anything else that differs locally desyncs.
- No other events reach the mod before `on_init`/`on_load` complete.

```lua
-- control.lua
local economy = require("scripts.economy")
local terminal = require("scripts.terminal")

local function init_storage()
  storage.version = storage.version or 1
  storage.forces = storage.forces or {}      -- [force_index] = {credits=0, prices={}, orders={}}
  storage.terminals = storage.terminals or {} -- [unit_number] = {entity=LuaEntity, force_index=n, ...}
  storage.players = storage.players or {}    -- [player_index] = {gui = {...}} (GUI refs only)
  for _, force in pairs(game.forces) do economy.ensure_force(force.index) end
end

script.on_init(function()
  init_storage()
  economy.rebuild_prices()
end)

script.on_configuration_changed(function(data)
  init_storage()                -- idempotent: fills missing keys after upgrades
  economy.rebuild_prices()      -- prototypes may have changed
  terminal.validate_all()       -- drop invalid LuaEntity refs
end)

script.on_load(function()
  -- only: re-register conditional handlers based on storage; never write storage
  if storage.terminals and next(storage.terminals) then terminal.register_tick() end
end)
```

## storage rules

- Each mod has its own `storage` (was `global` before 2.0). Persisted on save, restored before `on_load`.
- Allowed: nil, strings, numbers, booleans, tables (circular refs fine), **references to LuaObjects**
  (LuaEntity, LuaForce, LuaGuiElement, LuaPlayer...).
- **Functions are not allowed** (error on save). Metatables are dropped unless registered with
  `script.register_metatable(name, mt)` at file scope (`name` first, then `mt`; not in events/console).
- **Economy state is keyed by force index**: `storage.forces[force.index]`. Never per player, never a
  single global wallet. Handle `on_force_created`, `on_forces_merging` (move credits from `event.source`
  to `event.destination`), `on_forces_merged` (`event.source_index` is now invalid), and
  `on_player_changed_force` (only affects which wallet a GUI shows).
- Key tables by `unit_number` / `player_index` / `force_index` (numbers), **never by LuaObject**
  (`t[entity]` desyncs). Store the `LuaEntity` as a value and check `.valid` before use.
- Do not keep a second, file-scope copy of storage data that can diverge. A file-scope local that is
  only *a reference to a storage table* (set in on_init/on_load) is fine.

## Determinism and desync causes

Factorio is lockstep: every peer runs the same Lua. Desyncs come from local state that differs:

1. File-scope variables mutated in handlers (`local cache = {}` filled lazily) — a joining client has an
   empty cache. Put it in `storage` or rebuild it identically in `on_load` from `storage` only.
2. Doing anything in `on_load` beyond the three legal uses.
3. Conditional event registration that is not re-done in `on_load` from `storage`.
4. Tables keyed by LuaObjects or comparing locally created tables by reference.
5. Using data that is local to one machine for simulation: `request_translation` results, per-user
   settings, display resolution/scale, anything the player sees but others do not. Presentation only.
6. `os`, `io`, `coroutine`, `loadfile`, `dofile` do not exist. `math.random` is deterministic (map
   seed, shared with the game; cannot be used outside events/loading); for an independent stream use
   `game.create_random_generator(seed)`. `math.randomseed` does nothing.
7. `pairs` iterates in insertion order (first 1024 integer keys in order) — deterministic, but results
   still depend on insertion history, so build order-independent algorithms or sort keys.
8. `helpers.write_file(..., for_player)` / `game.print` with player-specific content are fine; do not
   branch simulation on file I/O (files cannot be read back anyway).

Testing: Heavy mode (`/toggle-heavy-mode`) saves and reloads every tick and reports state differences —
use it to catch on_load/local-state bugs without a second client (see `factorio-tooling`).

## Events

- `script.on_event(event_or_array, handler, filters?)` — **one handler per event per mod**; a second
  registration replaces the first (even with different filters). Filters only when registering a single
  event. `event` can also be a custom-input name string (`"gb-toggle-bazaar"`).
- `script.on_nth_tick(tick_or_array, handler)` — handler gets `{tick, nth_tick}`; passing `nil` handler
  unregisters; ticks fire on tick 0 too. Prefer it over `on_tick` + modulo.
- Custom events: `local id = script.generate_event_name()` at file scope; `script.raise_event(id, data)`.

### Entity lifecycle events (register all of them)

Built: `on_built_entity` (player; has `player_index`, `tags`), `on_robot_built_entity`,
`on_space_platform_built_entity` (only raised by space platforms; registering it without Space Age is
harmless), `script_raised_built`,
`script_raised_revive`, `on_entity_cloned` (`source`, `destination`).
Removed: `on_player_mined_entity`, `on_robot_mined_entity`, `on_space_platform_mined_entity`,
`on_entity_died`, `script_raised_destroy`, plus the catch-all **`on_object_destroyed`**.

```lua
local filters = {{filter = "name", name = "gb-terminal"}}
local function on_built(e)
  local entity = e.entity or e.destination          -- cloned uses destination
  if not (entity and entity.valid) then return end
  terminal.create(entity)                            -- stores storage.terminals[entity.unit_number]
  script.register_on_object_destroyed(entity)        -- returns registration_number, useful_id, type
end
for _, ev in pairs({
  defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity, defines.events.script_raised_built,
  defines.events.script_raised_revive, defines.events.on_entity_cloned,
}) do
  script.on_event(ev, on_built, filters)             -- one call per event: filters allowed
end

script.on_event(defines.events.on_object_destroyed, function(e)
  -- e.useful_id is the unit_number for entities; e.type is defines.target_type
  if e.type == defines.target_type.entity then terminal.remove(e.useful_id) end
end)
```

- `register_on_object_destroyed` (2.0 name; 1.1 was `register_on_entity_destroyed`) is global across
  mods, survives save/load, fires at the end of the current or next tick. It also accepts other targets
  (2.1 added `defines.target_type.force`, `electric_network`, ...).
- Use the mined/died events only when you need the *buffer* (`event.buffer`) to give the player items
  back (e.g. hub contents); otherwise rely on `on_object_destroyed`.
- Mods that create entities by script must call `script.raise_script_built{entity = e}` /
  `raise_script_destroy` — do the same for our hidden helper entities if other mods should know.

## UPS: batching

Never touch every terminal every tick. Round-robin a slice per tick:

```lua
local PER_TICK = 10
local function process_slice()
  local list = storage.terminal_list               -- dense array of unit_numbers, rebuilt on add/remove
  local n = #list
  if n == 0 then return end
  local i = storage.cursor or 1
  for _ = 1, math.min(PER_TICK, n) do
    if i > n then i = 1 end
    local t = storage.terminals[list[i]]
    if t and t.entity.valid then terminal.update(t) end
    i = i + 1
  end
  storage.cursor = i
end
script.on_nth_tick(1, process_slice)
```

- Keep the cursor and the list in `storage` (state). Remove entries by swap-with-last, not `table.remove`
  in the middle of iteration.
- Economy ticks (price drift, order matching, logistics delays) on `on_nth_tick(60)` or larger;
  delays as "due tick" queues sorted/bucketed by tick: `storage.deliveries[due_tick] = {...}`.
- Cache prototype lookups (`prototypes.item[name]`) in locals inside the function, not at file scope
  across ticks (prototypes are constant, so file-scope caching *of prototypes only* is safe, but
  `prototypes` is not available before `on_init`/`on_load`).
- Read `get_signals_changed(connector, last_tick)` before re-reading full circuit signal sets (2.1).

## Logging, commands, remote, helpers

```lua
game.print({"gb-gui.sold", count, {"item-name." .. name}, price}, {color = {0.4, 1, 0.4}})
player.print("...")                                 -- one player; `force.print` for a team
log("gb: prices rebuilt")                           -- factorio-current.log
helpers.write_file("gb/prices.json", helpers.table_to_json(storage.forces[1].prices), false)
-- written to script-output/; 4th arg for_player = only on that player's machine

commands.add_command("gb-balance", {"gb-command.balance-help"}, function(cmd)
  -- cmd.name, cmd.tick, cmd.player_index (nil = server console), cmd.parameter (string or nil)
  local player = cmd.player_index and game.get_player(cmd.player_index)
  if not player then return end
  player.print({"gb-gui.balance", storage.forces[player.force_index].credits})
end)

remote.add_interface("galactic-bazaar", {
  get_price = function(item_name, quality) return economy.get_price(item_name, quality) end,
  get_credits = function(force_index) return storage.forces[force_index] and storage.forces[force_index].credits end,
})
-- other mods: remote.call("galactic-bazaar", "get_price", "iron-plate", "normal")
```

- `commands.add_command(name, help, fn)` and `remote.add_interface` run at **file scope** (they do not
  persist through save/load; registering again on load is the normal pattern).
- Remote call arguments/returns are **copies**: metatables lost, LuaObject refs intact, functions
  cannot be passed. Validate every argument coming through a remote interface or command (types,
  ranges, existing force/item), they are system boundaries.
- `helpers` (all stages): `table_to_json`, `json_to_table`, `write_file`, `remove_path`,
  `compare_versions`, `is_valid_sprite_path`, `create_profiler` (runtime only), `encode_string`,
  `decode_string`, `evaluate_expression`, `stage`, `game_version`. In 1.1 these lived on `game`.

## Profiling UPS

- Console: `/measured-command <lua>` (alias `/mc`) runs Lua and prints the time taken.
- In code: `local p = helpers.create_profiler()` (or `create_profiler(true)` stopped);
  `p.stop()`, `p.restart()`, `p.reset()`, `p.add(other)`, `p.divide(n)`; print it as a LocalisedString:
  `log({"", "gb pricing: ", p})`. Values cannot be read numerically (non-deterministic); profilers
  cannot be stored in `storage`. **2.1: `game.create_profiler` was removed.**
- Per-mod script time overlays and UPS benchmarks: see the `factorio-tooling` skill.

## Multiplayer-safety checklist

- [ ] All mutable state lives in `storage`; economy keyed by `force.index`.
- [ ] `on_load` only reads storage, re-registers conditional handlers, relinks metatables.
- [ ] No table keyed by LuaObject; no reference comparison of local tables.
- [ ] Every stored LuaEntity/LuaGuiElement checked with `.valid` before use; invalid refs cleaned in
      `on_object_destroyed` and `on_configuration_changed`.
- [ ] Handlers registered unconditionally at file scope, or re-registered in `on_load` from storage.
- [ ] Per-user settings, translations, display info only drive presentation.
- [ ] Every GUI handler resolves `event.player_index` → `game.get_player()` and checks permissions
      (`player.force` owns the terminal) before mutating the economy — GUI events are player input.
- [ ] Forces: handle create/merge/delete; players: `on_player_created`, `on_player_removed`
      (clean `storage.players`).
- [ ] Signals written to circuits clamped to int32.
- [ ] Tested with heavy mode and with a second client (or headless server + client).

## Sources (read for this skill, Factorio 2.1.24)

- https://lua-api.factorio.com/2.1.24/ and /latest/ (`runtime-api.json`, diffed with
  https://lua-api.factorio.com/2.0.77/runtime-api.json): LuaBootstrap, LuaEntity, LuaControl,
  LuaInventory, LuaCircuitNetwork, LuaConstantCombinatorControlBehavior, LuaLogisticSection,
  LuaWireConnector, LuaGui, LuaGuiElement, LuaRemote, LuaCommandProcessor, LuaHelpers, LuaProfiler,
  LuaSettings, LuaGameScript, LuaPrototypes; concepts Signal, SignalID, SignalFilter, LogisticFilter,
  ItemStackIdentification, ItemWithQualityID, ItemWithQualityCount, Fluid, GuiAnchor,
  ConfigurationChangedData, CustomCommandData; events listed above.
- https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html
- https://lua-api.factorio.com/latest/auxiliary/storage.html
- https://lua-api.factorio.com/latest/auxiliary/libraries.html
- https://github.com/wube/factorio-data/blob/master/changelog.txt (2.1.7 Scripting section)
- https://wiki.factorio.com/Desynchronization
- https://wiki.factorio.com/Tutorial:Modding_tutorial/Gangsir (Multiplayer and desyncs)
- https://wiki.factorio.com/Console (`/measured-command`, `/toggle-heavy-mode`)
- https://github.com/wube/factorio-data/blob/master/core/prototypes/style.lua (style names)
- Examples: https://github.com/tiriscef/sosciencity (classes/entities/city-combinator.lua) and
  https://github.com/VencaCZ/warptorio-space-age (warp_constant_combinator.lua) for logistic sections.
