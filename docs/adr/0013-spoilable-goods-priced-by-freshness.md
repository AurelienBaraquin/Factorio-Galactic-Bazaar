# ADR-0013 — Spoilable goods sell at the market price times their freshness

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
is compared with the freshness-scaled price: a chest with the default floor (0.5) sells a stack
fresher than about half, and the stack spoils in the chest after that. The market window's Sell
has a floor of 0.05 (`cargo.WINDOW_MIN_PRICE_RATIO`), so nearly spoiled stock cannot be dumped to
push a price down for almost nothing and then buy fresh goods cheaply; its preview scales the
revenue by the average freshness of the stacks the sale would take. A stack's `LuaItem` is ignored
when the item spoils and its type is on an allowlist of types that carry no data of their own
(`item`, `tool`, `capsule`, `ammo`, `module`, `gun`, `rail-planner`, `repair-tool`,
`space-platform-starter-pack`); any other type, including one a later version or a mod adds, is
not sold. `market.sell` refuses a `value_factor` outside 0 to 1.

## Consequences

- Positive: no overpayment at any quality; spoilable goods are tradeable; non-spoiling goods are
  unchanged (freshness 1).
- Trade-offs accepted: each unit still moves the market by a full unit, so selling half-spoiled
  stock lowers the price as much as fresh stock for less revenue (bounded by the floors and the
  spread); a stale stack below an export floor stays in the chest until it spoils; purchases are
  delivered fresh, and cargo waiting in a capsule does not spoil (a refund on hub removal pays it
  as fresh, at the market's sell price).
- Follow-up: the export floor's interface (#19) lets the player sell stale goods automatically.
