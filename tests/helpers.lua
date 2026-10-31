-- Helpers shared by the in-game tests (not a test file: control.lua does not list it).
local test_helpers = {}

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
