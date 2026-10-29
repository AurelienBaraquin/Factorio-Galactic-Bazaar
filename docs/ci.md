# Continuous integration

The GitHub Actions pipelines of the repository: what they run, when, and how to reproduce them
locally. Both run on every pull request; a red check blocks the merge by convention (the owner
merges).

| Workflow | Trigger | Steps | Reproduce locally |
|---|---|---|---|
| `.github/workflows/docs-check.yml` | pull request or push to `main` touching Markdown, `docs/`, `.assistant/` or the checker | Node 22, `node tools/check-docs.mjs` | `node tools/check-docs.mjs` |
| `.github/workflows/ci.yml` | every pull request, push to `main` | job `lint`: Lua 5.2, LuaRocks, luacheck 1.2.0, `luacheck .`; job `unit`: Lua 5.2, busted 2.3.0, `busted` | see [testing.md](testing.md) |

No secret or variable is used. Expected duration: under a minute per job.
