-- Helpers shared by the in-game tests (not a test file: control.lua does not list it).
local bazaar_gui = require("scripts.bazaar_gui")

local test_helpers = {}

--- Picks tab `name` of the player's open Galactic Bazaar window, as a click on the tab would.
function test_helpers.select_tab(player, name)
  local pane = player.gui.screen[bazaar_gui.WINDOW].gb_bazaar_tabs
  for index, entry in ipairs(pane.tabs) do
    if entry.tab.tags.gb_tab == name then pane.selected_tab_index = index end
  end
  bazaar_gui.on_gui_selected_tab_changed({ element = pane, player_index = player.index })
end

--- Sets a force state's balance as a test needs it, with the marks the periodic handlers read from
--- it: the interest's and the insolvency check's lowest balances (`overdraft_low`, `solvency_low`)
--- start from it, and any insolvency or recovery in progress is dropped. Assigning the balance alone
--- would let those handlers act, between tests, on the balance a test left behind.
function test_helpers.set_balance(state, balance)
  state.balance = balance
  state.overdraft_low, state.solvency_low = balance, balance
  state.insolvent_since, state.recovering_since = nil, nil
end

return test_helpers
