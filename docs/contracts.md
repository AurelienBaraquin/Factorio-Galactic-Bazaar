# Contracts

Exchanges that span time — a counterparty provides goods, the force hands goods back before a
deadline — share one model and lifecycle ([ADR-0015](adr/0015-one-contract-model.md)). The pure
engine is `scripts/core/contracts.lua`; the runtime side is `scripts/contracts.lua`. Market spot
trades are not contracts ([market.md](market.md)).

## Model

| Field | Meaning |
|---|---|
| `kind`, `counterparty` | what kind of contract (incoming, capacity…) and who it is with |
| `provides` | goods the counterparty delivers to the force: `{kind = "item"\|"fluid", name, quality, count}` (copied; count positive and finite) |
| `requires` | goods the force must hand over (at least one, each `kind/name@quality` key once) |
| `reward`, `deposit`, `penalty` | credits, each from 0 to 10¹²: paid on fulfilment; the guarantee held on acceptance is deposit plus penalty |
| `duration_ticks`, `accept_ticks` | time to fulfil once accepted; time the offer stands (both positive and finite) |
| `charge` | optional credits the force pays every installment period: a service contract ([ADR-0019](adr/0019-service-contracts-with-a-charge.md)), whose `requires` may be empty |
| `advance` | optional credits (needs a `charge`) paid to the force at acceptance: a loan, whose charge repays it with interest and needs no service ([ADR-0021](adr/0021-loans.md)) |
| `installment_ticks`, `paid`, `next_installment` | optional period at which the reward is paid in installments ([ADR-0017](adr/0017-capacity-rental-with-installments.md)); reward paid so far; tick of the next installment |
| `custody` | optional: the counterparty collects the goods back itself (a warehouse rental, [ADR-0024](adr/0024-storage-rental.md)); fulfilling it earns no reputation, and no "due soon" alert is raised |
| `passive` | optional: the counterparty supplies everything and the force's machine only runs (a machine rental, [ADR-0026](adr/0026-contract-pay-follows-work-and-the-spread.md)); fulfilling it earns no reputation |
| `state` | `offered`, `active`, `fulfilled`, `failed`, `expired`, `declined` or `voided` |
| `delivered` | units handed over so far, per `kind/name` key |
| `offered_tick`, `accept_by`, `accepted_tick`, `due_tick`, `completed_tick`, `settled_tick`, `id` | lifecycle ticks, and the id, unique across all forces |

## Lifecycle

