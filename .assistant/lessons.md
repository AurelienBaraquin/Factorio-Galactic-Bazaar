# Lessons

Mistakes made on this project (by a person or an AI agent) and what now prevents them. Read it
before starting work; add to it whenever review, CI or the user catches something.

Each entry: `YYYY-MM-DD — what went wrong — how it was caught — what now prevents it`.
"What now prevents it" must be concrete: a test, a lint rule, a hook, a rule in `CLAUDE.md`, a
check in CI. An entry with no prevention is an open problem; say so.

2026-10-29 — A "vanilla" headless load check silently ran with Space Age, because the headless build enables its bundled DLC mods when `mod-list.json` does not mention them — caught by reading which mods the log loaded — the `factorio-tooling` skill and `README.md` now require listing `space-age`, `quality`, `elevated-rails` and `recycler` as disabled for vanilla runs; an automated check comes with the test setup (#4).
