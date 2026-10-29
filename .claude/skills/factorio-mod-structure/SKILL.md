---
name: factorio-mod-structure
description: Use when creating or changing the static side of the Galactic Bazaar Factorio mod - info.json, dependencies (including optional Space Age), the settings/data/control stage split, prototype definitions (items, recipes, technologies, entities such as containers, electric-energy-interface, combinators, custom-input, mod-data), reading the recipe/item/fluid graph for automatic pricing, Space Age/quality detection, locale .cfg files (en/fr, parameters, plurals), mod settings, migrations, changelog.txt, thumbnail and zip packaging. Triggers - "add a prototype", "new entity/item/recipe/technology", "data.lua", "data-final-fixes", "info.json", "dependency", "space-age optional", "locale", "translation", "mod setting", "migration", "changelog", "package the mod", "zip", "factorio_version".
---

# Factorio mod structure (prototype side)

Documented against **Factorio 2.1.24** — the project's target (owner decision: Factorio 2.1, Space Age
optional). lua-api.factorio.com `/latest/` and `/stable/` both resolve to 2.1.24 as of 2026-10-29; the
game changelog dates 2.1.24 to 2026-10-27 and the first 2.1 release (2.1.7) to 2026-06-23. **2.1 is a
new major version and a mod targets exactly one major version**: `factorio_version` is `"2.1"`.
For runtime scripting (control.lua, storage, events, GUI, circuits) use the `factorio-runtime` skill.

Reference files in this folder:
- [prototypes.md](prototypes.md) — verified prototype snippets (item, recipe, technology, container,
  electric-energy-interface, constant combinator, custom-input, mod-data) and base asset paths.
- [recipe-graph.md](recipe-graph.md) — reading the full recipe/item/fluid graph for pricing, Space Age,
  quality, recycling cycles, optional-mod detection.
- [locale-settings-migrations.md](locale-settings-migrations.md) — locale format, plurals, settings,
  JSON/Lua migrations, `on_configuration_changed`, changelog format, packaging.
- Version deltas 1.1 → 2.0 → 2.1: [../factorio-runtime/api-version-changes.md](../factorio-runtime/api-version-changes.md).

## Golden rules

1. **Never write an API name from memory.** Check it on lua-api.factorio.com/latest (or the machine
   readable `runtime-api.json` / `prototype-api.json` at the same URL) before using it. 2.0 → 2.1 removed
   or renamed several things this mod needs (`RecipePrototype.category` → `categories`,
   `LuaEntity.fluidbox` removed, `game.create_profiler` removed, `defines.inventory.assembling_machine_*`
   → `crafter_*`).
2. **Space Age is optional, never required.** Use `"? space-age"` in dependencies and guard every
   Space-Age-only prototype/property with `mods["space-age"]` (data stage) or `script.active_mods["space-age"]`
   (runtime), or better with the specific feature flag (`feature_flags.quality`, `feature_flags.space_travel`...).
3. **Prototypes are frozen after the data stage.** Anything that must adapt to other mods' recipes is
   computed either in `data-final-fixes.lua` or at runtime from `prototypes.*` (preferred for pricing).
4. **Prefix every name** (prototypes, settings, locale sections, custom events, remote interface) with
   the mod prefix (e.g. `gb-`). Setting names are global across all mods.
5. Keep files < 500 lines; one prototype family per file under `prototypes/`.

## Mod layout

```
galactic-bazaar/                 -- folder name: {name} or {name}_{version}
├── info.json                    -- the ONLY mandatory file
├── changelog.txt                -- strict format (see locale-settings-migrations.md)
├── thumbnail.png                -- ideally 144x144
├── settings.lua                 -- settings stage (+ settings-updates.lua, settings-final-fixes.lua)
├── data.lua                     -- prototype stage round 1
├── data-updates.lua             -- round 2
├── data-final-fixes.lua         -- round 3
├── control.lua                  -- runtime (separate Lua state per mod)
├── locale/en/*.cfg, locale/fr/*.cfg
├── migrations/*.json|*.lua
├── graphics/ ...
└── prototypes/ , scripts/       -- free-form, loaded via require()
```

Recognised subfolders: `locale`, `scenarios`, `campaigns`, `tutorials`, `migrations`. Everything else
is free-form and loaded with `require("prototypes.items")` (path from mod root, `.lua` implied;
`..`/`.` path components are disabled; another mod's file: `require("__flib__.gui")`; core lualib:
`require("util")`). `require` cannot be called inside event handlers — require everything at file scope.

## info.json

