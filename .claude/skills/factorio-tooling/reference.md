# factorio-tooling - reference snippets

Companion to `SKILL.md`. Copy into the repo only when the corresponding task asks for it.

## A. Full CI workflow (`.github/workflows/ci.yml`)

Built from FactorioTest `docs/CI.md` (stable branch) and the luacheck / gh-actions-lua READMEs.
Not yet run on this repository.

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

env:
  FACTORIO_VERSION: "2.1.24"   # matches info.json factorio_version "2.1"; bump deliberately

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: lunarmodules/luacheck@v1          # runs `luacheck .`
      - uses: leafo/gh-actions-lua@v13
        with: { luaVersion: "5.2" }
      - run: lua tools/check_changelog.lua changelog.txt

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: leafo/gh-actions-lua@v13
        with: { luaVersion: "5.2" }
      - uses: leafo/gh-actions-luarocks@v6
      - run: luarocks install busted
      - run: busted --lpath=./?.lua spec

  integration:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        mods: ["", "space-age"]                 # base game, and with the optional DLC
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - uses: actions/cache@v4
        id: factorio-cache
        with:
          path: ~/factorio
          key: factorio-headless-${{ env.FACTORIO_VERSION }}
      - name: Download Factorio headless (public, no login)
        if: steps.factorio-cache.outputs.cache-hit != 'true'
        run: curl -fsSL "https://factorio.com/get-download/${FACTORIO_VERSION}/headless/linux64" | tar -xJ -C ~
      - run: echo ~/factorio/bin/x64 >> "$GITHUB_PATH"
      - run: npm ci                              # factorio-test-cli as devDependency
      - name: Run FactorioTest
        run: |
          if [ -n "${{ matrix.mods }}" ]; then
            npx factorio-test run --mod-path . --mods ${{ matrix.mods }}
          else
            npx factorio-test run --mod-path .
          fi
      # Only needed if the mod gains mod-portal dependencies:
      #   npx factorio-test mods install --mod-path .
      #   env: FACTORIO_USERNAME / FACTORIO_TOKEN secrets (account token, not portal API key)

  package:
    runs-on: ubuntu-latest
    needs: [lint, unit, integration]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: mkdir -p dist && npx --yes factoriomod-debug@2.1.9 package --outdir dist
      - uses: actions/upload-artifact@v4
        with: { name: mod-zip, path: dist/*.zip }
```

Notes:
- `CI` is set by GitHub Actions, so FactorioTest freezes `factorio-test.lock.json`: commit it
  after the first local run, and re-run `npx factorio-test mods install` when mods change.
- The `--mods` flag is variadic; put `--` before any test-filter pattern.
- FactorioTest's own CI doc uses `actions/checkout@v7`, `setup-node@v7`, `cache@v6`; any
  current major works. Pin whatever Dependabot proposes.

### Optional release job (manual, after merge to main)

```yaml
  release:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: mkdir -p dist && npx --yes factoriomod-debug@2.1.9 package --outdir dist
      - name: Upload to mod portal
        env:
          FACTORIO_UPLOAD_API_KEY: ${{ secrets.FACTORIO_UPLOAD_API_KEY }}  # "ModPortal: Upload Mods"
        run: npx --yes factoriomod-debug@2.1.9 upload dist/*.zip galactic-bazaar
```
`fmtk upload <zipname> [name]` signature is from `fmtk --help`; the env var name is from
FMTK `doc/package.md`. The first release of a new mod must be created on the portal by hand
(the API returns `UnknownMod` otherwise). Do not use `fmtk publish` in CI on this repo: it
commits, tags and pushes to the default branch, which bypasses PRs.

Raw API equivalent (wiki `Mod_upload_API`):
```bash
URL=$(curl -fsS -X POST https://mods.factorio.com/api/v2/mods/releases/init_upload \
  -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" -F mod=galactic-bazaar \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"])')
curl -fsS -X POST "$URL" -F "file=@dist/galactic-bazaar_${VERSION}.zip"   # -> {"success": true}
```

## B. `tools/check_changelog.lua`

Validates the rules of https://lua-api.factorio.com/latest/auxiliary/changelog-format.html.
Tested locally (Lua 5.4) against a valid and an invalid sample; uses only Lua 5.1+ stdlib.

```lua
-- Validates changelog.txt against the official Factorio changelog format.
local path = arg[1] or "changelog.txt"
local f = assert(io.open(path, "r"))
local SEP = string.rep("-", 99)
local errors, versions, n = {}, {}, 0
local state, seen_date, entries = "start", false, nil
local function err(msg) errors[#errors + 1] = ("%s:%d: %s"):format(path, n, msg) end
for line in f:lines() do
  n = n + 1
  if line:find("\t") then err("tab character") end
  if line:find(" $") then err("trailing space") end
  if line == SEP then
    state, seen_date, entries = "after_sep", false, {}
  elseif state == "start" then
    if line ~= "" then err("content before first separator") end
  elseif state == "after_sep" then
    local v = line:match("^Version: (%d+%.%d+%.%d+)$")
    if not v then err("line after separator must be 'Version: X.Y.Z'")
    elseif v == "0.0.0" then err("version 0.0.0 is invalid")
    elseif versions[v] then err("duplicate version " .. v)
    else versions[v] = true end
    state = "body"
  elseif line ~= "" then
    if line:match("^Date: ") then
      if seen_date then err("second Date line") end
      seen_date = true
    elseif line:match("^  [^ ].*:$") then
      state = "category"; entries.cat = line; entries[line] = entries[line] or {}
    elseif line:match("^    %- ") then
      if state ~= "category" then err("entry before any category") else
        local bucket = entries[entries.cat]
        if bucket[line] then err("duplicate entry in category") end
        bucket[line] = true
      end
    elseif line:match("^      [^ ]") then
      if state ~= "category" then err("continuation outside an entry") end
    else err("unrecognised line (check indentation: 2/4/6 spaces)") end
  end
end
f:close()
if next(versions) == nil then err("no version section found") end
for _, e in ipairs(errors) do io.stderr:write(e, "\n") end
os.exit(#errors == 0 and 0 or 1)
```
Not covered: per-component range check (0..65535) and duplicate lines inside multiline entries.
Optionally also assert the top `Version:` equals `info.json` `version` in the release job.

## C. FactorioTest file template (`tests/market_flow.lua`)

```lua
local SURFACE = 1
describe("terminal purchase", function()
  local terminal
  before_each(function()
    terminal = game.surfaces[SURFACE].create_entity({
      name = "galactic-bazaar-terminal", position = { 0, 0 }, force = "player" })
  end)
  after_each(function()
    if terminal and terminal.valid then terminal.destroy() end
  end)

  test("state is scoped to the force and survives reload", function()
    local force_index = game.forces.player.index
    assert(storage.forces[force_index] ~= nil)
  end).after_reload_mods(function()
    assert(storage.forces[game.forces.player.index] ~= nil)
  end)
end)
```
Entity/name and storage layout are placeholders; align them with the actual mod.

## D. Local one-time setup (WSL2)

```bash
sudo apt install lua5.2 liblua5.2-dev luarocks   # package names [unverified on your distro]
luarocks --local install luacheck && luarocks --local install busted
export PATH="$HOME/.luarocks/bin:$PATH"
npm i -D factorio-test-cli
curl -fsSL https://factorio.com/get-download/2.1.24/headless/linux64 | tar -xJ -C ~
npx factorio-test run -p . --factorio-path ~/factorio/bin/x64/factorio
npx --yes factoriomod-debug@2.1.9 docs --online 2.1.24 .luals/fmtk
```
