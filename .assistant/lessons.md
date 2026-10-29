# Lessons

Mistakes made on this project (by a person or an AI agent) and what now prevents them. Read it
before starting work; add to it whenever review, CI or the user catches something.

Each entry: `YYYY-MM-DD — what went wrong — how it was caught — what now prevents it`.
"What now prevents it" must be concrete: a test, a lint rule, a hook, a rule in `CLAUDE.md`, a
check in CI. An entry with no prevention is an open problem; say so.

2026-10-29 — A "vanilla" headless load check silently ran with Space Age, because the headless build enables its bundled DLC mods when `mod-list.json` does not mention them — caught by reading which mods the log loaded — the `factorio-tooling` skill and `README.md` now require listing `space-age`, `quality`, `elevated-rails` and `recycler` as disabled for vanilla runs; an automated check comes with the test setup (#4).
2026-10-29 — The first in-game save/reload test used FactorioTest's `.after_reload_script`, copied from the tooling skill; for a mod it calls `game.reload_script`, which only reloads the scenario script, so the run aborted ("Reload was requested but did not happen") — caught by the first real FactorioTest run — the skill, the reference and both Factorio agents now prescribe `.after_reload_mods`, and the `game` CI job runs the test on every PR.
