# Documentation index

Every surface of this project — anything someone needs to know to build, run, test, ship, operate
or use it — has one document, listed here. A document is updated in the same change as what it
covers. What each kind of document must contain is described by the `project-sync` skill
(`doc-surfaces.md`).

The **Covers** column lists, in code spans, the paths a document describes. The docs check
(`scripts/check-docs.mjs`) uses it: a top-level folder, `Dockerfile`, compose file, CI pipeline,
`.env.example`, API contract, schema or migrations folder that no document covers is an error,
and a document whose covered paths keep changing without it is reported as possibly stale.

| Document | What it answers | Covers | Update when |
|---|---|---|---|
| [brief.md](brief.md) | What to build and why: purpose, scope, priorities, success criteria | the intent of the project | the scope, priorities or success criteria change |
| [architecture.md](architecture.md) | How the code is organised and how its parts fit together | `info.json` `data.lua` `control.lua` `locale/` `changelog.txt` `docs/` `.assistant/` `.github/` `.githooks/` `.claude/` | a module, folder, flow or convention is added, moved or removed |
| [adr/](adr/) | Why the structural choices were made | decisions | a structural decision is made or reversed |
| [decisions-log.md](../.assistant/decisions-log.md) | Smaller choices and their reasons | decisions | a smaller choice is made |
| [lessons.md](../.assistant/lessons.md) | Mistakes made and what now prevents them | lessons | review, CI or the user catches a mistake |
| [README.md](README.md) | This index and the documentation tooling | `scripts/check-docs.mjs` `.github/workflows/docs-check.yml` | the docs check or its workflow changes |
| [../README.md](../README.md) | Getting started: prerequisites, headless load check | `README.md` | a prerequisite or setup step changes |
