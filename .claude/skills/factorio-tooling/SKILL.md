---
name: factorio-tooling
description: Toolchain for developing the Galactic Bazaar Factorio mod - linting (luacheck), API type definitions (FMTK bundle for LuaLS/EmmyLua), pure-Lua unit tests (busted), in-game integration tests (FactorioTest CLI on the headless server), UPS benchmarks, packaging (fmtk package), changelog.txt rules, mod portal upload, debugging (FMTK debugger, log, /c, instrument mode, heavy mode) and GitHub Actions CI. Use when setting up or running lint/tests/CI, writing a test, packaging or publishing a release, measuring UPS, or debugging a desync or runtime error.
---

# Factorio tooling (Galactic Bazaar)

All commands and flags below were checked against the sources listed at the end
(docs read 2026-10-29). Anything not confirmed is tagged **[unverified]**.

## 0. Target version: Factorio 2.1 (owner decision)

- `info.json`: `"factorio_version": "2.1"`. Space Age stays optional.
- Current stable = **2.1.24** (`https://factorio.com/api/latest-releases`, 2026-10-29).
  Headless 2.1.24 download returns 302 (public). Pin CI to an exact version, bump deliberately.
- API docs: use `https://lua-api.factorio.com/2.1.24/...` (`runtime-api.json`,
  `prototype-api.json` and HTML pages verified 200). `/latest` currently equals 2.1.24.
- Never copy 2.0 snippets from forums/mods without checking them against 2.1.24.

### 2.0 -> 2.1 changes that matter here
Primary source: a diff of `runtime-api.json` / `prototype-api.json` 2.0.77 vs 2.1.24
(66 runtime members removed, ~600 added). No official 2.1 changelog/FFF was found online by
this research; the game ships `data/changelog.txt` in the headless tarball - read it for detail.
- **Recipes** (core of recipe-graph pricing): `RecipePrototype.category` and
  `additional_categories` are gone, replaced by `categories` (array) in data stage; runtime
  `LuaRecipe.category`/`LuaRecipePrototype.category`/`additional_categories` removed too
  (2.1 runtime: `LuaRecipePrototype.categories`, `has_category`).
  Also removed: `always_show_products`, `show_amount_in_title`, `result_is_always_fresh`,
  `reset_freshness_on_craft`, `LuaRecipePrototype.is_parameter`.
- **Items**: `ItemPrototype.fuel_category` -> `fuel_categories`; runtime
  `LuaItemPrototype.fuel_category`, `inventory_size`, `entity_filter_slots`, `tile_filter_slots` removed.
- **Fluids**: `LuaEntity.fluidbox` and the whole `LuaFluidBox` API (`get_capacity`, `flush`,
  `get_fluid_segment_*`, ...) removed from the 2.1 runtime docs - look up the 2.1 replacement
  before touching fluid pricing/trading.
- `game.create_profiler` removed (use `helpers.create_profiler`); `LuaGroup` class gone;
  `LuaEntityPrototype.max_power_output`, `fluid_usage_per_tick`, `pumping_speed` removed;
  `LuaPlayer.spectator`, `pipette_entity` removed; several control behaviors lost fields
  (`include_fuel`, `circuit_exclusive_mode_of_operation`, display-panel `messages`).
- Tooling impact: regenerate the FMTK bundle for 2.1.24 so LuaLS flags removed
  fields, and let the reviewer agent check for these names.

## 1. Recommended toolchain

| Concern | Tool | Gate in CI |
|---|---|---|
| Lint / undefined globals / purity | `luacheck` (lunarmodules, v1.2.0) + `.luacheckrc` | yes (exit 0 required) |
| API types, editor completion | FMTK bundle (`fmtk docs`) loaded by LuaLS or EmmyLua | local; CI optional |
| Pure logic unit tests | `busted` on Lua 5.2 | yes |
| Game integration tests | FactorioTest (`factorio-test-cli` 3.8.x + mod `factorio-test`) on headless | yes |
| Packaging / publishing | `fmtk package`, `fmtk upload` / mod portal API | release job |
| Debugging | FMTK VS Code debugger, `log()`, `/c`, heavy mode | local |

Lua version: Factorio runs a modified **Lua 5.2.1** (no `io`, `os`, `coroutine`,
`loadfile`, `dofile`; deterministic `math.random`; `pairs` iterates in insertion order).
Run busted on Lua 5.2 so the unit-test VM matches.

## 2. Architecture rule that makes testing possible

