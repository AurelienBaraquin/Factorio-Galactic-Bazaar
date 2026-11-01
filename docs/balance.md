# Balance: the progression simulation

How the economy's balance is measured: a pure-Lua simulation that plays typical progressions through
the real modules of `scripts/core/` on the game's own base values, the invariants checked on every
test run, and the figures of the balancing pass of #122 before and after it. The rules it changed are
in [ADR-0026](adr/0026-contract-pay-follows-work-and-the-spread.md), each constant in the
[decisions log](../.assistant/decisions-log.md).

## Running it

```bash
.lua/bin/lua tools/balance/report.lua   # prints every table below as Markdown (about 2 s)
.lua/bin/busted spec/balance_spec.lua   # the invariants (also part of .lua/bin/busted)
```

| File | Role |
|---|---|
| `tools/balance/sim.lua` | the simulation: scenarios, export and import flows, contracts, rentals, warehouses, loans, exploit checks, research bought with credits. It calls `scripts/core/market.lua`, `contract_offers.lua`, `storage_rental.lua`, `loans.lua`, `reputation.lua`, `freight.lua`, `account.lua`, `planets.lua`, `transit.lua`, and reads `prototypes/technologies.lua` with a stand-in `data` |
| `tools/balance/values.lua` | snapshot of the base values, stack sizes and 16 incoming-contract recipes of Factorio 2.1.24, vanilla and Space Age, as the mod computes them (generated, see below) |
| `tools/balance/report.lua` | prints the tables |
| `tools/balance/snapshot.py` | writes `values.lua` from two JSON dumps of the game |
| `spec/balance_spec.lua` | the economic invariants (below) |

A few figures belong to adapters or prototypes, which need the game, and are copied in `sim.lua`
with their source: the export chests' price floor (`cargo.DEFAULT_MIN_PRICE_RATIO`, 0.5), the rental
assembler's speed (0.75), the rental warehouse's 48 slots, one offer every 5 minutes, 8 listed
contracts. `tests/balance.lua` checks in game that they equal the adapters' and prototypes' values.

### Regenerating the snapshot

When the valuation ([pricing.md](pricing.md)) or the game version changes: add a temporary test file
to the FactorioTest list of `control.lua` that researches everything for the player force and writes
`helpers.table_to_json({values = storage.base_values, recipes = incoming.candidates(force), stack =
{[name] = stack_size}})` with `helpers.write_file`, run it with and without `--mods space-age`
(the file lands in `factorio-test-data-dir/script-output/`), then
`tools/balance/snapshot.py <vanilla.json> <space-age.json> > tools/balance/values.lua`, and remove
the test file.

## Scenarios

Assumptions, not measurements: what a force exports and imports every minute at each stage. Exports
go through export chests (sold every second while the next unit fetches half its base value, the
rest waiting); imports are bought every minute by the stage's delivery tier. Each runs 3 hours and
the last hour is measured, at steady state.

| Scenario | Tier, reputation | Exports a minute | Imports a minute | Rentals, loan |
|---|---|---|---|---|
| vanilla early (red science, just after Galactic Bazaar) | capsule, 0 | 240 iron and copper plates, 60 stone, 60 coal, 30 gears, 30 circuits | 10 steel | none, 5 000 |
| vanilla mid (blue science, oil) | shuttle, 10 | 900 iron and copper plates, 120 steel, 300 plastic, 300 circuits, 30 advanced circuits, 60 sulfur, 30 batteries, 10 engines | 10 chemical science, 5 electric engines | 4, 20 000 |
| vanilla late (rocket) | teleporter, 20 | 2 700 iron and copper plates, 450 steel, 900 plastic, 900 circuits, 180 advanced circuits, 20 processing units, 20 low density structures, 40 rocket fuel, 4 speed modules | 5 production and 5 utility science | 5, 100 000 |
| Space Age mid (Vulcanus, Fulgora) | shuttle, 10 | as vanilla mid, with 150 steel, 60 advanced circuits, 20 tungsten plates, 60 holmium plates, no sulfur or engines | 10 chemical science | 4, 20 000 |
| Space Age late | teleporter, 20 | as vanilla late, with 40 processing units and structures, 40 tungsten, 180 holmium, 60 carbon fibre, 20 supercapacitors, 5 quantum processors | 5 production and 5 utility science | 5, 100 000 |

Incoming contracts: one offer every 5 minutes, accepted and fulfilled, each paying the median reward
of the snapshot's recipes at the scenario's reputation (the report also gives the mean). Rentals: the scenario's rental assemblers
rented all the time, each paying the mean rent of the snapshot's recipes.

## Results (credits an hour)

Before (0.1.38) and after (0.1.39). Exports, imports, fees and loan interest did not change.