```json
{
  "name": "galactic-bazaar",
  "version": "0.1.0",
  "title": "Galactic Bazaar",
  "author": "AurelienBaraquin",
  "description": "Interstellar market: trade items, fluids and power for credits.",
  "factorio_version": "2.1",
  "dependencies": ["base >= 2.1.0", "? space-age >= 2.1.0", "? quality", "(?) some-hidden-optional", "! incompatible-mod"]
}
```

- Mandatory: `name`, `version` (`"a.b.c"`, each 0–65535), `title`, `author`. `factorio_version` is
  technically optional (defaults to `"0.12"`) but effectively mandatory.
- **`factorio_version` is `"major.minor"` only** (a third number makes the portal reject the mod).
  "Mods can only be compatible with one major version" — a mod declaring `"2.0"` is not loaded by 2.1
  and vice-versa. Quality, recycler and space-age 2.1.24 all declare `"2.1"`. This project uses `"2.1"`
  and depends on `base >= 2.1.0`.
- Mod name: portal allows only alphanumerics, `-` and `_`, length 4–49.
- Dependency string: `"<prefix> name <op> version"`. Prefixes: none = hard requirement, `?` optional,
  `(?)` hidden optional, `!` incompatible (version ignored), `+` recommended, `~` dependency that does not
  affect load order. Operators `<`, `<=`, `=`, `>=`, `>`. If a version is given on an optional
  dependency and that mod is present with a wrong version, **our mod is disabled**.
- Default when `dependencies` is omitted is `["base"]`.
- Optional dependencies matter for load order: listing `? space-age` guarantees our `data-final-fixes`
  runs after space-age's `data-final-fixes` and that our runtime handlers run after its handlers.
- Feature-flag fields (`quality_required`, `space_travel_required`, `spoiling_required`,
  `freezing_required`, `rail_bridges_required`, `segmented_units_required`, `expansion_shaders_required`,
  `expansion_required`) **require owning Space Age** — never set them (it would make the expansion
  mandatory). Use runtime/data detection instead.
- `migrates_from: ["old-mod"]` moves a removed mod's `storage` into `storage._migrated["old-mod"]`.
- In 2.1 the official mods are split: `space-age` depends on `base`, `elevated-rails`, `recycler`, and
  only **recommends** `+ quality`. `quality` depends on `recycler`. So "recycling recipes exist",
  "quality exists" and "Space Age exists" are three independent facts (see recipe-graph.md).

## The three stages and what exists in each

| Stage | Files (run for every mod, in load order, round by round) | Available globals |
|---|---|---|
| Settings | `settings.lua` → `settings-updates.lua` → `settings-final-fixes.lua` | `data` (`data:extend`), `mods`, `helpers` (whether `feature_flags` exists here is UNVERIFIED — do not rely on it) |
| Prototype (data) | `data.lua` → `data-updates.lua` → `data-final-fixes.lua` | `data`, `data.raw`, `mods`, `settings.startup`, `helpers`, `feature_flags`, `defines`, `serpent`, `log`, `table_size` |
| Runtime (control) | `control.lua`, then `on_init`/migrations/`on_load`/`on_configuration_changed` | `script`, `game` (not at file scope / on_load), `storage`, `prototypes`, `settings`, `helpers`, `remote`, `commands`, `rendering`, `rcon` |

- One shared Lua state per settings/data stage; it is **discarded at the end of the stage**: no variable
  carries from data to control. To pass computed data to runtime use a `mod-data` prototype
  (`prototypes.mod_data["gb-prices"].data`) or recompute at runtime.
- Mod order = dependency-chain depth first, then natural sort of internal names. All mods run
  `data.lua`, then all run `data-updates.lua`, then all `data-final-fixes.lua`.
- Unknown prototype properties are silently ignored — typos do not error. Missing required ones do.
- `math.random` in the data stage is seeded with a constant; `os`, `io`, `coroutine`, `loadfile`,
  `dofile` are unavailable everywhere.
- Debug data stage with `log(serpent.block(data.raw["item"]["iron-plate"]))` (goes to factorio-current.log).

## Defining prototypes — rules

- Add with `data:extend({ {...}, {...} })`. Each needs `type` and `name`; a `name` must be unique per
  prototype *type family*.
- Derive a new entity from a base one with `table.deepcopy` (defined in `core/lualib/util.lua`, global
  in all stages; `util.copy` is an alias) and change `name`, `minable.result`, `icon`, sizes, etc. Never
  mutate the base table in place.