| From | Event | To | Money (through the force's account) | Reputation |
|---|---|---|---|---|
| — | `contracts.offer(force, spec)` | offered | — | — |
| offered | `contracts.accept(force, id)` (refused without the guarantee, or while the force is insolvent: `insolvent`) | active | − deposit − penalty (`contract-guarantee`, when not 0); + advance (`contract-advance`) | — |
| offered | `contracts.decline(force, id)` | declined | — | — |
| active | `contracts.deliver(force, id, key, count)`, until the deadline | active | — | — |
| active | every `installment_ticks`, at the next settlement | active | + reward × share of required units delivered − `paid` (`contract-installment`) | — |
| active (service) | every `installment_ticks` on its schedule from acceptance, up to the deadline: a period the service of its kind cannot deliver is skipped; otherwise the service delivers it, then the charge is taken; a period not delivered is not charged | active | − charge (`contract-charge`) | — |
| active (service) | a charge the available funds (balance plus overdraft, [data-model.md](data-model.md)) cannot cover, or `contracts.abandon` | failed | nothing back: the guarantee is kept | −1 |
| active (loan) | every `installment_ticks` on its schedule up to the deadline: the charge, with no service | active | − charge (`contract-charge`) | — |
| active (loan) | a charge the available funds cannot cover | failed | that charge and every one left become the force's arrears | −1 |
| active (loan) | `contracts.abandon`: every charge left (`contracts.payoff`) is taken first; refused (`insufficient-funds`), changing nothing, when the available funds cannot cover it, and settled only once taken | fulfilled | − charges left (`contract-repaid`) | — |
| active (service) | its term ended (`due_tick` passed) and its last period charged | fulfilled | + deposit + penalty (`contract-fulfilled`) | — |
| active | every required unit delivered, at the next settlement (or on abandon) | fulfilled | + reward − `paid` + deposit + penalty (`contract-fulfilled`) | +1 (0 for a `custody` contract, whose counterparty collects its goods itself: a warehouse rental, and for a `passive` one: a machine rental) |
| active | deadline passed, at the next settlement, or `contracts.abandon` before completion | failed | nothing back: the guarantee is kept, installments paid stay paid (`contract-failed`, amount 0) | −1 |
| offered | offer window passed | expired | — | — |
| active | `contracts.void(force, id)`: its goods no longer exist (a mod was removed); never a loan, whose debt would vanish | voided | + deposit + penalty (`contract-voided`) | — |
| offered / active | the force goes bankrupt (see Insolvency and bankruptcy) | declined / failed | nothing back: the guarantee is kept (`contract-failed`, amount 0); a loan's installments left join the bankruptcy debt | reputation set to −20 |

A required amount within 10⁻⁶ of complete counts as delivered (fluid amounts are fractional).
Settlement runs every `contracts.SETTLE_TICKS` (60), contract ids in order. A settled contract
leaves the open contracts for the force's history (the newest `HISTORY_SIZE`, 20).

## Reputation

Each force has one score (`scripts/core/reputation.lua`, [ADR-0016](adr/0016-bounded-reputation-with-effects.md)),
moved by contract outcomes and kept within [`MIN`, `MAX`] = [−20, 20].

| Effect | Rule |
|---|---|
| Freight fees | every purchase's fee × `fee_factor` = 1 − `FEE_STEP` (0.025) × score: ×0.5 at 20, ×1.5 at −20 (`freight.preview`, `freight.order`) |
| Contract size | incoming offers aim at `TARGET_VALUE` × `contract_scale` = max(`MIN_SIZE` (0.5), 1 + `SIZE_STEP` (0.1) × score): ×3 at 20, ×0.5 from −5 down; the reward follows the batch |
| Force merge | the destination keeps its score less the source's debt (`reputation.merge`) |
| Loans | interest rate and debt cap (see Loans) |
| Bankruptcy | the score falls to −20 (see Insolvency and bankruptcy) |

The Overview tab shows the score and its effects on fees, contract sizes and loans ([window.md](window.md)); the Market tab shows the score, with its effects in the tooltip ([terminal.md](terminal.md)).

## Incoming contracts

Counterparties offer each force to craft for them (#76): they provide a batch of a recipe's
ingredients, the force hands back its products. Code: `scripts/incoming_contracts.lua` (runtime),
`scripts/core/contract_offers.lua` (pricing, pure), `scripts/contracts_gui.lua` (the Contracts tab of the Galactic Bazaar window, [window.md](window.md), which
also lists machine rentals; each row's counterparty tooltip names the kind, and every other cell's
tooltip gives the rule behind it for that kind and state, [window.md](window.md#explanations)). Every button of the
tab — Accept, Decline, Abandon, Repay, Borrow — needs a hub of the force within reach (the
window's), or nothing happens and the player is told why; an active contract's Decline cell stays in
place, empty and disabled.

| | |
|---|---|
| Unlock | the `gb-contracts` technology, which also unlocks the contract chest ([terminal.md](terminal.md)) |
| Offers | every `incoming.OFFER_TICKS` (5 min), each force that researched it, owns a hub, has fewer than `MAX_OFFERS` (3) open incoming offers and fewer than `contracts.MAX_LISTED` (8) contracts of the listed kinds (incoming and rental, `contracts.LISTED_KINDS`, which also lists warehouse rentals, concessions, outsourcing bookings, vaults and loans) open, offered or active (the rows of the Contracts tab), gets one; the recipe and counterparty are drawn from the force's own deterministic random state. While a market event pushes a good's price up by `SHORTAGE_DEPTHS` (0.1 depths) or more ([market.md](market.md#market-events-scriptscoremarket_eventslua-scriptsmarket_eventslua)), the offer names, with chance `SHORTAGE_CHANCE` (0.5), a recipe whose product is such a good (`contract_offers.pick_short`), on the usual terms ([ADR-0026](adr/0026-contract-pay-follows-work-and-the-spread.md)). The force is told of new offers, of contracts due within 2 minutes and of each fulfilment or failure at settlement ([notifications.md](notifications.md)) |
| Recipes | enabled, not hidden, made in an assembling machine (`crafting` or `advanced-crafting`), item ingredients only and one sure item product in a whole amount (no range, probability or extra fraction), every good with a base value, products worth more than ingredients; sorted by name before the draw |
| Batch | enough crafts for the products to be worth `TARGET_VALUE` (1 000) credits × the force's contract scale (see Reputation), from 1 to `MAX_BATCH` (1 000) |
| Terms | reward = the value crafting adds (products' minus ingredients' base value) plus `SPREAD_SHARE` (0.5) of what the market's spread takes from buying the products and selling the ingredients (spread / 2 × both values), at most `LABOR_SHARE` (0.3) × products' value, so buying the products and selling the ingredients still loses half the spread on a balanced market ([ADR-0026](adr/0026-contract-pay-follows-work-and-the-spread.md), [balance.md](balance.md)); deposit = `DEPOSIT_SHARE` (0.2) and penalty = `PENALTY_SHARE` (1) × ingredients' base value; at acceptance the penalty rises to what the ingredients would sell for on the force's market then, if more, so the guarantee always exceeds what the force receives; time = recipe time × batch × `TIME_FACTOR` (4) + `MARGIN_TICKS` (5 min); the offer stands `ACCEPT_TICKS` (5 min) |
| Acceptance | from the Contracts tab, at the window's hub, which must be within reach ([window.md](window.md)): every check of `contracts.can_accept` (still offered, not past its end, the guarantee within the available funds, overdraft included) runs first; then the ingredients are shipped, free, by orbital capsule to that hub (`freight.ship`, all or nothing: refused without an import chest, or when the capsule queue would overflow), and only then is the guarantee taken |
| Delivery | every `COLLECT_TICKS` (60), each contract chest attached to a hub hands over the normal-quality items its force's active incoming contracts still need, oldest contract first; what no contract needs stays in the chest; the chest's status lists what they still need ([terminal.md](terminal.md#building-status)) |

Deviation: ingredients always travel by orbital capsule (the counterparty's ship), whatever tier
the hub has. Capsules of a contract carry its id and a unit cost of 0: when the hub is removed they
are dropped, not sold back, since the force never paid for them. On configuration change, incoming
contracts whose goods no longer exist are withdrawn: offers declined, active contracts voided with
their guarantee back; their capsules are dropped without refund.

## Machine rental

Counterparties rent the force's rental assemblers (#78, [ADR-0017](adr/0017-capacity-rental-with-installments.md)).
Code: `scripts/rental.lua` (runtime), `scripts/core/contract_offers.lua` (`rental_crafts`,
`rental`); the building is described in [terminal.md](terminal.md).

| | |
|---|---|
| Unlock | the `gb-capacity-rental` technology (rental assembler) |
| Offers | every `rental.OFFER_TICKS` (5 min), each idle rental assembler attached to a hub, of a force that researched it and has room in the Contracts tab, is offered, in unit number order; the recipe is drawn like an incoming contract's among those of the machine's crafting categories whose surface conditions (Space Age) the machine's surface meets; the machine is reserved for that offer until it ends |
| Terms | `RENTAL_TICKS` (30 min); the products of `rental_crafts` crafts: `CAPACITY_SHARE` (0.8) of what the machine makes at its nominal speed in that time; reward (rent) = `RENT_PER_SECOND` (0.5 credit) × the seconds of crafting at speed 1 it promises (crafts × recipe time: 540 credits a term for a rental assembler, whatever the recipe, [ADR-0026](adr/0026-contract-pay-follows-work-and-the-spread.md)), paid every `INSTALLMENT_TICKS` (5 min) for what was delivered; a `passive` contract: fulfilling it earns no reputation; deposit = 0.2 and penalty = 1 × the products' or ingredients' base value, whichever is more |
| Acceptance | from the Contracts tab: refused when the machine is gone (`machine-gone`) or has no hub (`machine-no-hub`); the penalty rises to the market value of the products or ingredients, whichever is more; the guarantee is held, then the machine gets the recipe |
| Service | every `SERVICE_TICKS` (60), through a hub of its force: the machine keeps the contract's recipe (a pasted or other recipe is undone; an idle machine has none), its normal-quality products are taken (all of them: a surplus, from a productivity bonus, is the counterparty's too) and delivered, and, until the contract is complete, its ingredients topped up to `BUFFER_SECONDS` (4 s) of crafting, at least one craft, never beyond what the contract provides in all |
| End | once the contract is settled, declined or expired, the machine is released: its recipe, ingredients and products go back to the counterparty. A machine removed during a rental cannot fulfil it: the contract fails at its deadline. On configuration change, a rental whose recipe the machine can no longer craft (removed, or moved to another category) is withdrawn — declined if offered, voided with its guarantee back if active — and its machine released; one whose goods no longer exist is withdrawn like an incoming contract |

The rent needs no cap by the value crafting adds, unlike an incoming contract's reward: only
products the script takes from the machine count, so buying them on the market cannot fulfil the
contract. The machine is closed to the player's GUI, but inserters, mining or a paste can still
take from it what is in it between two services; any such taking leaves the contract short, and
the guarantee exceeds what can be taken.

## Storage rental

Storage trades both ways (#119, [ADR-0024](adr/0024-storage-rental.md)), after the
`gb-storage-rental` research, which unlocks both buildings ([terminal.md](terminal.md)). Code:
`scripts/vaults.lua`, `scripts/warehouses.lua` (runtime), `scripts/core/storage_rental.lua` (terms,
pure).

### Vaults: the force rents a NPC's space

| | |
|---|---|
| Rent | the Contracts tab's **Rent a vault** button (`vaults.rent`), at the window's hub: a `storage` contract offered and accepted at once with a counterparty of `VAULT_OPERATORS`, or nothing changes; refused `not-researched`, `no-import-chest` (the hub has none), `too-many-contracts`, `insolvent`, `insufficient-funds` (`not-offered` and `expired` cannot happen: the offer is accepted in its own tick) |
| Terms | `VAULT_SLOTS` (50) stacks for `TERM_TICKS` (30 min); charge `SLOT_RENT` (2) × `VAULT_MARKUP` (1.5) per stack (150 credits) every `PERIOD_TICKS` (5 min), whatever it holds; its service (`storage`) serves every period while the vault exists, with or without a hub, since it keeps the goods either way (so removing a hub before a charge never skips it); guarantee one period's charge; no reward, no reputation on fulfilment |
| Hub | the hub it was rented at, its position kept; when that hub is gone, every `vaults.SWEEP_TICKS` (60) the active vault takes over the nearest hub of its force on the same surface within `REATTACH_RANGE` (10 tiles) of where its hub stood (a hub replaced in place), import chest or not; otherwise it stays unattached until its term ends, still charged, its uplinks feeding nothing and Retrieve refused (`no-hub`), so that removing a hub never moves goods to another one; uplinks feed only the vault's current hub |
| Filling | every `vaults.UPLINK_TICKS` (6), the next `UPLINK_BATCH` (2) vault uplinks in turn (20 a second, as export chests) send what they hold into the force's active vaults rented at their hub, oldest first, up to each vault's stacks, at most `MAX_MOVES` (10) stack moves a pass for the 2 uplinks together (a stack split between two vaults counts twice); only items of normal quality, of a type whose stacks carry no data (`cargo.DATALESS_ITEM_TYPES`) and not spoilable, and plain (`cargo.is_plain`: undamaged, unused), so that what comes back is what went in; the rest stays in the uplink, whose status says so. A vault may hold more than its stacks only when goods return to it (see Capsules); it then takes nothing until it is back within them |
| Retrieve | the row's **Retrieve** button (`vaults.retrieve`) ships the vault's goods to the vault's own hub only (never another hub while the vault is active), by orbital capsule (`freight.ship`, free): item by item, as much as that hub's capsule queue takes (`freight.capsule_room`: 20 shipments of at most 10 stacks of one item, one launch every 10 s, landing 30 s after launch); what does not fit stays in the vault and the player is told how many stacks. Refused `no-hub` (the vault is unattached), `no-import-chest` (its hub has none), `queue-full` (nothing could ship). The vault stays rented |
| End | when the contract ends in any way — term over (guarantee back), a charge the available funds cannot cover or Abandon (failed: guarantee kept, −1 reputation), bankruptcy — every sweep ships what fits of the goods back the same way, never seized: to the vault's hub when it has an import chest, else to the first hub of the force on its surface that has one. What does not fit waits for the next sweep; the vault is forgotten once empty. The Overview's **Vault goods returning** line shows what ended vaults still have to ship |
| Deleted surface | a vault keeps its surface's index and name; its surface counts as deleted when no surface has that index, or the one that has it bears another name (indexes of deleted surfaces can be reused, [LuaSurface::index](https://lua-api.factorio.com/2.1.24/classes/LuaSurface.html#index)). Then, and only then, its returning goods may go to a hub of the force on any surface: the goods of a vault rented on a space platform that was deleted can land on a planet that way. An active vault on a deleted surface stays unattached until its term ends |
| Capsules | capsules bringing a vault's goods back carry `vault` = {id, surface_index, surface_name}; if their hub is removed before they land, `freight.on_hub_removed` hands them to the vault (`freight.register_returner`), recreated if it was already forgotten, and they ship again; they are never sold. Cargo whose item no longer exists after a mod change is dropped, like the vault's own goods of that item |

### Warehouse rentals: a NPC rents the force's space

| | |
|---|---|
| Offers | every `warehouses.OFFER_TICKS` (5 min), each idle, empty rental warehouse attached to a hub, of a force that researched storage rental and has room in the Contracts tab, is offered, in unit number order; the item is drawn from the sole products of the recipes an incoming contract could name, not spoilable |
| Terms | `storage_rental.warehouse`: units worth `contract_offers.TARGET_VALUE` × the force's contract scale (see Reputation), at least 1, at most `FILL_SHARE` (half) of the warehouse's slots; the contract provides and requires those units and is a `custody` contract (its counterparty collects the goods itself); reward (the rent) = `SLOT_RENT` (2) × stacks × periods (6), paid at fulfilment; deposit 0.2 and penalty 1 × their base value; `TERM_TICKS` (30 min) |
| Acceptance | from the Contracts tab: refused `warehouse-gone`, `warehouse-no-hub`, `warehouse-not-empty`; the penalty rises to `storage_rental.warehouse_penalty`: what buying all the goods on the force's market would cost now, with the price impact (`market.preview`, and never less than on the plain market, `market.plain_preview`, so that a market event never lowers it, [ADR-0025](adr/0025-market-events-as-a-shared-displacement-shift.md)), times `BUY_MARGIN` (1.1), or, when the market cannot sell that many, the offer's penalty × `UNQUOTED_FACTOR` (2) × `BUY_MARGIN`, never below the offer's penalty, so that keeping the goods costs no less than buying them at acceptance (the guarantee is fixed at acceptance: deposit (0.2 × the goods' base value) plus the penalty; if their buy price rises during the term by more than the guarantee's margin over that cost — between about 20 % and 30 %, for example through a shortage — keeping them saves buying them, at a cost of at least 1.2 × their base value and −1 reputation; selling them instead pays only from 5σ of NPC drift, since events never raise a sell price, so the guarantee is not re-priced: [balance.md](balance.md)); every `contracts.can_accept` check runs, then the goods are put in the warehouse (refused and undone if they do not fit), the guarantee is held, and the penalty is set back if the acceptance fails |
| Maturity | in the last `SERVICE_TICKS` (60) before the deadline, through a hub of its force within 10 tiles, the counterparty takes back what the warehouse holds of its goods, up to what is owed; all of it fulfils the contract at the next settlement: rent and guarantee, and no reputation (a custody contract, like a service contract: passive income earns none). No "contract due" alert is raised for it, since the force has nothing to deliver |
| Failure | goods missing at maturity — taken out by an inserter, the warehouse mined or deconstructed (its goods then go to whoever mined it) or destroyed, no hub in range — fail the contract at its deadline: the guarantee is kept and −1 reputation, like every failed contract |
| End | once the contract is settled, declined or expired, the warehouse is released and what is left of the counterparty's goods leaves it |

## Loans

A force borrows from the Galactic Credit Union (#96, [ADR-0021](adr/0021-loans.md)). Code:
`scripts/loans.lua` (runtime), `scripts/core/loans.lua` (terms and bounds, pure), the credit line of
`scripts/contracts_gui.lua`, the research `scripts/finance.lua`.

### Research

The financial engineering branch (#98, `prototypes/technologies.lua`, [terminal.md](terminal.md)).
Its effects are script-side (`nothing` effects with a description):

| Technology | After | Cost | Effect |
|---|---|---|---|
| `gb-credit` | `gb-contracts` | 150 × red, green | borrowing (`finance.CREDIT_TECHNOLOGY`): without it `loans.borrow` refuses with `not-researched` and the Borrow buttons are disabled, their tooltip naming the technology |
| `gb-overdraft-1` | `gb-credit` | 200 × red, green | overdraft limit 25 000 credits (from `account.BASE_OVERDRAFT_LIMIT`, 10 000) at reputation 0 or above |
| `gb-overdraft-2` | `gb-overdraft-1`, chemical science | 300 × red, green, blue | overdraft limit 100 000 credits at reputation 0 or above |

The limits are `account.OVERDRAFT_LEVEL_LIMITS`, one per technology of
`finance.OVERDRAFT_TECHNOLOGIES`. A level's extra over the base follows reputation
([ADR-0020](adr/0020-overdraft-and-debit-interest.md), amendment): `BASE + (level limit − BASE) ×
min(1, reputation.contract_scale(reputation))`, half the extra from −5 down (17 500 and 55 000),
the full extra from 0 up; the base is never scaled. The pure account cannot read research, so `scripts/finance.lua`
records each force's level, the highest overdraft technology researched, in
`storage.forces[i].overdraft_level`: on `on_research_finished` and `on_research_reversed` of these
technologies, on `on_force_reset` and `on_technology_effects_reset`, on init and configuration
change for every force, and for every force before each overdraft interest charge (once a minute), so
research changed without a per-technology event (`research_all_technologies`,
`reset_technologies`, `copy_from`) is picked up within a minute. Un-researching a level or losing
reputation lowers the limit at once: a balance below the new
limit spends nothing until it comes back, and pays interest on its debt up to the new limit.
Without the credit research, loans already taken are still repaid (installments, the Repay button)
and arrears still collected; the credit line still shows the debt.

| | |
|---|---|
| Unlock | `gb-credit` (see Research above); the Contracts tab shows its credit line from the start |
| Tiers | `TIERS`: 5 000, 20 000 or 100 000 credits, each one button; the contract is offered and accepted at once (`loans.borrow`), or nothing changes. Like Accept, the Borrow and Repay buttons need a hub of the force within reach (the window's, [window.md](window.md)), or nothing happens and the player is told why |
| Terms | the principal (`advance`) is paid at acceptance; `TERM_TICKS` (60 min), `PERIOD_TICKS` (5 min): 12 installments of principal × (1 + rate) / 12; no deposit, penalty or reward |
| Rate | over the term, fixed at borrowing: `BASE_RATE` (10 %) − `RATE_STEP` (0.25 %) × reputation, 5 % at 20, 15 % at −20 |
| Debt cap | `DEBT_CAP` (50 000) × the reputation's contract scale: 25 000 from −5 down, 150 000 at 20; the debt is the principal active loans still have to repay, principal × whole installments left / 12, plus arrears (`loans.outstanding`); a loan that would take it above the cap is refused (`debt-cap`) |
| Refusals | `not-researched` before `gb-credit`; `insolvent` while the force is insolvent; `credit-ban` during the credit ban after a bankruptcy; `debt-cap` (the debt counts loans only, not the overdraft); `overdrawn` when the available funds are below zero (the balance beyond the overdraft limit: `contracts.can_accept` refuses even a zero guarantee); `in-arrears` while any arrears are owed; `too-many-contracts` when `contracts.MAX_LISTED` listed contracts (loans included) are open; `invalid-amount` for an unknown tier |
| Repay | the row's **Repay** button (`contracts.abandon`) pays every installment left at once, interest included (`contract-repaid`), taken before the loan is settled; refused, changing nothing, when the available funds cannot cover it |
| Installments | one the available funds can pay is paid, even into the overdraft (which then pays its debit interest) |
| Default | an installment the available funds cannot cover fails the loan (−1 reputation); that installment and every one left become the force's `arrears`, taken every `loans.COLLECT_TICKS` (60) from the available funds, down to the overdraft limit (`loan-arrears`, journaled in one entry per minute): unpaid loan debt becomes overdraft debt, which pays debit interest; arrears beyond the overdraft stay owed until income covers them |
| Force merge | open loans carry over with the contract book; arrears add up |

## Insolvency and bankruptcy

A force that can no longer pay its debts gets a grace period, then goes bankrupt (#97,
[ADR-0022](adr/0022-insolvency-and-bankruptcy.md)). Code: `scripts/core/insolvency.lua` (rules,
pure), `scripts/insolvency.lua` (the check handler and the force's messages, told through
[notifications.md](notifications.md)); the Overview and
Market tabs show the state ([window.md](window.md), [terminal.md](terminal.md)).

| | |
|---|---|
| Check | every `CHECK_TICKS` (60), after the arrears collection, every force in index order (`insolvency.check_all`), from its lowest balance since the previous check (`solvency_low`, kept by every account transaction) |
| Insolvent | the lowest balance of the period was beyond the overdraft limit (`account.available` below 0), or the arrears exceed the available funds; `insolvent_since` records the check; the force is told the balance to reach and the time it has |
| Blocked | `contracts.can_accept` refuses every contract (`insolvent`: incoming contracts, rentals, leases, bookings, loans; a lease is refused before its offer is filed); no loan is granted. Selling, exports, power exports and contract deliveries go on. Purchases are only refused by the funds check, so a force insolvent through arrears, or recovering, may still buy |
| Recovery | once every check over `RECOVERY_TICKS` (an interest period, one minute) found the period's lowest balance leaving at least `RECOVERY_SHARE` (5 %) of the overdraft limit available, with no arrears owed (`recovery_balance`: the balance that leaves 5 % of the current limit available, read at each check, so it follows the force's research and reputation; −9 500 credits at the base limit; `recovering_since` records the first such check, a check that misses it clears it); the force is told once, never at each dip |
| Bankruptcy | at the first check `GRACE_TICKS` (10 min) or more after insolvency began whose period missed the margin: offers declined and active contracts failed (guarantees kept, each journaled as a 0-credit `contract-failed`); nothing is written off: the negative balance, the arrears and each active loan's installments left (`contracts.payoff`), plus a `RESTRUCTURING_SURCHARGE` of 25 % of them, move into `bankruptcy_debt`, the balance and arrears set to 0 (one `bankruptcy-restructured` entry: its amount brings the balance to 0, its `owed`, `surcharge` and `debt` fields hold what was owed, the surcharge and the total); reputation set to −20, `bankruptcies` + 1 and credit refused (`credit_ban_until`); the force is told what ended and what it owes |
| Bankruptcy debt | frozen: no interest, the surcharge standing in for it (a deliberate bankruptcy only costs fewer credits than repaying when the debt would take over about 100 minutes of income, [ADR-0022](adr/0022-insolvency-and-bankruptcy.md)). Garnished at the point of credit: `account.apply` sends every credit (sales, exports, rewards, refunds) to it first, as far as the balance is positive, and each check takes a positive balance already there; never into the overdraft (`bankruptcy-debt`, journaled in one entry per minute) |
| Credit ban | until both `BAN_TICKS` (60 min) × 2^(bankruptcies − 1), at most 8 hours, have passed and `bankruptcy_debt` is 0: the overdraft limit is 0 (no overdraft, no interest) and loans are refused (`credit-ban`); contracts that need no credit can be taken. The force is told when it ends. Credit then returns with the reputation of −20 the bankruptcy left, which halves a researched overdraft's extra over the base (#98); the balance is 0 by then, so the smaller limit cannot make the force insolvent again |
| What a bankruptcy leaves | leases release their planet slots at the next concessions sweep and rented machines are released at the next rental service, both because their contract is no longer active; goods already paid (capsules in flight, planet shipments in transit, an incoming contract's ingredients) still land |
| Force merge | the destination keeps the earliest `insolvent_since` (its recovery restarts), the latest `credit_ban_until` and the most `bankruptcies` (merging into a fresh force restarts nothing); bankruptcy debts and lowest balances add up. A merge can therefore impose the stricter ban, and the debt, on a healthy destination force |

## Storage

`storage.forces[i].contracts = {open = {[id] = contract}, history = {contract...}}`,
`storage.forces[i].reputation` (a score, 0 to start, within [−20, 20]), `storage.forces[i].arrears`
(credits a defaulted loan left owed), `storage.forces[i].overdraft_level` (the overdraft research
level), the insolvency fields `insolvent_since`, `recovering_since`, `credit_ban_until`,
`bankruptcies`, `bankruptcy_debt` and `solvency_low`, and `storage.contract_next_id`, the next id —
see [data-model.md](data-model.md); `storage.incoming_contracts` holds the contract chests and each
force's random state, `storage.rentals` the rental assemblers, `storage.vaults` the vaults and
vault uplinks, `storage.warehouses` the rental warehouses; the Contracts tab's state lives in
`storage.bazaar_gui` ([window.md](window.md)).
