# Locale, settings, migrations, changelog, packaging (Factorio 2.1.24)

## Locale

Files: `locale/<code>/*.cfg` (any file name, all files read). This mod ships `en` (mandatory fallback)
and `fr`. Format (no quotes; whitespace around `=` is part of the key/value — never write `key = value`):

```ini
[mod-name]
galactic-bazaar=Galactic Bazaar

[mod-description]
galactic-bazaar=Trade items, fluids and electricity for credits.

[entity-name]
gb-terminal=Bazaar terminal

[item-name]
gb-terminal=Bazaar terminal

[technology-name]
gb-bazaar=Galactic Bazaar

[technology-description]
gb-bazaar=Unlocks the bazaar terminal.

[mod-setting-name]
gb-price-multiplier=Price multiplier

[mod-setting-description]
gb-price-multiplier=Multiplies every computed price.

[string-mod-setting]
gb-pricing-mode-recipe=From recipes
gb-pricing-mode-flat=Flat

[controls]
gb-toggle-bazaar=Toggle Galactic Bazaar

[gb-gui]
balance=Balance: __1__ __plural_for_parameter__1__{1=credit|rest=credits}__
sold=Sold __1__ × __2__ for __3__ credits
```

```ini
; locale/fr/galactic-bazaar.cfg
[gb-gui]
balance=Solde : __1__ __plural_for_parameter__1__{0,1=crédit|rest=crédits}__
```

- Lookup keys: prototype names are found automatically under `item-name`, `entity-name`,
  `recipe-name`, `technology-name`, `fluid-name`, `*-description`; settings under `mod-setting-name` /
  `mod-setting-description`; dropdown values `string-mod-setting` as `<setting>-<value>`; custom inputs
  under `controls`. Custom sections are fine (`{"gb-gui.balance", 42}`).
