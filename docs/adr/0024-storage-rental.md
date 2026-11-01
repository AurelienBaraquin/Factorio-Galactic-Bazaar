# ADR-0024 — Storage rental both ways: NPC vaults filled by uplinks, rental warehouses for NPCs

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M8)
- **Supersedes**: none (extends [ADR-0015](0015-one-contract-model.md), [ADR-0017](0017-capacity-rental-with-installments.md) and [ADR-0019](0019-service-contracts-with-a-charge.md))

## Context

The brief lists storage among the flows traded in both directions (#119): the force rents space
from a NPC (deposits goods remotely through a hub, pays a periodic rent, retrieves them later with
the normal delivery delay), and a NPC rents the force's space (deposits goods in a building of the
force, pays rent, takes them back at maturity). Both must go through the one contract model, show in
the Contracts tab and the account statement, handle payment defaults like other contracts and keep
state per force (ADR-0001). Asset seizure and penalties on third-party goods are out of scope until
1.0.

## Options considered

1. **How goods reach a NPC vault** — a GUI deposit (pick an item and an amount, taken from the
   hub's import chests or the player's inventory), or a dedicated chest attached to the hub that
   uploads what is put in it, like an export chest. The chest is automatable with inserters and
   needs no item picker; the GUI needs neither a building nor a recipe.
2. **Where vault goods come back** — to any hub of the force (a free transport between planets for
   the price of the rent), or to the hub the vault was rented at, falling back to another hub of
   the force on the same surface.
3. **A NPC vault's default** — the goods are kept until the arrears are paid (a form of seizure,
   out of scope), or the contract defaults like any service contract (guarantee kept, reputation −1)
   and the goods are shipped back regardless.
4. **The force's space rented to a NPC** — any chest the player marks (guards against every way
   to use it), or a dedicated building closed to the player, like the rental assembler.
5. **When a NPC pays the warehouse rent** — every period (the model's installments pay only for
   units delivered, which happen at maturity), or with the reward at fulfilment.
6. **Reputation for a warehouse rental** — +1 on fulfilment like any goods contract, or none, like
   a service contract, since the force does nothing but keep the goods.
7. **How large a warehouse guarantee** — the goods' value at the one-unit quote (cheaper than
   buying them back once prices rise or the order moves the market), or the cost of buying them all
   with the price impact, plus a margin.

## Decision

A **vault** (contract kind `storage`) is a service contract (ADR-0019) of `VAULT_SLOTS` (50) stacks
for 30 minutes, rented from the Contracts tab at the window's hub and accepted at once; it charges
`SLOT_RENT` (2) × `VAULT_MARKUP` (1.5) per stack every 5 minutes whatever it holds, one period held
as its guarantee. Every period is charged while the vault exists, with or without a hub: it keeps
the goods either way, and a vault that skipped periods without a hub could be kept free by mining
its hub just before each charge. A **vault
uplink** chest attached to that hub (ADR-0005) sends what is put in it into the force's vaults
rented there; only plain, non-spoilable items of normal quality, so that what comes back is what
went in. Uplinks are visited in a round robin, 2 every 6 ticks, at most 10 stack moves per pass for
the two together, so that no pass costs more however many uplinks and goods there are.

The goods stay the force's, outside the contract, and are **never seized**:
- **Retrieve** ships them, free, by orbital capsule (`freight.ship`), to the vault's own hub only
  while the vault is active (otherwise a vault would carry goods between hubs for its rent); it
  ships item by item as much as that hub's capsule queue takes and leaves the rest in the vault,
  since a queue holds 20 shipments of one item each.
- When the contract ends in any way — term over, default, abandon, bankruptcy — the vault ships its
  goods back the same way, a queue's worth each second, to its hub or, when that hub has no import
  chest, another hub of the force on its surface; until everything is shipped the vault stays in
  storage and the Overview shows the stacks still returning.
- An active vault whose hub is gone takes over only a hub of its force within 10 tiles of where
  that hub stood (a hub replaced in place); otherwise it stays unattached until its term ends,
  still charged, with Retrieve refused, so that removing a hub never moves goods to another hub.
  Once ended, its goods go to any hub of the force on its surface that has an import chest.
- A vault whose surface was deleted (detected by its index and name, since indexes are reused)
  may return its goods to a hub on any surface: the only exception, chosen over refunding a value
  so that goods always come back as goods; a deleted platform's vault goods can land on a planet.
- Capsules of vault goods carry the vault: if their hub is removed before they land, the goods go
  back to the vault (recreated if needed) instead of being sold.
- A default follows ADR-0019 (guarantee kept, reputation −1); the goods still come back.

A **rental warehouse** (kind `warehouse`) is a steel-chest derivative closed to the player
(`operable = false`). Idle, empty and attached to a hub, it is offered every 5 minutes: a NPC stores
one non-spoilable item the force's industry makes (the products of incoming-contract recipes),
worth the incoming target value × contract scale, at most half its slots. The contract provides and
requires the same goods and is a **custody** contract, a new optional field of the contract model:
its counterparty collects the goods itself, so fulfilling it earns **no reputation** (passive
income, like a service contract; with +1 a force could reach the maximum of 20 in about 75 minutes
of idle warehouses) and raises no "due soon" alert; failing it costs −1, like every failed
contract. The guarantee is deposit 0.2 × the goods' base value plus a penalty raised at acceptance
to what buying all the goods on the force's market would cost with the price impact, times 1.1
(when the market cannot sell that many, twice the offer's penalty times 1.1). The guarantee is fixed
at acceptance, so keeping the goods costs no less than buying them then; a rise of their buy price
during the term beyond the guarantee's margin — about 20 % to 30 %, depending on how far the market
stands above the base value, for example through market events (#120) — makes keeping them
cheaper, left to the balancing milestone (#122). The rent, `SLOT_RENT` per stack and
period, is the reward, paid with the guarantee when the NPC takes every unit back in the last second
of the term through a hub of the force within 10 tiles. Missing goods — taken by an inserter, the
building mined or deconstructed (the goods then go to whoever mined it) or destroyed, no hub —
fail the contract at its deadline, like a removed rental assembler.

## Consequences

- Positive: storage trades both ways with one optional field added to the contract engine
  (`custody`); both kinds share its lifecycle, money path, notifications and the Contracts,
  Overview and Statement tabs; nothing a force owns is ever seized or sold without it.
- Trade-offs accepted: a vault holds only plain normal-quality, non-spoilable items, and has one
  size; goods returning to a vault may take it past its stacks until retrieved; an unattached vault
  cannot be filled or retrieved, yet is charged; a warehouse earns
  its rent only at the end and no reputation; vault and warehouse prices are first guesses for the
  balancing milestone.
- Follow-up: vault sizes or quality support if play-testing asks for them.
