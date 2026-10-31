-- Loans (#96, ADR-0020): the runtime side of borrowing. A force borrows one of the principal tiers
-- (scripts/core/loans.lua) as a contract of kind "loan" (scripts/contracts.lua): the principal is paid
-- at acceptance, installments are charged at the contract settlement. Arrears a defaulted loan left
-- are taken from the force's balance as it comes in. State: the loan contracts in each force's book
-- and storage.forces[i].arrears.
local account = require("scripts.core.account")
local contracts = require("scripts.contracts")
local core = require("scripts.core.loans")

local loans = {}

loans.COLLECT_TICKS = 60
-- Ticks over which a force's arrears payments share one journal entry.
local COLLECT_MERGE_TICKS = 3600

--- A force's debt (principal still to repay plus arrears) and its cap.
function loans.debt(force_index)
  local state = storage.forces[force_index]
  return core.outstanding(state.contracts.open, state.arrears), core.cap(state.reputation)
end

--- The terms a force is offered for each tier: {principal, rate, charge, refusal}, `refusal` nil when
--- it may borrow it (see `borrow` for the reasons).
function loans.offers(force_index)
  local state = storage.forces[force_index]
  local full = #contracts.listed(force_index) >= contracts.MAX_LISTED
  local list = {}
  for tier, principal in ipairs(core.TIERS) do
    local spec = core.spec(principal, state.reputation)
    list[tier] = {
      principal = principal, rate = core.rate(state.reputation), charge = spec.charge,
      refusal = full and "too-many-contracts"
        or core.refusal(principal, state.reputation, state.contracts.open, state.arrears),
    }
  end
  return list
end

--- Borrows the principal of tier `tier` (an index of core.TIERS) for a force: the loan contract is
--- offered and accepted at once, its principal paid to the force, or nothing changes. Returns the
--- contract id, or nil and a reason (invalid-amount, too-many-contracts, in-arrears, debt-cap).
function loans.borrow(force_index, tier)
  local state = storage.forces[force_index]
  local principal = core.TIERS[tier]
  if not (state and principal) then return nil, "invalid-amount" end
  local offered = loans.offers(force_index)[tier]
  if offered.refusal then return nil, offered.refusal end
  local id = contracts.offer(force_index, core.spec(principal, state.reputation))
  if not id then return nil, "invalid-amount" end
  local accepted, reason
  accepted, reason = contracts.accept(force_index, id)
  if not accepted then
    contracts.decline(force_index, id)
    return nil, reason
  end
  return id
end

--- on_nth_tick(COLLECT_TICKS): each force owing arrears pays what its balance can of them.
function loans.on_collect_tick(event)
  for _, state in pairs(storage.forces) do
    local paid = core.collect(state.arrears, state.balance)
    if paid > 0 then
      account.apply(state, -paid, { tick = event.tick, kind = "loan-arrears", key = "loans",
        merge_ticks = COLLECT_MERGE_TICKS })
      state.arrears = state.arrears - paid
    end
  end
end

return loans