- Missing key → "Unknown key: ..." shown in game.
- Parameters `__1__`, `__2__`; built-ins `__ITEM__iron-plate__`, `__ENTITY__name__`, `__FLUID__name__`,
  `__CONTROL__gb-toggle-bazaar__` (shows the player's binding).
- Plurals: `__plural_for_parameter__<n>__{<forms>}__`; forms `1`, `2,3,4`, `ends in 11`, `decimal`,
  `rest`; first match wins; negatives use the absolute value.
- Concatenation: `{"", {"item-name.iron-plate"}, ": ", 60}`. Fallback: `{"?", {"gb-gui.x"}, "default"}`
  (first valid parameter wins). Limits: max 20 parameters and max 20 levels of nesting — when
  concatenating long lists, chunk them into nested `{"", ...}` groups of ≤ 20.
- **Data stage: every parameter must be a string** (`tostring(n)`), else "Value must be a string".
- Comments: lines starting with `#` or `;`.
- Rich text (`[item=iron-plate]`, `[color=red]...[/color]`) works where the target supports it (chat,
  labels with rich text, tooltips).
- Runtime: never compare translated text; use `player.request_translation` + `on_string_translated` if
  you need text (asynchronous, per player — the result is player-local display data).

## Settings

Defined in `settings.lua` with `data:extend` (types and fields: see prototypes.md). Reading:

```lua
-- data stage: startup only
local mult = settings.startup["gb-price-multiplier"].value
-- runtime
local interval = settings.global["gb-update-interval"].value                     -- runtime-global
local show = settings.get_player_settings(player_index)["gb-show-tooltips"].value -- runtime-per-user
local show2 = game.get_player(player_index).mod_settings["gb-show-tooltips"].value
```

- `startup`: read-only at runtime; changing it requires restart and triggers
  `on_configuration_changed` (`data.mod_startup_settings_changed == true`).
- `runtime-global`: map-wide, admins change it in game → `on_runtime_mod_setting_changed`
  (`event.setting`, `event.setting_type`, `event.player_index`). Cache-free: read `settings.global` when
  needed or refresh a value in `storage` from that event.
- `runtime-per-user`: only for presentation (GUI, tooltips). **Never let it affect simulation or the
  economy** (another player's value is not what you think; prices must not depend on who looks).
- Setting names are global across mods → always prefix `gb-`.
- `hidden = true` + `forced_value` (bool/color) or single `allowed_values` to lock a value.

## Migrations

Folder `migrations/`. Each file runs **once per save**, ordered by mod order then file name
(lexicographic); all JSON first, then Lua. Adding the mod to an existing save runs all of them.
Name them by version: `0.2.0.json`, `0.2.0-storage-v2.lua`.

```json
{
  "entity": [["gb-old-terminal", "gb-terminal"]],
  "item":   [["gb-old-terminal", "gb-terminal"]],
  "recipe": [["gb-old-terminal", "gb-terminal"]]
}
```

- JSON renames keep entity `unit_number` and `storage` references valid; changing an entity's *type*
  gives a new unit number and invalidates stored references. Removed prototypes invalidate references.
- Lua migrations have `game` and `storage`; use them for one-shot data reshaping. Recipe/tech state is
  reset automatically by the game when mods/prototypes/startup settings change — do not re-unlock
  recipes manually just for that; but **script-driven state (our tiers, unlocks stored in storage) must be
  re-derived** in `on_configuration_changed`.
- Order on load of an existing save: migrations → `on_load` → `on_configuration_changed`. For a new
  mod: `on_init` → migrations. So Lua migrations must tolerate `storage` already initialised by `on_init`.
- Prefer a **storage schema version** (`storage.version = 3`) checked in `on_configuration_changed` for
  structural upgrades; it is testable and runs in a predictable place. Use Lua migration files only for
  one-off fixes tied to a release.

`on_configuration_changed(data)` (`ConfigurationChangedData`): `old_version`/`new_version` (game),
`mod_changes[name] = {old_version, new_version}` (nil old = just added, nil new = removed),
`mod_startup_settings_changed`, `migration_applied`, `migrations[IDType][old] = new`.

```lua
script.on_configuration_changed(function(data)
  local mine = data.mod_changes["galactic-bazaar"]
  if mine and mine.old_version then
    -- upgrade path; helpers.compare_versions(mine.old_version, "0.2.0") < 0 then ...
  end
  rebuild_prices()          -- prototypes may have changed
  validate_entities()       -- drop invalid LuaEntity references
end)
```

`helpers.compare_versions(a, b)` returns an int32 (<0, 0, >0) — available in all stages.

## changelog.txt (strictly parsed by the game)

```
---------------------------------------------------------------------------------------------------
Version: 0.1.0
Date: 2026-11-01
  Major Features:
    - Initial release: bazaar terminal, recipe-based prices, credits per force.
  Bugfixes:
    - Fixed a crash when a terminal was destroyed on the same tick it was built.
      Multi-line entries continue with exactly six spaces.
```

Rules: separator line = **exactly 99 dashes**; next line must be `Version: x.y.z` (not empty, unique,
not `0.0.0`); optional single `Date: ` (free format); category lines start with exactly 2 spaces and end
with `:`; entries start with exactly 4 spaces + `- `; continuation lines exactly 6 spaces; **no tabs, no
trailing spaces**; no duplicate entries in the same category. Recognised categories (sorted first):
Major Features, Features, Minor Features, Graphics, Sounds, Optimizations, Balancing, Combat Balancing,
Circuit Network, Changes, Bugfixes, Modding, Scripting, Gui, Control, Translation, Debug, Ease of use,
Info, Locale, Compatibility. Parse errors only appear in `factorio-current.log`.

## Packaging

- Zip name **must** be `<name>_<version>.zip` (`galactic-bazaar_0.1.0.zip`), version equal to
  `info.json`. Inside: one top-level folder (any name) containing `info.json`.
- Unzipped development copy: folder `galactic-bazaar` or `galactic-bazaar_0.1.0` in the user data
  `mods/` directory (Linux: `~/.factorio/mods/`; a symlink to the repo works for development).
- `thumbnail.png` at mod root, ideally 144×144.
- Exclude dev files (tests, CI, `.git`, `.claude`) from the zip. Tooling (fmtk package, CI) is covered
  by the `factorio-tooling` skill.
- Mod portal: name 4–49 chars, alphanumerics/`-`/`_`; portal shows changelog as plain text.
