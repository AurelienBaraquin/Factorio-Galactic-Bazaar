# ADR-0007 — Value overrides are fixed sources of the valuation, set by a remote interface

- **Status**: Accepted
- **Date**: 2026-10-30
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M1)
- **Supersedes**: none

## Context

Base values come from the production graph (ADR-0002). Issue #10 asks that other mods can fix or
adjust a value through a documented `remote` interface, with input checks, and that a startup
setting scales every value. The open question is what an override does to the items made from the
overridden one.

## Options considered

1. **Override the key only** — the value is replaced after valuation. Simple, but products keep the
   old cost of their ingredients: a mod that makes iron plates worth 10 leaves gears at 2.7, and a
   recycler turns that gap into free credits.
2. **Override as a fixed source** — the value is set before valuation and no recipe may change it;
   every product made from it follows. A factor ("twice what the graph says") needs the graph's
   value first, so it takes a second valuation pass.
3. **Override recipe costs** — mods adjust `TIME_COST` per recipe. Precise, but far from what a mod
   author wants to say ("this ore is rare").

## Decision

Option 2. `remote.call("galactic-bazaar", …)` offers `set_value`, `scale_value`, `clear_value` and
`get_value`; overrides persist in `storage.value_overrides`, keyed like base values, and each change
recomputes every base value. A fixed value is final: the startup multiplier `gb-value-multiplier`
scales every other value. A fixed value is a source from the main tier on; a factor keeps the tier
the graph priced its key in (ADR-0002 tiers), so a factor of 1 is neutral and a factor never lets a
natural source undercut a production chain. Values and factors are bounded so every value stays
finite and above the floor. Invalid input (a key that is not a tradeable item or fluid, a missing or
out-of-range number, a call during `on_load`) raises an error in the calling mod, since it is a
programming mistake. After every rebuild, each market's displacement is rescaled by
`V_old / V_new` and bounded again, so a price stays the same multiple of its base value.

## Consequences

- Positive: an override is consistent with the whole economy; no arbitrage between an overridden
  input and its products; the interface is four functions.
- Trade-offs accepted: each call recomputes everything (17 ms vanilla, 47 ms Space Age, measured on
  2.1.24), fine for calls made once in a mod's `on_init` or `on_configuration_changed`, not for calls
  every tick; prices move with their base value at once (relative market state is kept); factors
  do not compound along a chain.
- Follow-up: a batch call if mods set many values at once.
