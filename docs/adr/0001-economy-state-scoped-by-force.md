# ADR-0001 — Economy state is scoped by force

- **Status**: Accepted
- **Date**: 2026-10-29
- **Deciders**: Aurélien Baraquin (owner)
- **Supersedes**: none

## Context

Galactic Bazaar gives each player a balance, a reputation, open orders, contracts and market
history. The mod ships solo first, but must not block multiplayer later. In Factorio, the unit
that owns research, entities and alliances is the *force* (`LuaForce`), not the player, and the
persistent mod state lives in `storage` (the name, since Factorio 2.0, of the former `global`), which must stay
deterministic across all clients.

## Options considered

1. **One global value** (e.g. `storage.money`) — simplest, but there is exactly one economy for
   the whole map: adding a second team later means rewriting every read and write.
2. **Keyed by player** (`storage.players[player_index]`) — matches the GUI, but research and
   entities belong to forces; two players of the same team would hold separate wallets, and
   entities built by robots have no player.
3. **Keyed by force** (`storage.forces[force.index]`) — matches how Factorio owns research and
   entities; one team shares one economy; several teams get several economies with no change.

## Decision

All economy state — balance, reputation, orders, contracts, owned capacity, history — is stored
under `storage.forces[force.index]`. No economy value is ever held in a single global variable
or keyed by player. Player-scoped data is limited to per-player presentation state (open GUI,
selected tab), kept apart from economy state.

## Consequences

- Positive: multiplayer with several teams needs no data migration; entity events resolve the
  owner through `entity.force`.
- Negative / trade-offs accepted: every API takes a force; force creation and merging
  (`on_force_created`, `on_forces_merging`) must be handled.
- Follow-up: decide how forces share a market (one shared order book or one per force) when
  multiplayer is designed.