| Scenario | Exports | Imports | Fees | Incoming before → after | Rentals before → after | Loan interest | Net before → after | Reputation / h before → after |
|---|---|---|---|---|---|---|---|---|
| vanilla early | 45 066 | 5 481 | 274 | 292 → 886 (mean 904) | 0 → 0 | 500 | 39 103 → 39 697 | 12 → 12 |
| vanilla mid | 158 317 | 37 105 | 835 | 523 → 1 524 (mean 1 714) | 1 141 732 → 4 320 | 1 500 | 1 261 133 → 124 721 | 20 → 12 |
| vanilla late | 246 560 | 136 201 | 681 | 600 → 2 227 (mean 2 457) | 1 427 165 → 5 400 | 5 000 | 1 532 444 → 112 306 | 22 → 12 |
| Space Age mid | 166 830 | 17 107 | 385 | 532 → 1 720 (mean 2 175) | 590 652 → 4 320 | 1 500 | 739 022 → 153 878 | 20 → 12 |
| Space Age late | 306 456 | 75 907 | 380 | 612 → 2 400 (mean 3 158) | 738 314 → 5 400 | 5 000 | 964 096 → 232 970 | 22 → 12 |

The vanilla late scenario nets less than vanilla mid: it buys 5 production and 5 utility science
packs a minute, 136 000 credits an hour, because their markets are thin (a pack is worth about 133
credits, so 20 000 credits of depth is 150 packs). Buying high-tier science costs more than its
base value; making it is the cheaper way, which is the point.

From reputation 0, the best reputation (20) takes 100 minutes of fulfilled crafting contracts (it
took 30 minutes from 10 with four idle rental assemblers before).

**Exports** (unchanged): share of the production sold in the last hour — early 100 %, vanilla mid
81 %, vanilla late 33 %, Space Age mid 86 %, Space Age late 40 %. Whatever its value and volume, one
good earns at most **26 694 credits an hour** from export chests: selling it as fast as its own
reversion allows at the 0.5 floor (`depth_credits` × ln(0.95 / 0.5) × ln 2 / half-life × 0.5).
Income grows by selling more kinds of goods, not more of one: the liquidity challenge of
[ADR-0003](adr/0003-market-price-model.md), kept.

**Incoming contracts** (reputation 0, capsule; medians of the snapshot's recipes; the 2σ column is
the best net when products are 2 standard deviations of NPC drift cheaper and ingredients as much
dearer):

| | Reward | Reward / products | Reward / crafting second | Best buy-and-deliver net | Same, drift 2σ |
|---|---|---|---|---|---|
| vanilla before → after | 24.3 → 73.8 | 2.4 % → 7.4 % | 0.10 → 0.32 | −185.6 → −138.4 | 150.2 → 203.8 |
| Space Age before → after | 22.2 → 71.8 | 2.2 % → 7.2 % | 0.10 → 0.32 | −180.4 → −134.6 | 143.0 → 193.2 |

The work cap (1 credit a crafting second) binds for quick, valuable crafts: a spidertron's offer
paid 3 408 before the cap and pays 10 now, on an 82 000-credit guarantee.

The snapshot's recipes add more value than most. Over all candidates, measured once in game on
2026-11-01 (the dumps behind the snapshot; the full lists are not kept): 173 vanilla recipes, median
reward about 5 credits before and 48 after (4.1 % of the products, the work cap binding for 105 of
them, largest 158); 207 with Space Age, 200 of them viable, median 56.5 after (5.1 %, largest 232).

**Machine rentals** (a rental assembler, speed 0.75):

| | Rent per term (mean) | Rent per term (max) | Rent / guarantee an hour (mean) | Reputation per rental |
|---|---|---|---|---|
| vanilla before → after | 142 717 → 540 | 2 207 861 (spidertron) → 540 | 50.0 % → 25.7 % | 1 → 0 |
| Space Age before → after | 73 831 → 540 | 1 136 076 → 540 | 46.7 % → 37.8 % | 1 → 0 |

**Warehouse rentals** (unchanged, reputation 0): rent over the term, guarantee at acceptance on a
balanced market, and the NPC drift at which keeping and selling the goods would beat handing them
back.

| Goods | Units | Rent | Worth | Guarantee | Drift to keep and sell |
|---|---|---|---|---|---|
| wood | 2 400 | 288 | 300 | 409 | 0.902 depths (11.2σ) |
| iron plate | 758 | 96 | 1 001 | 1 385 | 0.468 (5.8σ) |
| electronic circuit | 292 | 24 | 1 000 | 1 385 | 0.419 (5.2σ) |
| processing unit | 11 | 12 | 1 048 | 1 453 | 0.412 (5.1σ) |
| tungsten plate (Space Age) | 46 | 12 | 1 016 | 1 407 | 0.411 (5.1σ) |

**Credit** (unchanged): a loan's interest over its hour is 15 %, 10 %, 7.5 % and 5 % of the
principal at reputation −20, 0, 10 and 20; 100 000 needs reputation 10 or more (debt cap). The
overdraft costs 3 000 an hour on 10 000 of debt, 30 % an hour: always dearer than a loan.

**Research bought with credits** (science packs bought at once on a balanced market, capsule fee):
2 000 to 3 400 credits for the red and green technologies (2 to 5 minutes of early net income),
about 20 000 for the blue ones (31 minutes early, 10 mid); the teleporter's 500 production and
utility packs cost 1.24 million in vanilla and 0.38 million with Space Age bought at once, because
their markets are thin: buy late science gradually, or make it.

