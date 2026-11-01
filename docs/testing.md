# Quality checks and tests

How the mod's code is checked, and how to run each check locally. CI runs the same commands
([ci.md](ci.md)).

## Local toolchain

Factorio embeds a modified Lua 5.2, so the checks run on Lua 5.2. Install it once, with LuaRocks,
luacheck and busted, into `.lua/` (git-ignored); it needs python3 with pipx, a C compiler and
make, but no root access:

```bash
./tools/setup-lua.sh
```

The `pre-commit` git hook (`.githooks/pre-commit`) runs the documentation check, then luacheck and
busted when `.lua/` is installed, before every commit.

## Static analysis: luacheck

```bash
.lua/bin/luacheck .
```

Configuration: `.luacheckrc`. It declares the globals Factorio provides in each stage and
enforces two project rules:

- the Factorio 1.1 name `global` and the functions Factorio removes (`io`, `os`, `coroutine`,
  `loadfile`, `dofile`) are errors everywhere;
- `scripts/core/` is pure Lua: any use of the game API there is an error, so that this logic can
  be unit-tested outside the game.

Exit code `0` means clean; `1` warnings; `2` and above, syntax or configuration errors.

## Unit tests: busted

```bash
.lua/bin/busted
```

Unit tests cover the pure logic in `scripts/core/` and run outside the game, on Lua 5.2.
Specs live in `spec/`, mirror the module path and end in `_spec.lua`
(`scripts/core/force_registry.lua` → `spec/core/force_registry_spec.lua`). Configuration:
`.busted` (runs `spec/`, resolves `require("scripts.core.x")` from the repository root, as
Factorio does).

One spec checks files rather than logic: `spec/locale_spec.lua` reads `locale/en` and `locale/fr`
and fails when a key is repeated (Factorio refuses to load the mod), when a key uses other parameters
(`__1__`...) in French than in English, when the two languages do not
define the same keys, when a `"section.key"` literal of `control.lua`, `data.lua`, `settings.lua`,
`scripts/` or `prototypes/` names a key English lacks, or when a Tips and tricks entry of
`prototypes/tips_and_tricks.lua` (loaded with and without Space Age and quality) has no name or
description. Keys built at run time are not seen; the headless game cannot check them either, since
it translates nothing without a connected client.

What is deliberately not unit-tested: code outside `scripts/core/`, which calls the game API.
It is covered by the in-game tests below.

## In-game tests: FactorioTest

```bash
npm ci                                                    # once: installs factorio-test-cli
PATH=~/.local/share/factorio-headless/factorio/bin/x64:$PATH npm run test:game
PATH=~/.local/share/factorio-headless/factorio/bin/x64:$PATH npm run test:game -- --mods space-age
```

