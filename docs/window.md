# The Galactic Bazaar window

One window with tabs gathers what the player needs to read and act on the economy (#105,
[ADR-0023](adr/0023-central-window.md)). Code: `scripts/bazaar_gui.lua` (window, tab registry,
hub binding, button, inputs, refresh), `scripts/overview_gui.lua` (Overview tab) with its figures
computed by `scripts/core/overview.lua` (pure), `scripts/statement_gui.lua` (Statement tab) with its
classification, pages and totals in `scripts/core/statement.lua` (pure), and the tabs described with their features: Market
([terminal.md](terminal.md#market-tab), `scripts/market_gui.lua`), Logistics
([terminal.md](terminal.md#logistics-tab), `scripts/logistics_gui.lua`, rows from the pure
`scripts/core/logistics.lua`), Contracts
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
| Logistics | 25 | always | the force's hubs, and for the one selected its shipments queued and in flight and its modules with their status ([terminal.md](terminal.md#logistics-tab)) |
| Contracts | 30 | always | offers, active contracts, the credit line ([contracts.md](contracts.md)) |
| Planets | 40 | `gb-planetary-concessions` researched (disabled before, tooltip naming the research; shown again as the Overview if the research is reversed) | planets, slots, leases and bookings ([planets.md](planets.md#planets-tab)) |
| Statement | 50 | always | the force's journal and its totals per category ([below](#statement-tab)) |

### Overview figures

`overview.figures(state, tick)` reads one force's state and returns, without changing it:

| Section | Figures |
|---|---|
| Account | balance; overdraft used (`max(0, -balance)`), its limit and what is left (`account.overdraft_left`); the interest rate and period; the next charge, `account.interest_due` (what a charge would take now: the rate on the lowest balance since the last charge, counted up to the limit, 0 under the minimum) and the ticks until it (charges run every `INTEREST_TICKS` from tick 0) |
| Reputation | the score (−20 to 20), the freight fee factor, the contract size factor, the loan rate over the term and the loan debt cap ([contracts.md](contracts.md)) |
| Solvency | `solvent`, `insolvent` (grace left before bankruptcy, the balance to keep, and while it is kept the time left before recovery) or `banned` (credit refused after a bankruptcy: time left, bankruptcy debt); the bankruptcies so far |
| Commitments | open contracts counted by kind and state, shown as offers waiting, active contracts (incoming, rental), active leases (concession, outsourcing) and loans with the principal left and arrears; the nearest deadline of an active contract and its kind |

## Statement tab

Where every credit came from and went to (#108). Read only: it works anywhere.

- **Journal**: the force's journal (`storage.forces[i].journal`, [data-model.md](data-model.md)),
  newest first, `statement.PAGE_SIZE` (12) rows a page with `<` and `>` (clamped to the first and
  last page). Columns: game time of the entry (`h:mm:ss`; a merged entry shows its last part, its
  tooltip the first and last), transaction (a label per kind, its tooltip the rule behind it, with
  the current figures: freight fee rates, interest rate and period, restructuring surcharge), subject
  (the goods with their icon and quality, electricity, or the contract and its kind; the raw key when
  the goods' prototype is gone), quantity, amount (green received, red paid) and the balance after
  it (empty for entries older than the balance field). A line above it gives the number of entries,
  the oldest one's time and the journal's size.
- **Filter**: a drop-down, All or one category; changing it goes back to the first page. An entry's
  category is the one `account.apply` recorded on it (`category`), computed for older entries.
- **Totals**: one row per category plus Total: income, spending, net and transactions, over the last
  10 minutes, the last hour or since records began (a drop-down; a line gives the first tick
  covered). They come from the force's ledger (`state.ledger`), not the journal: every transaction is
  counted, merged or not, even once the journal has dropped it. Periods count by whole minutes of
  game time (the current minute and the 9 or 59 before it); "since records began" starts at the
  force's first transaction, for a save from 0.1.33 or older its first after the upgrade.

| Category | Journal kinds (label) |
|---|---|
| Sales | `sell` of goods (window, export chests and manifolds, catapults, cargo of a removed hub sold back) |
| Purchases | `buy` of goods (window, order combinators) |
| Freight | `freight` (fee of a purchase), `freight-refund` (purchase that can never land nor be sold back) |
| Power | `sell` and `buy` of `energy/…` keys (power substations), labelled `power-sell` and `power-buy` |
| Contracts | `contract-guarantee`, `contract-installment`, `contract-charge`, `contract-fulfilled`, `contract-failed`, `contract-voided`, unless the contract is a loan |
| Loans | `contract-advance`, `contract-repaid`, `loan-arrears`, and any contract entry whose `contract_kind` is `loan` |
| Interest | `overdraft-interest` |
| Bankruptcy | `bankruptcy-restructured`, `bankruptcy-debt` |
| Other | any kind this version does not know (label `other`, its tooltip naming the kind) |

Contract entries carry the contract's kind (`contract_kind`) from 0.1.34; a contract entry of an
older save has none and counts under Contracts. A kind added to `account.apply` must be given a
label, a category (`statement.LABELS`, `statement.LABEL_CATEGORY`) and its locale keys
(`gb-statement.kind-<label>` and `-tooltip`, English and French); `spec/core/statement_spec.lua`
checks every label has a category.

## Explanations

The window's figures, column headers and buttons listed here have a tooltip stating the rule behind
them, with live figures where they are cheap (#111): the Overview's lines (the fee, contract size and loan
formulas take their factors from `scripts/core/reputation.lua` and `scripts/core/loans.lua`), the
Market tab's balance, hub, delivery tier (the Logistics tab's tier tooltip), search (how words
match, `catalog.search`), page (items a page), columns and their cells
(spread and price freshness from `scripts/core/market.lua` and `scripts/core/telecom.lua`, trend
from the NPC history), quantity, Buy, Sell and preview, and the item detail's figures
([terminal.md](terminal.md#item-detail)); each Contracts row's cells by kind and state (goods
provided and required, reward or charge and guarantee, offer end or deadline, Accept, Decline,
Abandon, a loan's principal, payoff and installments), its reputation and loan debt (the cap's range
from the reputation factors); the Planets tab's columns and cells (distance and transit from
`scripts/core/transit.lua`); the Logistics tab's shipment columns, each hub's power (what stops
without it and what keeps working) and status, and each attached building's name and status (what
the colours mean and how often statuses refresh); the Statement tab's columns, categories and kinds
of transaction. Without a tooltip: section headings, the pager buttons, the item detail's
breakdown lines (each line spells out its own computation) and the status texts themselves, which
are sentences saying what the building does or waits for; the status a building shows on hover in
the world is the game's `custom_status`, which takes no tooltip, so those texts carry their own
explanation.

Tooltips that never change are set once, when the tab is built. Those that follow the force's state
are written only when what they show changed: the Market tab's reputation and delivery tooltips
(the score, and the tier with the score, kept in the view's `tooltips`), the Contracts tab's
reputation and each row's cells (the contract id and state each row's tooltips were written for, in
the view's `shown`); a loan's Repay tooltip, which gives the payoff, the Borrow buttons and the
Logistics tab's tier keep being written on each refresh as before. Every locale key a literal in the
code names must exist in English and French with no key repeated (`spec/locale_spec.lua`); a key
built at run time (`"gb-overview." .. line .. "-tooltip"`) is not checked there, so new ones are
spelled out; the spec also checks that each key uses the same parameters (`__1__`...) in both
languages. A new tab gives every figure it shows such a tooltip.

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
`bazaar_gui.refresh(player)` refreshes the shown tab now. A panel of an existing tab is built and
refreshed by that tab and keeps its state in that tab's view, like the Market tab's item detail
(`scripts/item_detail_gui.lua`, [terminal.md](terminal.md#item-detail)).

## Refresh and budget

Only the shown tab of each open window of a connected player is refreshed, once a second: windows
are spread over `SLOTS` (10) slots of `SLOT_TICKS` (6) ticks by player index, so a tick refreshes
at most the windows of the players whose index falls in its slot. Before the tab, the refresh
re-binds the hub if needed and enables or disables the tabs (written only when that changes).
Measured on 2.1.24 by `tests/bazaar_gui.lua` (average of 10 refreshes of one window; ranges over
several runs, vanilla with 208 items and Space Age with 296, alone and within the full test run,
where the Market tab is slowest): Overview 0.08 to 0.19 ms, Market 0.32 to 0.66 ms (0.45 to 0.62 ms
with a selected item and its detail, [terminal.md](terminal.md#market-tab)), Contracts 0.10
to 0.21 ms, Planets 0.09 to 0.25 ms; the Overview of a window with no hub in reach, searching the whole 64-tile radius on each
refresh (reach raised above the cap), 0.10 to 0.14 ms, so the search adds about 0.02 to 0.05 ms
(one run showed a single 1 ms outlier, a garbage collection, which the budget does not cover).
The Statement tab is measured by `tests/statement_gui.lua` in its costliest view, a full journal
(500 entries) filtered by a category and a full ledger (60 minutes of every category) over the last
hour, average of 10 refreshes: 0.20 to 0.29 ms unchanged and 0.40 to 0.62 ms when a transaction
came in before each refresh (rows shift, most cells written), vanilla and Space Age, alone and
within the full test run. Its cost grows with the
journal only when a category is filtered (one pass over the entries), and with the minutes of the
ledger the period covers; each element is written only when what it shows changed.
Budget: 0.7 ms per window refresh, that is 0.7 ms per slot tick for each player
whose index falls in that slot, nothing on other ticks and nothing for closed windows. The
Logistics tab is measured by `tests/logistics_gui.lua` with 20 hubs, a full capsule queue and about
1000 modules on the map, after a warm-up (`log` line read by hand, not asserted; ten runs of the
file alone): 0.33 to 0.49 ms per refresh, and 0.51 to 0.74 ms for a refresh that lists the selected
hub's modules again (once every 5 s while the tab is shown, or when another hub is selected). Runs
on a busier machine or within the full suite, whose heap is larger, showed averages up to 0.81 ms
and 2.4 ms for those, which the budget does not cover; the module listing is the part to watch
([terminal.md](terminal.md#logistics-tab)). `tests/explanations.lua` measures a full Contracts tab
(8 rows: offers, a lease and loans) and the Market tab beside it: 0.25 to 0.29 ms and 0.23 to 0.26
ms per refresh. The tooltips (#111) changed no refresh measurably: over five runs of the measuring
tests alone, vanilla, before and after, Overview 0.06 to 0.07 ms both, Market 0.23 to 0.28 then
0.23 to 0.29 ms, Contracts 0.08 to 0.09 ms both (0.25 to 0.29 then 0.26 to 0.29 ms with 8 rows),
Planets 0.06 to 0.07 ms both, Logistics 0.34 to 0.39 then 0.34 to 0.37 ms (one run at 0.64 ms).

## State

`storage.bazaar_gui[player_index]` ([data-model.md](data-model.md#storagebazaar_gui)), created by
`on_init` and `on_configuration_changed`; a save from 0.1.30 or older has none until its
configuration change, and the events that can run before it (refresh tick, hub removal, GUI input,
hotkey, button, hub click) create it themselves (never `on_load`). Until then, an input on an
element of one of the separate windows of such a save (`gb_market`, `gb_contracts`, `gb_planets`),
or the game closing one, destroys that window; so does an input on a `gb_bazaar` window that is not
the one the player's state holds. The layout has only been checked by tests, not by eye.