Split the code into two layers. This is enforced by luacheck (section 3).

```
scripts/core/        PURE Lua 5.2: pricing, recipe-graph walk, market maths, order book.
                     No game/script/storage/defines/prototypes/helpers access.
                     Inputs = plain tables, outputs = plain tables/numbers.
scripts/             ADAPTERS: event handlers, GUI, entities, circuit I/O, storage.
                     Read the game API, build plain tables, call core, write results.
spec/                busted specs for scripts/core (run outside the game).
tests/               FactorioTest files for adapters (run inside the game).
```

Rules for `scripts/core`:
- Functions take their world as arguments, e.g.
  `pricing.compute(recipes, base_prices, params) -> prices` where `recipes` is a
  plain `{ [name] = { ingredients = {...}, products = {...}, energy = n } }`
  extracted once by an adapter from `prototypes.recipe`.
- No hidden state: the per-force economy state lives in
  `storage.forces[force_index]` and is **passed in** (`market.apply_trade(state, trade)`
  returns or mutates only that table). Never cache it in a module upvalue.
- Only serializable data in state (numbers, strings, booleans, plain tables).
  No functions, no metatables, no LuaObjects.
- Deterministic: no `os.time`, no `pairs` order assumptions across differently
  built tables, integer maths where results are shown on circuits (int32 range).
- Clamp before writing circuit signals: values must fit in int32
  (-2147483648 .. 2147483647). Put the clamp in core and unit-test it.
- `require` paths are absolute from the mod root (`require("scripts.core.pricing")`);
  `..` and `.` relative requires are not allowed by Factorio. busted resolves the same
  path with `--lpath=./?.lua`.

## 3. Static analysis: luacheck

Install: `luarocks install luacheck` (CI: `lunarmodules/luacheck@v1` action).
Exit codes: 0 clean, 1 warnings, 2 syntax errors, 3 unreadable files, 4 bad config.

`.luacheckrc` at the repo root (written from the luacheck docs; **not yet executed** -
run `luacheck .` once and tune):

```lua
std = "lua52"
max_line_length = 120
exclude_files = { ".luarocks/**", "factorio-test-data-dir/**", "dist/**", "node_modules/**", ".luals/**" }
not_globals = { "global", "io", "os", "coroutine", "loadfile", "dofile" } -- `global` = 1.1 name

stds.factorio_runtime = {
  globals = { "storage" },
  read_globals = { "game", "script", "remote", "commands", "settings", "rendering",
    "helpers", "prototypes", "rcon", "defines", "log", "localised_print",
    "table_size", "serpent", "__DebugAdapter", "__Profiler" },
}
stds.factorio_data = {
  globals = { "data" },
  read_globals = { "mods", "settings", "defines", "log", "table_size", "serpent",
    "localised_print" }, -- use `local util = require("util")`, not a global
}
stds.factorio_test = { read_globals = { "describe", "test", "it", "before_each",
  "after_each", "before_all", "after_all", "after_test", "async", "done", "on_tick",
  "after_ticks", "ticks_between_tests", "tags" } } -- names from FactorioTest Writing-Tests.md

files["control.lua"]            = { std = "lua52+factorio_runtime" }
files["scripts/**/*.lua"]       = { std = "lua52+factorio_runtime" }
files["scripts/core/**/*.lua"]  = { std = "lua52" }          -- purity enforced here
files["data*.lua"]              = { std = "lua52+factorio_data" }
files["settings*.lua"]          = { std = "lua52+factorio_data" }
files["prototypes/**/*.lua"]    = { std = "lua52+factorio_data" }
files["tests/**/*.lua"]         = { std = "lua52+factorio_runtime+factorio_test" }
files["spec/**/*.lua"]          = { std = "lua52+busted" }
files["tools/**/*.lua"]         = { globals = { "io", "os" } }  -- CI scripts, never shipped
```

Run: `luacheck .` (or `luacheck . --formatter plain` for grep-able output).
Notes: `files[...]` globs are applied general-to-specific, so the `scripts/core`
entry overrides `scripts/**`. Keep undefined-global warnings (111/112/113) enabled:
they are what catch 1.1-era names and typos.

## 4. Types: FMTK bundle for LuaLS / EmmyLua

FMTK = "Factorio Modding Tool Kit" (npm `factoriomod-debug`, CLI `fmtk`, 2.1.9).
Current FMTK targets **EmmyLua** in VS Code; its generated bundle is a LuaLS-style
addon (`config.json` with `Lua.*` settings + `library/`), and the command alias is
`luals-addon`. The old `fmtk sumneko-3rd` command no longer exists in 2.1.9.

