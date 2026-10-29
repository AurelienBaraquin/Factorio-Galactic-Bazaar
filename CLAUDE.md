# CLAUDE.md

Operating guide for AI agents working in this repository. Read it first, every session. If it
conflicts with an older instruction, **this file and the documents it links win**.

## 1. Project

Galactic Bazaar is a Factorio 2.1 mod (Space Age optional) that turns every flow of the game —
items, fluids, energy, storage, machine capacity, logistics — into a tradable asset on a
simulated galactic market, for experienced players who want the challenge to move from physical
constraints to economic ones.

- Brief — what to build, scope, priorities, success criteria: `docs/brief.md`. **Read it at the
  start of every session**; it is the source of truth for *what* to build.

## 2. Map

This file stays short. Details live in the documents below — link to them, do not copy them here.

| Topic | File |
|---|---|
| What to build: purpose, scope, priorities, success criteria | `docs/brief.md` |
| Index of all documentation: structure, interfaces, deployment, CI, tests, technologies… | `docs/README.md` |
| Code structure and flows | `docs/architecture.md` |
| Decisions and their reasons | `docs/adr/` · `.assistant/decisions-log.md` |
| Mistakes already made, and what now prevents them | `.assistant/lessons.md` |
| Work tracking: milestones M0–M7, epics, issues (in French) | [GitHub Project](https://github.com/users/AurelienBaraquin/projects/3) |
| Factorio 2.1 modding knowledge: mod structure, runtime API, tooling | `.claude/skills/factorio-mod-structure/` · `.claude/skills/factorio-runtime/` · `.claude/skills/factorio-tooling/` |
| Specialised sub-agents: developer, reviewer, API researcher | `.claude/agents/` |

## 3. Hard rules

1. Never commit secrets, credentials or `.env` files; secrets come from the environment. Validate all external input at the boundary.
2. State a measurable budget before optimising, and verify it after.
3. Never store money, reputation or any economy state in a single global or per-player variable; key it by force in `storage` (ADR-0001).
4. Never commit or push to `main`. Work on a branch and open a pull request that links its issue (`Closes #N`).
5. The owner merges pull requests; you do not.
6. Branches are named `<type>/<issue>-<slug>`, for example `feat/12-pricing-engine`.
7. Commits follow Conventional Commits (`feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`, `perf`, `build`).
8. Never add `Co-Authored-By` or "Generated with" lines to commits or pull requests; `.claude/settings.json` disables them and `.githooks/commit-msg` rejects them.
9. The documentation check (`node scripts/check-docs.mjs`) runs before every commit, and fails when a surface has no document; fix what it reports instead of bypassing it.
10. The documentation check also runs in CI.
11. Enable the git hooks once per clone with `git config core.hooksPath .githooks`; Claude Code refuses `git commit` until they are active.
12. Working mode: act freely on reversible changes; stop on structural or irreversible ones. The owner can override it for a given task.
13. Always ask before: adding a dependency, deleting files or data, changing the save-data format without a migration, changing CI or hooks, pushing to `main`, publishing to the Factorio mod portal.
14. Autonomy: without asking you may edit documentation, write ADRs and decision-log entries, create branches, push branches and open pull requests. Anything else that changes the repository or the outside world: ask first.
15. Code, commits and documentation are written in English. GitHub issues and the project board are written in French. In-game text ships English and French locales.
16. Do what the task asks, nothing more.
17. Read a file fully before editing it.
18. Never state something about the code you have not verified in the code.
19. Documentation is part of done: a change is not finished until the documents that describe what it touched are updated, in the same change.
20. Everything that exists and that someone needs to build, run, test, ship, operate or use the project has one document, listed in `docs/README.md`. A new surface (interface, data model, service, technology, pipeline, environment, command, configuration variable) gets its document in the change that introduces it. Keep one home per fact: link, do not copy, and prefer a generated reference when the code is the source of truth.

## 4. Commands

```bash
git config core.hooksPath .githooks   # once per clone
node scripts/check-docs.mjs           # documentation check
```

## 5. Living documentation protocol

The documentation is part of the product. You are **authorised, and expected, to keep it
current without asking**, in the same change as the code. Decisions are not final: they can be
superseded, but never silently.

| When | Do |
|---|---|
| You start on this project with no prior context (a new session, or you are a sub-agent) | Run the `project-onboard` skill before the task; it only reads |
| You make or notice a structural choice (dependency, pattern, data model, boundary, tool, process) | Run the `adr-new` skill: an ADR if it is architectural, otherwise one dated line in `.assistant/decisions-log.md` |
| Your change adds, moves, removes or alters anything that exists in the project — a module, API, command, data model, event, configuration variable, service, technology, pipeline, environment, test setup, deployment step or user-visible behaviour | Update the document that covers it (find it in `docs/README.md`), or create it if the surface is new — the `project-sync` skill describes what each kind of document must contain — and keep the index true, in the same change |
| The scope, priorities or success criteria change (the user says so, or the work shows the brief is wrong) | Propose the change, update `docs/brief.md` once the user agrees, and record it with `adr-new`; never edit the brief silently |
| A document, rule or past decision turns out to be wrong or stale | Fix the document; for a decision, write a new ADR that supersedes the old one |
| A mistake was caught by review, CI or the user | Add an entry to `.assistant/lessons.md`; if it can be enforced, propose a test, lint rule or hook |
| Before opening a PR, and at the end of a work session | Run the `project-sync` skill and fix what it reports |

Describe only what exists. If you do not know, write it under *Open questions* and ask the
user — never guess into a document. Keep this file under about 100 lines.

## 6. Open questions

- Lint and test tooling (luacheck or LuaLS, busted, in-game test framework) — settled in milestone M0, owner validates.
- Success criteria for 1.0, beyond M1 — owner.
- Unified contract model for every exchange — ADR when the contract engine is designed.
