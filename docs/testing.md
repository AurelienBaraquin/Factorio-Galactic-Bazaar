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
It is covered by in-game tests once they exist (issue #4).