The tests in `tests/` run inside a headless Factorio 2.1.24 (install: [README](../README.md)),
in an isolated `factorio-test-data-dir/` that never touches a real mods folder. They cover the
adapters in `scripts/`: storage lifecycle and force events (`tests/forces.lua`), the overdraft and its interest (`tests/overdraft.lua`), contracts (`tests/contracts.lua`), loans, their default, repayment, merge and the Contracts tab's credit line (`tests/loans.lua`), the financial engineering research: borrowing gated by credit, overdraft levels from research events, resets and older saves (`tests/finance.lua`), insolvency, its refusals, bankruptcy, force merge and the Market tab's status (`tests/insolvency.lua`), incoming contracts, the contract chest and the Contracts tab (`tests/incoming_contracts.lua`), machine rental (`tests/rental.lua`), NPC planets, transit and their tab (`tests/planets.lua`), mining concessions, outsourced production and their research gating (`tests/concessions.lua`), the production
graph and base values built from the real prototypes (`tests/recipe_graph.lua`,
`tests/pricing.lua`), value overrides through the remote interface (`tests/overrides.lua`), quality values and markets (`tests/quality.lua`, effective in the Space Age run), per-force trading (`tests/market.lua`), the terminal buildings
(`tests/hubs.lua`, `tests/cargo.lua`, including spoilable goods priced by freshness in the Space Age run), catapults (`tests/catapult.lua`), fluid manifolds (`tests/manifold.lua`), delivery by orbital capsule and tiers (`tests/freight.lua`), docking bays (`tests/docking_bay.lua`), teleporters (`tests/teleporter.lua`), power trading (`tests/power.lua`), price signal combinators (`tests/price_signals.lua`), order combinators (`tests/circuit_orders.lua`), telecommunications (`tests/telecom.lua`), the coherence of the research tree (`tests/technologies.lua`), the status of each building, its alerts, refresh cycle and cost, and saves that predate it (`tests/entity_status.lua`) and the Market tab driven through the test save's
player (`tests/market_gui.lua`), the Market tab's item detail: its figures before and after trades, the price history with and without telecommunications 2, the base value breakdown checked against every real base value, overrides, quality, an item without a market, a save from before the breakdown, a reload and its refresh cost (`tests/item_detail.lua`), notifications: each kind's alert, the per-player settings, grouping and throttling (`tests/notifications.lua`), the Galactic Bazaar window: hotkey and button gated by
research, tabs built when first shown, the hub it binds, trading only within reach and never from
remote view, events of a save from before the window and its leftover windows, the Overview
figures, the removal of older saves' windows and each tab's refresh cost, with no hub in reach too (`tests/bazaar_gui.lua`;
`test_helpers.select_tab` picks a tab as a click would), the Logistics tab: hubs, purchases,
incoming contract ingredients and planet shipments with their state, origin and cost, a long queue
paged, modules and their status, the camera, selection refused for another force's hub or
building, a save from before the tab, its refresh cost and a reload (`tests/logistics_gui.lua`), the Statement tab: rows updated in place,
subjects and labels of every kind of entry, the category filter, period totals from the ledger,
pagination, the contract kind recorded by a real loan, a save without the window's state, the
ledger or entry categories, its refresh cost on a full journal and ledger, the cost of recording
transactions into a full journal of 200 recurring goods, and merging into a journal entry across a reload
(`tests/statement_gui.lua`), the built-in explanations: the Tips and tricks entries (the Space Age
and quality ones only with them), the tooltips of the Market, Contracts, Planets and Logistics tabs,
those that follow the force's state written only when it changes, and their caches across a reload
(`tests/explanations.lua`), and that state survives a save and reload
(`.after_reload_mods`, which acts like a save and load for mods). A reload re-runs the test file, so `after_each`
re-fetches what it needs instead of trusting the file's locals. The periodic handlers keep running
between tests, so a test never assigns a force's balance directly: it calls
`test_helpers.set_balance(state, balance)` from `tests/helpers.lua`, which also resets the low-water
marks (`overdraft_low`, `solvency_low`) and drops any insolvency or recovery in progress, or the
interest or insolvency check would act on the balance the test left behind. Name the module's local
`test_helpers`: `helpers` is the game's own global (`helpers.create_profiler`). `control.lua` registers them only when the `factorio-test` mod is
active, so they are inert in a normal game. CLI configuration: the `factorio-test` key of
`package.json`.

**Prerequisite — a Factorio account.** The CLI downloads the `factorio-test` mod from the mod
portal, which requires `FACTORIO_USERNAME` and `FACTORIO_TOKEN` (token shown on
https://factorio.com/profile) in the environment, never in the repository. CI reads them from
the repository secrets of the same names; without them the `game` job is skipped with a notice.

Refresh costs (`tests/bazaar_gui.lua`, `tests/logistics_gui.lua`, `tests/entity_status.lua` and the
module tests that measure a pass) are logged, not asserted: `LuaProfiler` values cannot be read from
Lua, so a budget is checked by reading the `[galactic-bazaar] … tab refresh` and similar lines in
`factorio-test-data-dir/factorio-current.log` after a run. A measurement that follows a burst of
allocation (placing hundreds of buildings, or the test files run before it) collects garbage first
(`collectgarbage("collect")`, then a warm-up): otherwise the collector charges that garbage to the code
measured. Since that hides the collection the code's own garbage drives, `tests/logistics_gui.lua`
also logs what each refresh allocates (collector stopped) and single refreshes with a collector that
never pauses (`collectgarbage("setpause", 100)`, restored after), whose median and worst case are
read from the log.

Space Age is not owned by the owner, so the `--mods space-age` run is the only coverage of Space
Age code paths: every such path needs a test here.