## Exploits examined

| Loop | Finding | Outcome |
|---|---|---|
| Machine rental | rent was 30 % of the products' value: a risk-free 50 % of the guarantee an hour, unbounded by the recipe's value (2.2 million a term for a spidertron), funded by a loan at 10 % an hour | **closed**: rent per crafting second, 540 a term whatever the recipe (ADR-0026) |
| Rental reputation | each fulfilled rental gave +1: four idle machines took a force from 10 to 20 in 30 minutes, with nothing at stake | **closed**: rentals are passive, no reputation (ADR-0026) |
| Incoming contracts | the reward was capped at the value crafting adds: about 5 credits for most recipes, a dead channel | **reworked**: the value crafting adds plus half the spread a market round trip loses, still below that loss, and at most 1 credit a crafting second (ADR-0026) |
| Incoming reward following value | before the work cap, a spidertron paid 3 408 for a 10-second craft, about 44 % an hour on its 82 000 guarantee funded by a loan | **closed**: the work cap (independent review of #127) |
| Shortage offers on dead recipes | in Space Age, gears, pipes and cables cost more to assemble than to cast, so no offer can be made of them; a shortage of one took half the offers for nothing | **closed**: offers draw only among viable recipes (`contract_offers.viable`) |
| Buying the products to fulfil an incoming contract | loses 135 to 190 credits a contract on a balanced market; pays when NPC drift moves the products and ingredients far enough apart (break-even when the products drift about 0.07 depth down and the ingredients as much up, 0.8σ each; 2σ each gives about +200); bounded by 12 offers an hour | accepted: a trader's opportunity, not a pump; the reward is still capped by base values |
| Market round trips from balance | best −4.3 % over quantities up to 5 depths and waits up to 10 hours | none |
| Own reversion (ADR-0003) | buying back at its own depressed price and selling once it has recovered returns +5 % (+10.5 % for small trades, [market.md](market.md)), but the whole cycle (the sale that depressed it included) always earns less than selling less in the first place | accepted: it recovers part of the force's own price impact, never more; checked by the spec |
| Warehouse guarantee (ADR-0024) | keeping and selling the goods beats handing them back only from 5.1σ of NPC drift (events never raise a sell price); keeping them when their *buy* price rose (a shortage) saves buying them, at a cost of at least 1.2 × their base value and −1 reputation | accepted: a costly hedge, never a source of credits; no re-pricing |
| Concessions and outsourcing | reselling what a lease ships pays from 0.06 and 0.11 depths of NPC drift (0.8σ, 1.4σ), but the lease charges for 30 minutes while the drift reverts in 10, and abandoning costs the guarantee and reputation | accepted |
| Loan funding a guaranteed contract | the only risk-free yields left are rentals (540 a term per machine) and warehouses (rent of a few to 288 a term), both bounded by 8 listed contracts | none |
| Market events | a surplus of 0.7 depths for 14 minutes takes 5.1 % of a saturated export's income over 3 hours; one exported good meets a surplus about once every 300 hours at frequency 1 (0.0032 an hour, 218 candidates) | defaults kept; see "Open questions" |

## Invariants (`spec/balance_spec.lua`)

- No closed round trip from a balanced market pays, up to 5 depths and 10 hours apart; the
  own-reversion cycle never beats selling less at once.
- One good's export income never exceeds the ceiling, at any value and volume.
- Buying the products and selling the ingredients of an incoming contract never pays on a balanced
  market, at every reputation and tier, vanilla and Space Age; at base prices the reward leaves at
  least a quarter of the spread as a margin, and `SPREAD_SHARE` is below 1; a reward pays more than
  the value crafting adds, except where the work cap binds, where it equals the cap.
- A rental's rent stays within its machine-time bound whatever the recipe, and a fulfilled rental
  earns no reputation (read from the engine's own settlement);
  8 rentals earn under a quarter of the vanilla mid exports.
- Keeping and selling a warehouse's goods needs more than 4σ of NPC drift, for every snapshot good at
  reputation −20, 0 and 20.
- The overdraft costs more an hour than any loan, and no loan is free.
- Concession and outsourcing prices lie within a balanced market's spread.
- Every scenario has a positive net income with contracts under a quarter of exports, and the best
  reputation takes at least 1.5 hours of contracts.

## Not modelled

NPC drift and market events inside the scenarios (examined separately above), freshness, quality
markets, power trading, fluids, planets' transit delays, insolvency. Scenarios are assumptions about
a typical factory; the snapshot holds 16 recipes, not all candidates.

## Open questions

- Market events reach the goods a force trades rarely, because they are drawn among every
  tradeable key (218 in vanilla, 320 with Space Age). Weighting the draw towards the goods forces
  trade would make them felt without raising the frequency; to decide with the owner.
- Quality: values grow ×3 a level; whether quality modules and recycling make a quality level for
  less than 3 normal items, which would make selling quality a money source, is not measured.
