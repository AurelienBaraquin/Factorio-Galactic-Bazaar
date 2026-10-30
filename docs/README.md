# Documentation index

Every surface of this project — anything someone needs to know to build, run, test, ship, operate
or use it — has one document, listed here. A document is updated in the same change as what it
covers. What each kind of document must contain is described by the `project-sync` skill
(`doc-surfaces.md`).

The **Covers** column lists, in code spans, the paths a document describes. The docs check
(`tools/check-docs.mjs`) uses it: a top-level folder, `Dockerfile`, compose file, CI pipeline,
`.env.example`, API contract, schema or migrations folder that no document covers is an error,
and a document whose covered paths keep changing without it is reported as possibly stale.

| Document | What it answers | Covers | Update when |
|---|---|---|---|
| [brief.md](brief.md) | What to build and why: purpose, scope, priorities, success criteria | the intent of the project | the scope, priorities or success criteria change |
| [architecture.md](architecture.md) | How the code is organised and how its parts fit together | `info.json` `settings.lua` `data.lua` `control.lua` `locale/` `scripts/` `changelog.txt` `docs/` `.assistant/` `.github/` `.githooks/` `.claude/` | a module, folder, flow or convention is added, moved or removed |
| [adr/](adr/) | Why the structural choices were made | decisions | a structural decision is made or reversed |
| [decisions-log.md](../.assistant/decisions-log.md) | Smaller choices and their reasons | decisions | a smaller choice is made |
| [lessons.md](../.assistant/lessons.md) | Mistakes made and what now prevents them | lessons | review, CI or the user catches a mistake |
| [README.md](README.md) | This index and the documentation tooling | `tools/check-docs.mjs` | the docs check or its workflow changes |
| [../README.md](../README.md) | Getting started: prerequisites, load check, play-test deploy, packaging | `README.md` `tools/build.py` `.gitattributes` | a prerequisite or setup step changes |
| [testing.md](testing.md) | How the code is checked and tested, and how to run each check | `.luacheckrc` `.busted` `spec/` `tests/` `package.json` `tools/setup-lua.sh` | a check, its configuration or the toolchain changes |
| [ci.md](ci.md) | What each CI pipeline runs and when | `.github/workflows/` | a workflow, trigger or step changes |
| [data-model.md](data-model.md) | What the mod persists in `storage` and its invariants | `scripts/forces.lua` `scripts/core/force_registry.lua` `scripts/core/account.lua` `scripts/core/power_settlement.lua` `scripts/pricing.lua` `scripts/hubs.lua` `scripts/cargo.lua` `scripts/freight.lua` `scripts/power.lua` `scripts/price_signals.lua` `scripts/circuit_orders.lua` `scripts/market_gui.lua` | the shape of `storage` or its lifecycle changes |
| [pricing.md](pricing.md) | How base values are computed, and the parameters that shape them | `scripts/recipe_graph.lua` `scripts/core/recipe_graph.lua` `scripts/core/valuation.lua` `scripts/core/overrides.lua` `scripts/core/quality.lua` `scripts/pricing.lua` `scripts/value_overrides.lua` `settings.lua` | the graph rules, the algorithm or a parameter changes |
| [market.md](market.md) | How buy and sell prices react to trades and recover, how forces trade | `scripts/market.lua` `scripts/core/market.lua` `scripts/core/npc_market.lua` `scripts/core/random.lua` | the price model or its parameters change |
| [terminal.md](terminal.md) | The trading hub and its modules: prototypes, power, recipes, registry | `prototypes/` `scripts/hubs.lua` `scripts/cargo.lua` `scripts/market_gui.lua` `scripts/core/catalog.lua` `scripts/freight.lua` `scripts/core/freight.lua` `scripts/power.lua` `scripts/price_signals.lua` `scripts/core/signals.lua` `scripts/circuit_orders.lua` `scripts/core/orders.lua` | a terminal building, its recipe, its registry, the market window or a delivery tier changes |
| [player-guide.md](player-guide.md) | What the mod puts on and reads from the circuit network, its units and examples, for players | the circuit signals and orders | a signal, its unit or its refresh changes |
