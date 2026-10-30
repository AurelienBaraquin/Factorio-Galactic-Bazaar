# Architecture

How the code is organised and how its parts fit together. The *why* of each choice is in
[`adr/`](adr/); this page describes **what exists now**.

This document is kept true by whoever changes the structure, in the same change. Every path it
cites must exist (checked by `tools/check-docs.mjs`). Sections are added when the thing they
describe exists, not before.

## 1. Layout

The repository root is the mod folder: Factorio reads `info.json`, the stage files and
`locale/` directly from it. No gameplay code exists yet.

```
info.json       mod manifest: name, version, factorio_version 2.1, dependencies (Space Age optional)
data.lua        prototype stage entry point: requires one file per prototype family
prototypes/     prototype definitions (trading hub, cargo chests, technologies, custom inputs)
control.lua     runtime stage entry point: registers every event handler
locale/         in-game text, one folder per language (en, fr)
scripts/        runtime adapters between the game API and the pure logic
scripts/core/   pure Lua logic, no game API (checked by luacheck, unit-tested)
changelog.txt   release notes in the strict format the game parses
spec/           busted unit tests of scripts/core/
tests/          FactorioTest in-game tests of scripts/
package.json    development tooling only (FactorioTest CLI)
tools/          repository tooling: Lua toolchain setup, packaging and deploy, documentation check
docs/           brief, architecture, ADRs and the documentation index
.assistant/     decisions log and lessons for AI agents
.github/        issue and pull request templates, CI workflows
.githooks/      git hooks (commit message rules, documentation check)
.claude/        Claude Code project settings, hooks, Factorio modding skills and agents
```

Only the first eight entries ship in the mod: `.gitattributes` marks everything else
`export-ignore`, and `tools/build.py` uses that list for both the zip and play-test deploys.

## 2. Conventions in place

- Economy state is keyed by force in `storage` ([ADR-0001](adr/0001-economy-state-scoped-by-force.md));
  shape and invariants in [data-model.md](data-model.md).
- Two layers: `scripts/core/` is pure Lua that takes and returns plain tables (unit-tested with
  busted, game API forbidden by luacheck); `scripts/` adapts it to the game (reads the API,
  calls core, writes `storage`).
- `control.lua` is the only file that registers event handlers, because Factorio keeps one
  handler per event per mod; modules expose handler functions and `control.lua` composes them.

## 3. Flows

- **Init and configuration change**: `control.lua` calls `forces.init` (one state per force, with
  its account), `pricing.init` (base values from the prototypes, [pricing.md](pricing.md)),
  `hubs.init` (drops hubs that no longer exist) and `cargo.init` (drops chests that no longer
  exist, re-attaches the others).
- **Building events**: `control.lua` routes every way an entity can appear (filtered to the mod's
  buildings) to `hubs.on_built`, or `cargo.on_built` for a chest; a new hub also re-attaches nearby
  modules. `on_object_destroyed` forgets a hub (its modules look for another) or a chest
  ([terminal.md](terminal.md)).
- **Export**: `script.on_nth_tick(cargo.EXPORT_INTERVAL)` sells the next batch of export chests.
- **Market window**: the `gb-open-hub` input opens it; `on_gui_click` and `on_gui_text_changed`
  dispatch on the element's `gb_action` tag; `on_gui_closed` and `on_player_removed` drop it;
  `script.on_nth_tick(market_gui.REFRESH_INTERVAL)` refreshes open windows.
- **Force events**: creation and merging update `storage.forces` ([data-model.md](data-model.md));
  after a merge, every cargo chest is re-attached.
- **Market**: `scripts/market.lua` quotes and executes trades for a force, advancing each key's
  NPC market lazily when read ([market.md](market.md)); export chests sell through it.

## 4. Decisions

See [`adr/`](adr/) for the recorded decisions and `../.assistant/decisions-log.md` for smaller
ones.
