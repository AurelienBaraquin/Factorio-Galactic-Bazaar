-- Loans (#96, ADR-0021): the runtime side of borrowing. A force borrows one of the principal tiers
-- (scripts/core/loans.lua) as a contract of kind "loan" (scripts/contracts.lua): the principal is paid
-- at acceptance, installments are charged at the contract settlement. Arrears a defaulted loan left
-- are taken from the force's available funds, overdraft included, as they allow. Borrowing needs the
-- credit research (#98); loans already taken are repaid and arrears collected without it. State: the
-- loan contracts in each force's book and storage.forces[i].arrears.
local account = require("scripts.core.account")
local contracts = require("scripts.contracts")
local core = require("scripts.core.loans")
local finance = require("scripts.finance")
local insolvency = require("scripts.core.insolvency")

local loans = {}

loans.COLLECT_TICKS = 60
-- Ticks over which a force's arrears payments share one journal entry. Arrears are read `or 0`: a
-- save made before loans has none until on_configuration_changed adds them.
local COLLECT_MERGE_TICKS = 3600

--- A force's debt (principal still to repay plus arrears) and its cap.
function loans.debt(force_index)
  local state = storage.forces[force_index]
  return core.outstanding(state.contracts.open, state.arrears or 0), core.cap(state.reputation)
end

-- Why a force may borrow nothing now, whatever the tier, or nil: it has not researched credit, the
-- contracts window is full, the force is insolvent or refused credit after a bankruptcy (ADR-0022), or
-- its balance is beyond its overdraft limit (no available funds: acceptance refuses even a zero
-- guarantee, contracts.can_accept).
local function refusal_for_all(force_index, state)
  if not finance.researched(game.forces[force_index], finance.CREDIT_TECHNOLOGY) then return "not-researched" end
  if #contracts.listed(force_index) >= contracts.MAX_LISTED then return "too-many-contracts" end
  if insolvency.insolvent(state) then return "insolvent" end
  if insolvency.credit_banned(state) then return "credit-ban" end
  if account.available(state) < 0 then return "overdrawn" end
  return nil
end

--- The terms a force is offered for each tier: {principal, rate, charge, refusal}, `refusal` nil when
--- it may borrow it (see `borrow` for the reasons).
function loans.offers(force_index)
  local state = storage.forces[force_index]
  local blocked = refusal_for_all(force_index, state)
  local list = {}
  for tier, principal in ipairs(core.TIERS) do
    local spec = core.spec(principal, state.reputation)
    list[tier] = {
      principal = principal, rate = core.rate(state.reputation), charge = spec.charge,
      refusal = blocked or core.refusal(principal, state.reputation, state.contracts.open, state.arrears or 0),
    }
  end
  return list
end

--- Borrows the principal of tier `tier` (an index of core.TIERS) for a force: the loan contract is
--- offered and accepted at once, its principal paid to the force, or nothing changes. Returns the
--- contract id, or nil and a reason (invalid-amount, not-researched, too-many-contracts, insolvent,
--- credit-ban, overdrawn, in-arrears, debt-cap; insufficient-funds should acceptance still refuse).
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

--- on_nth_tick(COLLECT_TICKS): each force owing arrears pays what its available funds can of them,
--- down to its overdraft limit: unpaid loan debt becomes overdraft debt, which pays debit interest
--- and blocks spending (ADR-0021). Arrears beyond the overdraft stay owed.
function loans.on_collect_tick(event)
  for _, state in pairs(storage.forces) do
    local paid = core.collect(state.arrears or 0, account.available(state))
    if paid > 0 then
      account.apply(state, -paid, { tick = event.tick, kind = "loan-arrears", key = "loans",
        merge_ticks = COLLECT_MERGE_TICKS })
      state.arrears = state.arrears - paid
    end
  end
end

return loans
