# Quality checks and tests

How the mod's code is checked, and how to run each check locally. CI runs the same commands
([ci.md](ci.md)).

## Local toolchain

Factorio embeds a modified Lua 5.2, so the checks run on Lua 5.2. Install it once, with LuaRocks,
luacheck and busted, into `.lua/` (git-ignored); it needs python3 with pipx, a C compiler and
make, but no root access:

```bash
./tools/setup-lua.sh
```

## Static analysis: luacheck

```bash
.lua/bin/luacheck .
```

Configuration: `.luacheckrc`. It declares the globals Factorio provides in each stage and
enforces two project rules:

- the Factorio 1.1 name `global` and the functions Factorio removes (`io`, `os`, `coroutine`,
  `loadfile`, `dofile`) are errors everywhere;
- `scripts/core/` is pure Lua: any use of the game API there is an error, so that this logic can
  be unit-tested outside the game.

Exit code `0` means clean; `1` warnings; `2` and above, syntax or configuration errors.

## Unit tests: busted

```bash
.lua/bin/busted
```

Unit tests cover the pure logic in `scripts/core/` and run outside the game, on Lua 5.2.
Specs live in `spec/`, mirror the module path and end in `_spec.lua`
(`scripts/core/force_registry.lua` → `spec/core/force_registry_spec.lua`). Configuration:
`.busted` (runs `spec/`, resolves `require("scripts.core.x")` from the repository root, as
Factorio does).

What is deliberately not unit-tested: code outside `scripts/core/`, which calls the game API.
It is covered by the in-game tests below.

## In-game tests: FactorioTest

```bash
npm ci                                                    # once: installs factorio-test-cli
PATH=~/.local/share/factorio-headless/factorio/bin/x64:$PATH npm run test:game
PATH=~/.local/share/factorio-headless/factorio/bin/x64:$PATH npm run test:game -- --mods space-age
```

The tests in `tests/` run inside a headless Factorio 2.1.24 (install: [README](../README.md)),
in an isolated `factorio-test-data-dir/` that never touches a real mods folder. They cover the
adapters in `scripts/`: storage lifecycle and force events (`tests/forces.lua`), the production
graph and base values built from the real prototypes (`tests/recipe_graph.lua`,
`tests/pricing.lua`), and that state survives a save and reload
(`.after_reload_mods`, which acts like a save and load for mods). `control.lua` registers them only when the `factorio-test` mod is
active, so they are inert in a normal game. CLI configuration: the `factorio-test` key of
`package.json`.

**Prerequisite — a Factorio account.** The CLI downloads the `factorio-test` mod from the mod
portal, which requires `FACTORIO_USERNAME` and `FACTORIO_TOKEN` (token shown on
https://factorio.com/profile) in the environment, never in the repository. CI reads them from
the repository secrets of the same names; without them the `game` job is skipped with a notice.

Space Age is not owned by the owner, so the `--mods space-age` run is the only coverage of Space
Age code paths: every such path needs a test here.
