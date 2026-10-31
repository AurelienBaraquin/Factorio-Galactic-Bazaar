# The Galactic Bazaar window

One window with tabs gathers what the player needs to read and act on the economy (#105,
[ADR-0023](adr/0023-central-window.md)). Code: `scripts/bazaar_gui.lua` (window, tab registry,
hub binding, button, inputs, refresh), `scripts/overview_gui.lua` (Overview tab) with its figures
computed by `scripts/core/overview.lua` (pure), and the tabs described with their features: Market
([terminal.md](terminal.md#market-tab), `scripts/market_gui.lua`), Contracts
([contracts.md](contracts.md), `scripts/contracts_gui.lua`), Planets
([planets.md](planets.md#planets-tab), `scripts/planets_gui.lua`). The player-facing description is
in [player-guide.md](player-guide.md#the-galactic-bazaar-window).

## Opening and closing

| Way | Behaviour |
|---|---|
| Hotkey | `custom-input` `gb-toggle-bazaar`, Ctrl + Shift + G by default (`prototypes/inputs.lua`, named in the game's control settings): opens the window on the Overview, or closes it; before the force has researched `gb-galactic-bazaar` it prints which research is needed |
| Button | a sprite button with the hub's icon, `gb_bazaar_button`, in the top-left mod button flow (`mod-gui`), shown to every player of a force that has researched `gb-galactic-bazaar` and removed when that research is reversed (only this button: the shared flow is left to `mod-gui`); clicking it does what the hotkey does. Kept in step on init and configuration change, `on_player_created`, `on_player_changed_force`, the research events and the force resets, and every interest tick (one minute) as a self-heal, since some research changes raise no per-technology event |
| Hub | clicking a hub of the player's force within reach (`gb-open-hub`, linked to the game's "open GUI" control) opens the window on the Market tab bound to that hub, or binds it and shows that tab if the window is open; in remote view it opens the Market tab without a hub |
| Closing | the close button, E or Esc (the window is the player's opened GUI, `on_gui_closed`, which the game also raises when the player enters or leaves remote view), the hotkey or the button, the player leaving, changing force or being removed, and every configuration change (windows are rebuilt on the next opening) |

## Hub and trading

Every tab can be read anywhere, remote view included. Actions that trade or commit the force —
buy, sell, accept, decline or abandon a contract, borrow, repay, lease, book — go through the
window's hub (`bazaar_gui.hub(player, window)`): the bound hub while it is the player's force's and
within reach, otherwise the nearest hub of the force within reach of the player's body
(`physical_surface`, `physical_position`, radius `min(reach_distance, MAX_HUB_SEARCH)`, 64 tiles;
ties to the lowest unit number), which the window then binds; nil when there is none and always
in remote view (`controller_type` `remote`), and the action is refused with `gb-bazaar.no-hub` or
`gb-bazaar.remote-view` (`bazaar_gui.no_hub_message`). The lookup runs on every refresh and before
every action; a destroyed hub is unbound at once (`on_hub_removed`); a tab's refresh reads the hub
the window just resolved (`bazaar_gui.bound_hub`) instead of searching again. Each tab keeps its
own checks (power, import chest, funds…). A purchase from the Market tab is also refused
(`tier-changed`, and the preview refreshed) unless the preview shown was computed for that same
hub and the tier it named still ships the order, so the player has always seen the fee. When no
tier could take the order (a full queue, an item without stack size), the preview shows that reason
instead of a fee, and the order is sent expecting no tier (`"none"`): it is refused with the real
reason, or as `tier-changed` if a tier opened up since.

## Tabs

| Tab | Order | Available | Content |
|---|---|---|---|
| Overview | 10 | always | the figures below, one line each, with a tooltip explaining it |
| Market | 20 | always | prices, search, buy and sell ([terminal.md](terminal.md#market-tab)) |
| Contracts | 30 | always | offers, active contracts, the credit line ([contracts.md](contracts.md)) |
| Planets | 40 | `gb-planetary-concessions` researched (disabled before, tooltip naming the research; shown again as the Overview if the research is reversed) | planets, slots, leases and bookings ([planets.md](planets.md#planets-tab)) |

### Overview figures

`overview.figures(state, tick)` reads one force's state and returns, without changing it:

| Section | Figures |
|---|---|
| Account | balance; overdraft used (`max(0, -balance)`), its limit and what is left (`account.overdraft_left`); the interest rate and period; the next charge, `account.interest_due` (what a charge would take now: the rate on the lowest balance since the last charge, counted up to the limit, 0 under the minimum) and the ticks until it (charges run every `INTEREST_TICKS` from tick 0) |
| Reputation | the score (−20 to 20), the freight fee factor, the contract size factor, the loan rate over the term and the loan debt cap ([contracts.md](contracts.md)) |
| Solvency | `solvent`, `insolvent` (grace left before bankruptcy, the balance to keep, and while it is kept the time left before recovery) or `banned` (credit refused after a bankruptcy: time left, bankruptcy debt); the bankruptcies so far |
| Commitments | open contracts counted by kind and state, shown as offers waiting, active contracts (incoming, rental), active leases (concession, outsourcing) and loans with the principal left and arrears; the nearest deadline of an active contract and its kind |

## Adding a tab or a panel

A tab is a module that requires `scripts/bazaar_gui.lua` and, at file scope, calls:

```lua
bazaar_gui.register_tab({
  name = "statement",          -- unique; caption from the locale key gb-bazaar.tab-statement
  order = 50,                  -- unique position among the tabs, lowest first
  build = function(player, container, view, window) --[[ fill container, set view.elements ]] end,
  refresh = function(player, view, window) --[[ update view.elements in place ]] end,
  actions = { ["statement-page"] = function(player, view, tags, window, element, event) end },  -- optional
  available = function(player) return true end,                                -- optional
  locked_tooltip = function(player) return { "..." } end,                     -- optional
})
```

`control.lua` requires the module (that is what registers it). `view` is the tab's own table in
`storage.bazaar_gui[i].views[name]`, created empty when the tab is first shown; anything the tab
keeps there must be serialisable or a GUI element. Names and orders are unique across tabs
(registration asserts it). Elements that trigger an action carry the tag `gb_action` with a name
registered by exactly one tab; every GUI input event (`bazaar_gui.GUI_EVENTS`: click, text changed,
confirmed, element chosen, checkbox, selection, slider; `control.lua` routes them all to
`bazaar_gui.on_gui_input`) of such an element runs it, with the element that raised it and the
event, while the window is open and that tab is built; an action that should follow only one kind
of event checks `event.name` (a click in a text field also raises `on_gui_click`: the Market tab's
search and quantity act only on `on_gui_text_changed` and `on_gui_confirmed`). An action that trades or commits the force calls `bazaar_gui.hub(player, window)` and refuses
with `bazaar_gui.no_hub_message(player)` without a hub. `bazaar_gui.open(player, name, hub)` opens the window on a tab (and binds a
hub within reach), `bazaar_gui.view(player_index, name)` returns a built tab's view and
`bazaar_gui.refresh(player)` refreshes the shown tab now. A panel of an existing tab (the item
detail of #110) is built and refreshed by that tab and keeps its state in that tab's view.

## Refresh and budget

Only the shown tab of each open window of a connected player is refreshed, once a second: windows
are spread over `SLOTS` (10) slots of `SLOT_TICKS` (6) ticks by player index, so a tick refreshes
at most the windows of the players whose index falls in its slot. Before the tab, the refresh
re-binds the hub if needed and enables or disables the tabs (written only when that changes).
Measured on 2.1.24 by `tests/bazaar_gui.lua` (average of 10 refreshes of one window; ranges over
several runs, vanilla with 208 items and Space Age with 296, alone and within the full test run,
where the Market tab is slowest): Overview 0.08 to 0.19 ms, Market 0.32 to 0.66 ms, Contracts 0.10
to 0.21 ms, Planets 0.09 to 0.25 ms; the Overview of a window with no hub in reach, searching the whole 64-tile radius on each
refresh (reach raised above the cap), 0.10 to 0.14 ms, so the search adds about 0.02 to 0.05 ms
(one run showed a single 1 ms outlier, a garbage collection, which the budget does not cover).
Budget: 0.7 ms per window refresh, that is 0.7 ms per slot tick for each player
whose index falls in that slot, nothing on other ticks and nothing for closed windows.

## State

`storage.bazaar_gui[player_index]` ([data-model.md](data-model.md#storagebazaar_gui)), created by
`on_init` and `on_configuration_changed`; a save from 0.1.30 or older has none until its
configuration change, and the events that can run before it (refresh tick, hub removal, GUI input,
hotkey, button, hub click) create it themselves (never `on_load`). Until then, an input on an
element of one of the separate windows of such a save (`gb_market`, `gb_contracts`, `gb_planets`),
or the game closing one, destroys that window; so does an input on a `gb_bazaar` window that is not
the one the player's state holds. The layout has only been checked by tests, not by eye.