```bash
npx --yes factoriomod-debug@2.1.9 docs --online 2.1.24 .luals/fmtk   # verified: 1171 files
# fmtk docs [outdir] -d <runtime-api.json> -p <prototype-api.json> | -o [version]
#   --pdump <data-raw-dump.json> --sdump <mod-settings-dump.json> --docbase <url>
```

`.luarc.json` (LuaLS; add `.luals/` to `.gitignore`):

```json
{
  "runtime.version": "Lua 5.2",
  "runtime.path": ["?.lua"],
  "runtime.builtin": { "io": "disable", "os": "disable", "coroutine": "disable" },
  "workspace.library": [".luals/fmtk/factorio/library"],
  "runtime.plugin": ".luals/fmtk/factorio/plugin.lua",
  "diagnostics.globals": ["__DebugAdapter", "__Profiler"]
}
```

The settings above mirror the generated `config.json`; the `runtime.plugin` wiring
and directory layout of `library/` are **[unverified]** - check the generated
`config.json` and adjust. The plugin maps `storage` to a per-mod name, handles
`__mod__` requires and typed `remote` interfaces.

Optional CI type check: `lua-language-server --check=. --checklevel=Warning --logpath=.luals/log`.
Results go to the log path; the exit code on findings is **[unverified]** - fail the
job by testing the produced report instead of relying on the exit code.
Prefer luacheck as the hard gate; treat LuaLS as advisory until the report shape is confirmed.

## 5. Unit tests: busted (pure core)

```bash
luarocks install busted
busted --lpath=./?.lua spec          # spec files: spec/**/*_spec.lua (default pattern _spec)
busted -c ...                        # coverage, needs luacov
```

`.busted`:
```lua
return { default = { ROOT = { "spec" }, lpath = "./?.lua", verbose = true } }
```

Spec shape:
```lua
local pricing = require("scripts.core.pricing")
describe("pricing.compute", function()
  it("prices a product from its ingredients", function()
    local recipes = { gear = { ingredients = { { name = "iron", amount = 2 } },
                               products = { { name = "gear", amount = 1 } }, energy = 0.5 } }
    local prices = pricing.compute(recipes, { iron = 10 }, { energy_cost = 1 })
    assert.are.equal(20.5, prices.gear)
  end)
end)
```
Each spec file runs in its own `insulate` block by default (globals and
`package.loaded` restored). If core accidentally touches `game`, it errors under
busted - a second purity check on top of luacheck.

## 6. Integration tests: FactorioTest (in game, headless)

2.1-compatible: the `factorio-test` mod has a 2.1 line (3.1.0 2026-06-24 .. 3.1.2 2026-10-11,
`factorio_version 2.1`; 3.0.x is the 2.0 line). CLI `factorio-test-cli` 3.8.0 picks its bundled
save by game version (`headless-save.zip` for 2.1, `headless-save-2.0.zip` for 2.0).
Not yet run end-to-end against 2.1.24 for this repo **[verify on first CI run]**.

Register at the **end** of `control.lua` (no `info.json` dependency needed):
```lua
if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")({ "tests/terminal", "tests/market_flow" },
    { load_luassert = true })
end
```
Never `require` test files from normal code.

Test API: `describe`, `test`/`it`, `before_all`, `after_all`, `before_each`,
`after_each`, `after_test`, `.skip`, `.only` (CLI fails on `.only` unless `--no-forbid-only`).
Code inside `describe` runs at load; anything touching the game goes in tests/hooks.
Also: `test.each({...})("name %s", fn)`, `test.todo`, `tags("slow")`,
`ticks_between_tests(n)`, async via `after_ticks(n, fn)` or `async(timeout)` + `on_tick(fn)` + `done()`,
multi-step `.step("label", fn)`. **Save/load safety:** chain
`test(...).after_reload_script(fn)` / `.after_reload_mods(fn)` - the reload reruns all files,
so it proves state lives in `storage` and that `on_load` re-registers handlers. Use it for
every per-force economy state test.

