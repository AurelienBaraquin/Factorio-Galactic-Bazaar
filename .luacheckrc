-- Static analysis for the Galactic Bazaar mod (luacheck 1.2.0). Run: luacheck .
-- Factorio runs a modified Lua 5.2: io, os, coroutine, loadfile and dofile do not exist, and
-- `global` is the Factorio 1.1 name of `storage`.
std = "lua52"
max_line_length = 120
exclude_files = { ".lua/**", "factorio-test-data-dir/**", "dist/**", "node_modules/**" }
not_globals = { "global", "io", "os", "coroutine", "loadfile", "dofile" }

stds.factorio_runtime = {
  globals = { "storage" },
  read_globals = { "game", "script", "remote", "commands", "settings", "rendering",
    "helpers", "prototypes", "rcon", "defines", "log", "localised_print",
    "table_size", "serpent", "__DebugAdapter", "__Profiler" },
}
stds.factorio_data = {
  globals = { "data" },
  read_globals = { "mods", "settings", "defines", "feature_flags", "helpers", "log",
    "table_size", "serpent", "localised_print" },
}

-- FactorioTest globals, from its Writing-Tests documentation.
stds.factorio_test = {
  read_globals = { "describe", "test", "it", "before_each", "after_each", "before_all", "after_all",
    "after_test", "async", "done", "on_tick", "after_ticks", "ticks_between_tests", "tags", "assert" },
}

files["control.lua"] = { std = "lua52+factorio_runtime" }
files["scripts/**/*.lua"] = { std = "lua52+factorio_runtime" }
-- Pure logic: no game API at all, so it can be unit-tested outside the game.
files["scripts/core/**/*.lua"] = { std = "lua52" }
files["data*.lua"] = { std = "lua52+factorio_data" }
files["settings*.lua"] = { std = "lua52+factorio_data" }
files["prototypes/**/*.lua"] = { std = "lua52+factorio_data" }
files["tests/**/*.lua"] = { std = "lua52+factorio_runtime+factorio_test" }
files["spec/**/*.lua"] = { std = "lua52+busted" }
