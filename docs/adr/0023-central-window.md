# ADR-0023 — One Galactic Bazaar window with registered tabs, readable anywhere, trading at a hub within reach

- **Status**: Accepted
- **Date**: 2026-10-31
- **Deciders**: Aurélien Baraquin (owner, delegated to the agent for M7)
- **Supersedes**: none

## Context

After a play-test the owner found every mechanism working but the mod far too opaque (#104,
milestone M7, brief priority 7): the account, the overdraft, interest, reputation, solvency and
the open commitments were scattered over three windows (market, contracts, planets), each opened
only by clicking a trading hub and closed as soon as the player walked away. #105 asks for one
window, opened by a hotkey and a permanent button, readable anywhere, with an Overview tab, the
three windows integrated as tabs, and a structure that the next issues of the milestone extend:
the account statement (#108), logistics (#109) and the market item detail (#110). Constraints:
trading actions stay tied to a hub of the force within reach (no remote trading, ADR-0005), every
GUI event is player input, state lives in `storage`, economy state per force (ADR-0001), and a GUI
refresh must not grow with the number of tabs.

## Options considered

1. **Window structure** — keep three windows and add a fourth for the overview (duplication, and
   the player still has to know where each figure lives); one window that rebuilds its body on each
   tab switch (simple, but destroys elements a click may still target, lesson of 2026-10-30); or
   **one window with a `tabbed-pane`**, each tab's content built once, the first time it is shown,
   and updated in place.
2. **How tabs are added** — the window module requires and knows every tab (every new tab edits
   it, and tab modules cannot reach the window without a require cycle); or **a registry**: tab
   modules require the window module and register a definition at load (name, order, build,
   refresh, actions, availability), like freight tier providers.
3. **Which hub a window trades through** — only the hub it was opened from, the window closing out
   of reach (the old behaviour: no consultation away from a hub); any hub of the force wherever it
   is (remote trading, against ADR-0005); or **the bound hub while it is within reach, else the
   nearest hub of the force within reach**, looked up again on refresh and before every action.
4. **Refresh** — every tab of every open window (cost grows with tabs); or **only the shown tab of
   each connected player's open window**, once a second, spread over slots by player index.
5. **State** — one table per window, as before (`storage.players`, `storage.contracts_gui`,
   `storage.planets_gui`); or **one table per player window**, `storage.bazaar_gui[player_index]`,
   holding the bound hub, the shown tab and each tab's own state.

## Decision

`scripts/bazaar_gui.lua` owns one screen window, `gb_bazaar`, with a `tabbed-pane`. Tabs register
with `bazaar_gui.register_tab{name, order, build, refresh, actions, available, locked_tooltip}` at
file scope when `control.lua` requires them: Overview (10, `scripts/overview_gui.lua`), Market (20),
Contracts (30), Planets (40, available once planetary concessions are researched; disabled with a
tooltip naming the research before). Action names are unique across tabs (registration asserts
it), so one dispatcher routes any click or text change of this mod's elements to the tab that owns
it. A tab's content is built the first time it is shown and only the shown tab is refreshed, once a
second per connected player, in one of `SLOTS` (10) slots of `SLOT_TICKS` (6) ticks. The
`gb-toggle-bazaar` hotkey (Ctrl + Shift + G) and a button in the mod button flow (`mod-gui`), both
once the force has researched `gb-galactic-bazaar`, open or close it; clicking a hub opens it on the
Market tab bound to that hub. The window binds the hub it was opened from, otherwise the nearest hub
of the force within reach of the player's body (physical surface and position, search radius capped
at 64 tiles), and looks again on refresh and before each action, which re-checks force and reach
as before. Owner decisions (coordinator, review of #114): every action that commits the force needs
that hub — Decline and Abandon of every contract kind included, like Accept and Repay — and nothing
trades from remote view (`controller_type` `remote`; a hub clicked there opens the Market tab
without a hub). A purchase is refused (`tier-changed`) unless its preview was computed for the same
hub with a tier. Every GUI input event of this mod's elements reaches the tab actions, with the
element; tab names and orders are unique. The handlers create `storage.bazaar_gui` when a save
from before it runs events before its configuration change, and an input on a window of such a
save destroys that window. The Overview's figures are computed by a
pure module, `scripts/core/overview.lua`, from the force's state; the interest estimate reuses
`account.interest_due`, the function the charge itself uses. State is
`storage.bazaar_gui[player_index] = {hub, tab, views, elements}`; the old tables and windows are
removed on configuration change.

## Consequences

- Positive: every figure the player needs to read their position is one hotkey away, anywhere; a
  new tab (#108 account statement, #109 logistics) is a new module that registers itself, and a
  panel of an existing tab (#110 item detail) lives in that tab's view, without touching the window;
  the refresh cost is that of the one tab shown, measured on 2.1.24 at 0.08 to 0.19 ms (Overview), 0.32 to 0.66 ms
  (Market), 0.10 to 0.21 ms (Contracts) and 0.09 to 0.25 ms (Planets) per refresh, within a budget
  of 0.7 ms per window refresh ([window.md](../window.md)).
- Negative / trade-offs accepted: a window left open no longer closes when the player walks away;
  it loses its hub instead, and trading buttons then refuse with a message rather than being
  disabled. A purchase may go to a different hub than the one shown a second earlier if the player
  moved between two hubs; the delivery tier check (`tier-changed`) still refuses a fee the player
  did not see. The layout has only been checked by tests, not by eye.
- Follow-up work: #108, #109 and #110 add their tabs or panels through the registry; the market
  tab's status line repeats a few Overview figures (balance, overdraft, solvency, reputation) that
  trading needs at hand.