Run:
```bash
npm i -D factorio-test-cli
npx factorio-test run -p .                 # headless, isolated ./factorio-test-data-dir
npx factorio-test run -p . -v "market"     # verbose + Lua-pattern filter (escape - as %-)
npx factorio-test run -p . -g -w           # graphics + watch
npx factorio-test run -p . --mods space-age   # also run with Space Age enabled
```
Behaviour: symlinks the mod into `<data-dir>/mods`, auto-detects Factorio (or
`--factorio-path`), uses a bundled empty lab-tile save (or `--save`, `--start-scenario base/freeplay`),
exits 0 only if all tests pass, kills Factorio after `--output-timeout` (15 s) of silence.
Config file: `factorio-test.json` (camelCase keys of long flags), e.g.
`{ "modPath": ".", "mods": [], "gameSpeed": 1000 }`.
Mod resolution writes `factorio-test.lock.json` - **commit it**; with `CI` set the
lockfile is frozen. Run twice in CI: without and with `space-age` (optional dependency).

## 7. Headless Factorio on Linux / WSL2

- Download is public, no login: `curl -fsSL https://factorio.com/get-download/<ver>/headless/linux64 | tar -xJ -C ~`
  (`<ver>` = `2.1.24`, or `stable`). Binary: `~/factorio/bin/x64/factorio`.
- The headless build includes the DLC mods (`space-age`, `quality`, `elevated-rails`, plus `recycler` in 2.1) - verified by listing the 2.1.24 archive; disabled unless requested (`--mods`).
- Downloading **portal mods** (deps) needs `FACTORIO_USERNAME` + `FACTORIO_TOKEN`
  (token from factorio.com/profile or `player-data.json`), not a portal API key.
  Galactic Bazaar has no portal deps today, so CI needs no secret.
- Useful flags (wiki): `--mod-directory PATH`, `--create FILE`, `--start-server FILE`,
  `--server-settings FILE`, `-c/--config PATH`, `--dump-data` (data.raw to script-output),
  `--check-unused-prototype-data`, `--disable-migration-window`, `--instrument-mod NAME`.
- Manual dev loop without FactorioTest: `ln -s "$PWD" ~/factorio/mods/galactic-bazaar`
  (folder name `galactic-bazaar` or `galactic-bazaar_<version>`), then
  `~/factorio/bin/x64/factorio --create /tmp/gb.zip` and read `~/factorio/factorio-current.log`.

### Owner's setup: repo in WSL2, game on Windows (Steam, 2.1.24)

Facts (checked 2026-10-29): Windows user data `C:\Users\aurel\AppData\Roaming\Factorio`
= `/mnt/c/Users/aurel/AppData/Roaming/Factorio`; `mods/mod-list.json` lists only `base`.
The owner does **not** own Space Age and runs no mods: **manual play-testing on the owner's
machine is vanilla only** (base game, no space-age/quality/elevated-rails).
**All Space Age coverage comes from headless runs with `--mods space-age`** (CI matrix and
local `npx factorio-test run -p . --mods space-age`). Verified 2026-10-29: the headless
2.1.24 archive contains `data/{base,core,space-age,quality,elevated-rails,recycler}/info.json`
(`recycler` is a separate built-in mod in 2.1). Consequence: any Space Age code path must have
a FactorioTest test, since no human will ever click through it; also test `--mods quality`
alone if quality handling is touched. Logs readable from WSL at
`/mnt/c/Users/aurel/AppData/Roaming/Factorio/factorio-current.log`. `rsync` is installed in WSL.