- Item ↔ entity ↔ recipe triangle: item `place_result = "gb-terminal"`, entity
  `minable = {mining_time = 0.2, result = "gb-terminal"}`, recipe `results = {{type="item", name="gb-terminal", amount=1}}`,
  `enabled = false` + technology `effects = {{type = "unlock-recipe", recipe = "gb-terminal"}}`.
- Recipes (2.0+): ingredients and results are **tables with explicit `type`**
  (`{type="item", name="iron-plate", amount=10}`), no 1.1 shorthand `{"iron-plate", 10}` and no
  `result=`. Fluids: `{type="fluid", name="water", amount=100}`.
- **2.1: recipes use `categories = {"crafting"}` (array). `category` and `additional_categories` were
  removed.** Default is `{"crafting"}`.
- Technologies: either `unit = {count=..., ingredients={{"automation-science-pack",1}}, time=15}` or
  `research_trigger = {type="craft-item", item="iron-plate", count=50}`. Use `{type="nothing",
  effect_description={...}}` to show script-driven effects (e.g. logistics tiers) in the tech GUI, and
  `research_trigger = {type="scripted", trigger_description={...}}` + `LuaForce::script_trigger_research`
  for script-completed techs.
- Science packs from Space Age must only be referenced when `mods["space-age"]`.
- Icons: `icon = "__base__/graphics/icons/constant-combinator.png"` with `icon_size` default 64.
  Reference base graphics by `__base__/...`, our own by `__galactic-bazaar__/graphics/...`.
- Hide internal/helper prototypes with `hidden = true` (PrototypeBase) — e.g. hidden combinators used
  as I/O ports of the terminal. Mark parameter prototypes with `parameter = true` only for blueprint
  parameters.

See [prototypes.md](prototypes.md) for complete, verified snippets.

## Reading the recipe graph (summary)

Prefer **runtime** (`prototypes.recipe`, `prototypes.item`, `prototypes.fluid`) in `on_init` and
`on_configuration_changed`: it sees the final state after every mod's `data-final-fixes`, costs nothing
at startup, and can be stored per force. Use `data-final-fixes` only if prices must influence
prototypes (e.g. tooltips) — and even then other mods sorted after us can still change recipes. Treat
recycling (`categories` containing `"recycling"`), hidden, parameter and barrel/void recipes specially to
avoid cycles. Full method in [recipe-graph.md](recipe-graph.md).

## Optional Space Age detection

```lua
-- data stage
if mods["space-age"] then --[[ add planet-specific variants ]] end
if feature_flags["quality"] then --[[ quality-aware prototypes ]] end
-- runtime
local has_space_age = script.active_mods["space-age"] ~= nil
local has_quality   = script.feature_flags.quality      -- LuaBootstrap::feature_flags
local has_platforms = script.feature_flags.space_travel
```

Feature flags (both stages): `expansion`, `expansion_shaders`, `freezing`, `quality`, `rail_bridges`,
`segmented_units`, `space_travel`, `spoiling`. Prefer flags over mod names: another mod can enable
quality without Space Age.

## Locale, settings, migrations, packaging (summary)

- `locale/en/galactic-bazaar.cfg` + `locale/fr/galactic-bazaar.cfg`; `[item-name]`, `[entity-name]`,
  `[recipe-name]`, `[technology-name]`, `[mod-setting-name]`, custom `[gb-gui]` sections. Parameters
  `__1__`, plurals `__plural_for_parameter__1__{1=credit|rest=credits}__`. In the data stage every
  localised-string parameter must be a string (`tostring(n)`).
- Settings types: `bool-setting`, `int-setting`, `double-setting`, `string-setting`, `color-setting`;
  `setting_type`: `"startup"` (data stage + runtime, read-only), `"runtime-global"` (map-wide, admins),
  `"runtime-per-user"`. Economy-affecting values must be `startup` or `runtime-global`, never per-user.
- Migrations: `migrations/*.json` renames prototypes, `migrations/*.lua` fixes game state; each file runs
  once per save, sorted by name — prefix with the version: `0.2.0-rename-terminal.json`.
- Zip: `galactic-bazaar_0.1.0.zip` containing one folder (any name) with `info.json` inside.
- `changelog.txt`: 99 dashes, `Version: x.y.z`, optional `Date: `, categories with 2 spaces and a colon,
  entries with 4 spaces + `- `; no tabs, no trailing spaces.

Details: [locale-settings-migrations.md](locale-settings-migrations.md).

## 2.0 → 2.1 changes that matter (data side)

From the game changelog (2.1.7 "Modding"/"Scripting" sections, `wube/factorio-data/changelog.txt`) and
a diff of `prototype-api.json` 2.0.77 vs 2.1.24:

