#!/usr/bin/env bash
# Installs the Lua toolchain used by the quality checks into .lua/ (git-ignored):
# Lua 5.2 (the version Factorio embeds), LuaRocks, luacheck and busted.
# Needs python3 with pipx, a C compiler and make; no root access.
set -euo pipefail

prefix="${1:-.lua}"

pipx run hererocks "$prefix" --lua 5.2 --luarocks latest
"$prefix/bin/luarocks" install luacheck 1.2.0
"$prefix/bin/luarocks" install busted 2.3.0
