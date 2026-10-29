# Architecture

How the code is organised and how its parts fit together. The *why* of each choice is in
[`adr/`](adr/); this page describes **what exists now**.

This document is kept true by whoever changes the structure, in the same change. Every path it
cites must exist (checked by `scripts/check-docs.mjs`). Sections are added when the thing they
describe exists, not before.

## 1. Layout

The repository root is the mod folder: Factorio reads `info.json`, the stage files and
`locale/` directly from it. No gameplay code exists yet.

```
info.json      mod manifest: name, version, factorio_version 2.1, dependencies (Space Age optional)
data.lua       prototype stage entry point (empty)
control.lua    runtime stage entry point (empty)
locale/        in-game text, one folder per language (en, fr)
changelog.txt  release notes in the strict format the game parses
docs/        brief, architecture, ADRs and the documentation index
scripts/     repository tooling (documentation check)
.assistant/  decisions log and lessons for AI agents
.github/     issue and pull request templates, CI workflows
.githooks/   git hooks (commit message rules, documentation check)
.claude/     Claude Code project settings, hooks, Factorio modding skills and agents
```

## 2. Conventions in place

- Economy state is keyed by force in `storage` ([ADR-0001](adr/0001-economy-state-scoped-by-force.md)).
  It is a rule for the code to come; no code applies it yet.

## 3. Decisions

See [`adr/`](adr/) for the recorded decisions and `../.assistant/decisions-log.md` for smaller
ones.