- `factorio_version` `"2.1"`; 2.0 mods do not load in 2.1.
- New dependency prefix `+` (optional but recommended, enabled by default).
- `RecipePrototype.category` / `additional_categories` removed → `categories = {...}`. Many combined
  categories were deleted (`basic-crafting`, `crafting-with-fluid-or-metallurgy`, `electronics`, ...),
  `hand-crafting` added; recipes now list several categories. The `recycling` category moved from base
  to the `recycler` mod.
- `ItemProductPrototype.probability` / `FluidProductPrototype.probability` → `independent_probability`;
  new `shared_probability`. Ingredients gained `quality_min`/`quality_max`/`quality_change`.
- **All science packs are plain `item` prototypes** (no longer `tool`); technologies/labs accept any
  item as research ingredient.
- `ItemPrototype.fuel_category` → `fuel_categories`. `ContainerPrototype.picture` is a `Sprite4Way`.
  `AssemblingMachinePrototype.enable_logistic_control_behavior` removed (use flag
  `"no-logistic-connection"`). `CustomInputPrototype.key_sequence` no longer accepts deprecated key names.
- Quality: quality effect values in prototypes divided by 10, `next_probability` multiplied by 10; new
  `chain_probability`. Space Age split into `space-age` + `recycler` + `quality` (+ `elevated-rails`),
  with `quality` only recommended.
- Space Age recipes renamed: `molten-iron` → `iron-ore-melting`, `molten-copper` → `copper-ore-melting`.
- `info.json` `migrates_from` added; mods can define new languages via locale.
- Runtime-side deltas (fluids, inventories defines, profiler, control behaviors): see
  [../factorio-runtime/api-version-changes.md](../factorio-runtime/api-version-changes.md).

## Pitfalls checklist (data side)

- [ ] `factorio_version` is `"2.1"`; dependency versions use `>= 2.1.0`.
- [ ] No `category =` on recipes (2.1 uses `categories`), no `result =`, all ingredients typed.
- [ ] No Space-Age prototype/item/science pack/surface referenced without a guard.
- [ ] No `*_required` feature flags in info.json.
- [ ] Every new prototype has en + fr locale keys (or `localised_name`), otherwise "Unknown key".
- [ ] Entities have `minable`, `flags = {"placeable-neutral", "player-creation"}`, collision/selection boxes.
- [ ] Hidden helper entities: `hidden = true`, `flags` include `"not-blueprintable"`, `"not-deconstructable"`
      as needed, `selectable_in_game = false` (or flag `"not-selectable-in-game"`) when the player must not
      touch them.
- [ ] Entities looked up with `game.get_entity_by_unit_number` need the `"get-by-unit-number"` flag.
- [ ] Startup-setting changes trigger `on_configuration_changed` — runtime must handle it.
- [ ] Renamed prototypes come with a JSON migration.

## Sources (read for this skill, Factorio 2.1.24)

- https://lua-api.factorio.com/latest/ (version index; `/stable/` = 2.1.24, last 2.0 = 2.0.77)
- https://lua-api.factorio.com/latest/runtime-api.json and /prototype-api.json (diffed against
  https://lua-api.factorio.com/2.0.77/runtime-api.json and /prototype-api.json)
- https://lua-api.factorio.com/latest/auxiliary/mod-structure.html
- https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html
- https://lua-api.factorio.com/latest/auxiliary/migrations.html
- https://lua-api.factorio.com/latest/auxiliary/changelog-format.html
- https://lua-api.factorio.com/latest/auxiliary/libraries.html
- https://lua-api.factorio.com/latest/prototypes/RecipePrototype.html, TechnologyPrototype.html,
  ElectricEnergyInterfacePrototype.html, ContainerPrototype.html, ConstantCombinatorPrototype.html,
  CustomInputPrototype.html, ModData.html (via prototype-api.json)
- https://wiki.factorio.com/Tutorial:Mod_settings
- https://wiki.factorio.com/Tutorial:Localisation
- https://github.com/wube/factorio-data/blob/master/changelog.txt (game changelog, 2.1.7–2.1.24 sections)
- https://github.com/wube/factorio-data (base/space-age/quality/recycler info.json,
  core/lualib/util.lua, base/prototypes/item.lua, recipe.lua, technology.lua, recycler/data-updates.lua,
  recycler/recycling.lua)
- Community reports of the 2.1 recipe `categories` change and `factorio_version "2.1"` bump (mod portal
  changelogs, found via search) — confirmed against prototype-api.json.