Options for putting the mod in the Windows `mods` folder:
- **(a) Sync copy WSL -> Windows (RECOMMENDED).** A script (to be written in issue #5) copies
  the shippable files into `/mnt/c/Users/aurel/AppData/Roaming/Factorio/mods/galactic-bazaar/`
  (unversioned folder name is valid). Shape:
  ```bash
  rsync -rt --delete --delete-excluded \
    --exclude='.*' --exclude='spec/' --exclude='tests/' --exclude='tools/' --exclude='docs/' \
    --exclude='node_modules/' --exclude='factorio-test-data-dir/' --exclude='dist/' \
    --exclude='*.md' --exclude='package*.json' --exclude='factorio-test*.json' \
    ./ /mnt/c/Users/aurel/AppData/Roaming/Factorio/mods/galactic-bazaar/
  ```
  Keep the exclude list identical to `info.json#/package/ignore` (or sync from the
  `fmtk package` output) so the Windows game sees exactly what ships. `--delete` is scoped to
  that one folder; guard the script against an empty/incorrect destination variable.
  Copies are plain NTFS files: no link semantics, nothing the in-game mod updater can
  follow back into the repo. Enable once in-game or with
  `npx fmtk mods --modsPath /mnt/c/Users/aurel/AppData/Roaming/Factorio/mods enable galactic-bazaar`
  (command exists in fmtk 2.1.9; not run against this folder). Restart the game (or use the
  main-menu mod reload) after syncing prototype changes.
- **(b) Windows link to `\\wsl.localhost\<distro>\home\aurel\PERSO\Factorio-Galactic-Bazaar`
  (NOT recommended).** A junction (`mklink /J`) cannot target a network path - Microsoft
  docs only allow local volumes, and `\\wsl.localhost` is a network (9P) share. A directory
  symlink (`mklink /D`, admin or Developer Mode) can target UNC paths; a forum report says
  `mklink /D` to a network drive worked in 1.1.110, broke in 2.0.8 and was fixed by 2.0.13.
  Loading a mod through a `\\wsl.localhost` symlink on 2.1.24 is **[unverified]**, works only
  while the WSL VM runs, is slow over 9P, and forum users report the in-game mod updater
  deleting files through symlinked mod folders - a risk to the git working tree.

Split of responsibilities: Windows game = manual play-testing and the FMTK debugger
(run VS Code on the Windows side or point the debugger at the Windows `factorio.exe`
**[unverified from WSL]**); Linux headless 2.1.24 inside WSL = luacheck/busted/FactorioTest
and CI parity (`./factorio-test-data-dir` is isolated, it never touches the Windows mods folder).

UPS benchmark (wiki flags; deterministic, no rendering):
```bash
~/factorio/bin/x64/factorio --mod-directory ./bench-mods \
  --benchmark saves/bazaar-1k-terminals.zip --benchmark-ticks 3600 --benchmark-runs 3 \
  --benchmark-verbose all
```
Compare the same save with the mod disabled vs enabled in `bench-mods/mod-list.json`
(`npx fmtk mods --modsPath ./bench-mods disable galactic-bazaar`). Keep a committed
stress save; record ms/tick in the PR when touching `on_tick`/`on_nth_tick` code.

## 8. Packaging and publishing

- Zip name must be `{name}_{version}.zip`; info.json mandatory fields: `name`,
  `version`, `title`, `author`; `factorio_version` effectively mandatory (`"2.1"`).
- `fmtk package --outdir dist` (verified): creates `dist/galactic-bazaar_X.Y.Z.zip`
  with top folder `galactic-bazaar_X.Y.Z/`, excluding dotfiles, `modname_*.zip` and
  globs in `info.json#/package/ignore`. **`--outdir` must already exist** (`mkdir -p dist`).
  Add to info.json: `"package": { "ignore": ["spec/**", "tests/**", "tools/**", "node_modules/**", "factorio-test-data-dir/**", "dist/**", "*.md", "package*.json", "factorio-test*.json"] }`
  (keep `tests/**` only if shipped tests are not wanted; the registration guard makes them inert anyway).
- Other fmtk commands: `datestamp`, `version` (bumps info.json + new changelog section),
  `upload <zip> [name]`, `details`, `publish` (all-in-one: requires clean tree on default
  branch, commits, tags, pushes - **conflicts with a PR workflow; don't use it from CI on PR branches**).
- Upload API (wiki): `POST https://mods.factorio.com/api/v2/mods/releases/init_upload`
  with `Authorization: Bearer $KEY`, form `mod=<name>` -> `upload_url`; then
  `POST <upload_url>` with form `file=@zip` -> `{"success":true}`. Key needs
  "ModPortal: Upload Mods" (fmtk reads it from `FACTORIO_UPLOAD_API_KEY`). Only works
  for a mod that already exists on the portal (`UnknownMod` otherwise).

### changelog.txt format (official, strict)
```
---------------------------------------------------------------------------------------------------
Version: 0.2.0
Date: 2026-10-29
  Features:
    - Terminal sells items at recipe-graph prices.
    - Long entry first line
      continuation line has exactly six spaces.
  Bugfixes:
    - Fixed int32 overflow on price signal.
```
Separator = exactly 99 `-`; `Version: a.b.c` mandatory, unique, not 0.0.0; one optional
`Date:`; category line = 2 spaces + text + `:`; entry = 4 spaces + `- `; continuation = 6 spaces;
no tabs, no trailing spaces, no duplicate entries within a category; the line after the
separator must not be empty. Errors only show in `factorio-current.log`, so validate in CI
(see `reference.md` for a checker script).

## 9. Debugging

- **FMTK debugger** (VS Code, extension `justarandomgeek.factoriomod-debug`):
  `.vscode/launch.json` `{ "type": "factorio", "request": "launch", "name": "Factorio Mod Debug" }`;
  extra keys include `factorioArgs`, `hookDebugConsole`, `trace`, `modsPath` (auto from
  `mod-list.json` in workspace). Breakpoints, stepping, profiler. Under WSL2 the debugger
  must launch a Factorio binary it can reach **[unverified: Windows-side game from WSL]**.
- `log(LocalisedString)` -> `factorio-current.log`; `print` -> stdout only;
  `localised_print` -> stdout for tools. `serpent.block(t)` to dump tables (not LuaObjects).
- Console: `/c <lua>` (prints), `/sc` silent, `/measured-command` (timing). Prefix with
  `__galactic-bazaar__` to run in the mod's Lua state: `/c __galactic-bazaar__ game.print(serpent.line(storage.forces))`.
  Any script command permanently disables achievements for that save.
- **Instrument mode**: `--instrument-mod <name>` loads `instrument-settings.lua`,
  `instrument-data.lua`, `instrument-after-data.lua`, `instrument-control.lua` early in all
  Lua states; one mod at a time; multiplayer disabled. Used by debugger/profilers.
- **Desyncs**: `/toggle-heavy-mode` (admin) saves/loads every tick and writes differing
  states to the `dumps` folder - run it in a save that exercises buy/sell/circuit paths after
  any storage or on_load change. A real desync report contains `desynced-level`,
  `reference-level.zip`, `log.txt`; diff `script.dat` (`npx fmtk scriptdat <file>` dumps it).
  Usual causes: state outside `storage`, writes in `on_load`, non-persisted upvalue caches,
  conditional event registration not replayed in `on_load`.

## 10. GitHub Actions

See `reference.md` for the full workflow (lint, busted, FactorioTest with and without
Space Age, changelog check, package artifact). Minimal lint + unit job:

```yaml
jobs:
  lint-unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: lunarmodules/luacheck@v1
      - uses: leafo/gh-actions-lua@v13
        with: { luaVersion: "5.2" }
      - uses: leafo/gh-actions-luarocks@v6
      - run: luarocks install busted
      - run: busted --lpath=./?.lua spec
```
Action major versions: checkout/setup-node/cache tags shown in FactorioTest's CI doc
are `@v7/@v7/@v6`; `@v4` is the safe long-lived tag - bump if needed **[unverified which is current]**.

## Sources (read for this skill)

- https://github.com/GlassBricks/FactorioTest (README, stable `docs/`: Getting-Started, CLI-Reference, CI, Configuration, Running-Tests, Writing-Tests); `npx factorio-test run --help` (3.8.0)
- https://mods.factorio.com/api/mods/factorio-test (2.1 line 3.1.x)
- https://github.com/justarandomgeek/vscode-factoriomod-debug (readme, doc/package.md, doc/language-lua.md, doc/language-lua-sumneko.md, doc/workspace.md, package.json); `npx fmtk --help` (2.1.9); `fmtk docs --online 2.1.24` and `fmtk package` run locally
- https://code.claude.com/docs/en/sub-agents
- https://factorio.com/api/latest-releases ; https://factorio.com/get-download/2.1.24/headless/linux64 (HTTP 302, public)
- https://lua-api.factorio.com/2.1.24/runtime-api.json and prototype-api.json (diffed against 2.0.77)
- https://wiki.factorio.com/Command_line_parameters
- https://wiki.factorio.com/Console
- https://wiki.factorio.com/Desynchronization
- https://wiki.factorio.com/Mod_upload_API
- https://lua-api.factorio.com/latest/auxiliary/changelog-format.html
- https://lua-api.factorio.com/latest/auxiliary/mod-structure.html
- https://lua-api.factorio.com/latest/auxiliary/libraries.html
- https://lua-api.factorio.com/latest/auxiliary/instrument.html
- https://lua-api.factorio.com/latest/index-runtime.html
- https://luacheck.readthedocs.io/en/stable/config.html ; https://luacheck.readthedocs.io/en/stable/cli.html ; https://github.com/lunarmodules/luacheck
- https://lunarmodules.github.io/busted/
- https://github.com/leafo/gh-actions-lua
- https://luals.github.io/wiki/usage/
- Example 2.x `.luacheckrc`: https://github.com/clusterio/universal_edges/blob/master/.luacheckrc
