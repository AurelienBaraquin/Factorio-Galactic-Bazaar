# Decisions log

Running record of the choices that are too small for an ADR but worth remembering: what was
decided and why. Newest entries at the bottom. A choice that shapes the architecture gets an ADR
in `docs/adr/` and a one-line pointer here.

Format: `YYYY-MM-DD — what was decided — why (the trade-off)`.

Never rewrite history: if a choice is reversed, add a new line that says so.

2026-10-29 — Target Factorio 2.0; Space Age is an optional dependency, never required — reach both vanilla and Space Age players; every Space Age feature must degrade cleanly when the mod is absent.
2026-10-29 — Market counterparties are both abstract NPC planets and the real Space Age planets when present — keeps the economy rich in vanilla while using Space Age content when available.
2026-10-29 — Solo first, multiplayer-safe architecture — ship sooner; per-force state (ADR-0001) keeps the door open to multiplayer.
2026-10-29 — Code, commits and docs in English; GitHub issues and board in French; in-game locales en + fr — English is the norm of the Factorio modding ecosystem; the owner tracks work in French.
2026-10-29 — Work flows through issue → branch → pull request, merged by the owner — every change is traceable to an item of the GitHub Project.
2026-10-29 — Target Factorio 2.1 instead of 2.0 (reverses the first line above); Space Age stays optional — 2.1.24 is the current stable release and a mod declaring 2.0 is reported not to load on 2.1.
2026-10-29 — Repository tooling lives in `tools/`, never in `scripts/` — `scripts/` is the conventional folder for the mod's runtime code (adapters in `scripts/`, pure logic in `scripts/core/`), and `tools/` is never shipped in the mod zip.
2026-10-29 — luacheck is the static-analysis gate (local and CI); LuaLS/FMTK type checking stays an optional editor aid — luacheck's exit code is reliable and verified, LuaLS's CLI check reporting is not.
2026-10-29 — busted 2.3.0 on Lua 5.2 runs the unit tests of scripts/core/ (local and CI) — it matches Factorio's Lua version and needs no game.
