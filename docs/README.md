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
| [architecture.md](architecture.md) | How the code is organised and how its parts fit together | `info.json` `data.lua` `control.lua` `locale/` `scripts/` `changelog.txt` `docs/` `.assistant/` `.github/` `.githooks/` `.claude/` | a module, folder, flow or convention is added, moved or removed |
| [adr/](adr/) | Why the structural choices were made | decisions | a structural decision is made or reversed |
| [decisions-log.md](../.assistant/decisions-log.md) | Smaller choices and their reasons | decisions | a smaller choice is made |
| [lessons.md](../.assistant/lessons.md) | Mistakes made and what now prevents them | lessons | review, CI or the user catches a mistake |
| [README.md](README.md) | This index and the documentation tooling | `tools/check-docs.mjs` | the docs check or its workflow changes |
| [../README.md](../README.md) | Getting started: prerequisites, load check, play-test deploy, packaging | `README.md` `tools/build.py` `.gitattributes` | a prerequisite or setup step changes |
| [testing.md](testing.md) | How the code is checked and tested, and how to run each check | `.luacheckrc` `.busted` `spec/` `tests/` `package.json` `tools/setup-lua.sh` | a check, its configuration or the toolchain changes |
| [ci.md](ci.md) | What each CI pipeline runs and when | `.github/workflows/` | a workflow, trigger or step changes |
| [data-model.md](data-model.md) | What the mod persists in `storage` and its invariants | `scripts/forces.lua` `scripts/core/force_registry.lua` `scripts/core/account.lua` `scripts/pricing.lua` | the shape of `storage` or its lifecycle changes |
| [pricing.md](pricing.md) | How base values are computed, and the parameters that shape them | `scripts/recipe_graph.lua` `scripts/core/recipe_graph.lua` `scripts/core/valuation.lua` | the graph rules, the algorithm or a parameter changes |
| [market.md](market.md) | How buy and sell prices react to trades and recover | `scripts/core/market.lua` | the price model or its parameters change |
