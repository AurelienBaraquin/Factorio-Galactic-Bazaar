# ADR-0009 — Spoilable goods sell at the market price times their freshness

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent)
- **Supersedes**: none

## Context

With Space Age, items such as nutrients, bioflux and agricultural science packs spoil: each stack
has a `spoil_percent` that rises from 0 the moment it is made. Issue #56 reported that export
chests and the market window would sell an almost spoiled stack at its full base value, and with
quality values (ADR-0008, legendary ×243) the overpayment would be large. The in-game tests showed
that in 2.1 every stack of a spoilable item carries a `LuaItem` (to hold its spoilage), so the
"plain stack" check of `scripts/cargo.lua` refused them all: spoilable goods could not be sold at
all. Letting them through needs a pricing rule. Requiring `spoil_percent == 0` is not one, since
nothing stays fresh.

## Options considered

1. **Scale the revenue by freshness** (`1 - spoil_percent`), the market moving by the units sold —
   continuous, no cliff, a half-spoiled stack is worth half; the market sees a full unit of supply
   for a fraction of the credits.
2. **Refuse stacks past a freshness threshold**, paying full value below it — simple, but a cliff
   that still overpays just under the threshold, and a constant to tune.
3. **Scale the revenue and move the market by freshness-equivalent units** — the goods' "value
   supplied" moves the price, but a market measured in units would drift from the units actually
   sold.

## Decision

Option 1. `cargo.sell_stacks` passes the stack's freshness to `market.sell`, which multiplies the
revenue by it (`value_factor`) and moves the market by the units sold. The price floor of an export
chest keeps its meaning — each unit must fetch at least `min_price_ratio` × its base value — so it
is compared with the freshness-scaled price: a chest with the default floor (0.5) keeps a stack
fresher than about half, and the stack spoils in the chest after that. The market window's Sell has
no floor and always sells. A stack's `LuaItem` is ignored when the item spoils and its type carries
no data of its own (grid, inventory, label, tags, blueprint, entity data).

## Consequences

- Positive: no overpayment at any quality; spoilable goods are tradeable; non-spoiling goods are
  unchanged (freshness 1).
- Trade-offs accepted: the window's preview prices fresh goods, the printed result gives the real
  revenue; a stale stack below an export floor stays in the chest until it spoils; purchases are
  delivered fresh.
- Follow-up: the export floor's interface (#19) lets the player sell stale goods automatically.
