# Continuous integration

The GitHub Actions pipelines of the repository: what they run, when, and how to reproduce them
locally. Both run on every pull request; a red check blocks the merge by convention (the owner
merges).

| Workflow | Trigger | Steps | Reproduce locally |
|---|---|---|---|
| `.github/workflows/docs-check.yml` | pull request or push to `main` touching Markdown, `docs/`, `.assistant/` or the checker | Node 22, `node tools/check-docs.mjs` | `node tools/check-docs.mjs` |
| `.github/workflows/ci.yml` | every pull request, push to `main` | job `lint`: Lua 5.2, LuaRocks, luacheck 1.2.0, `luacheck .`; job `unit`: Lua 5.2, busted 2.3.0, `busted`; job `game` (matrix vanilla / `space-age`): headless 2.1.24, `npm ci`, `npx factorio-test run` | see [testing.md](testing.md) |

Secrets: `FACTORIO_USERNAME`, `FACTORIO_TOKEN` (job `game`; skipped with a notice when absent). Expected duration: under a minute per job.
