-- Loans (#96, ADR-0020). Pure Lua: the terms of a loan and the bounds on borrowing. A loan is a
-- contract (core/contracts.lua) whose `advance`, the principal, is paid to the force at acceptance and
-- whose charge repays principal plus interest in equal installments over the term. The interest rate
-- falls as reputation rises; a cap on the debt, scaled like the contracts a force is offered, bounds
-- borrowing. A loan that defaults leaves what was not repaid owed as the force's `arrears`, taken from
-- its balance as it comes in; no loan is granted while arrears are owed.
local contracts = require("scripts.core.contracts")
local reputation = require("scripts.core.reputation")

local loans = {}

-- Principals a force may borrow, in credits.
loans.TIERS = { 5000, 20000, 100000 }
-- Term of a loan and period of its installments: 12 installments over an hour.
loans.TERM_TICKS = 3600 * 60
loans.PERIOD_TICKS = 3600 * 5
-- Interest over the term at reputation 0, and its change per point: 5 % at 20, 15 % at -20.
loans.BASE_RATE = 0.1
loans.RATE_STEP = 0.0025
-- Debt cap at reputation 0, scaled by the reputation's contract scale (×0.5 to ×3).
loans.DEBT_CAP = 50000
-- The counterparty every loan names.
loans.LENDER = "lender"

--- Installments over a loan's term.
function loans.periods()
  return loans.TERM_TICKS / loans.PERIOD_TICKS
end

--- Interest over the term, as a share of the principal, for a reputation `score`.
function loans.rate(score)
  return loans.BASE_RATE - loans.RATE_STEP * reputation.add(score, 0)
end

--- The most a force with reputation `score` may owe: principal still to repay plus arrears.
function loans.cap(score)
  return loans.DEBT_CAP * reputation.contract_scale(score)
end

--- The contract spec of a loan of `principal` credits for a force with reputation `score`.
function loans.spec(principal, score)
  return {
    kind = "loan", counterparty = loans.LENDER, provides = {}, requires = {},
    reward = 0, deposit = 0, penalty = 0, advance = principal,
    charge = principal * (1 + loans.rate(score)) / loans.periods(),
    duration_ticks = loans.TERM_TICKS, accept_ticks = 60, installment_ticks = loans.PERIOD_TICKS,
  }
end

--- A force's debt: the principal its active loans in `open` ({[id] = contract}) still have to repay,
--- in proportion to their installments left, plus its `arrears`.
function loans.outstanding(open, arrears)
  local debt = arrears
  for _, contract in pairs(open) do
    if contract.advance and contract.state == contracts.ACTIVE then
      debt = debt + contract.advance * contracts.periods_left(contract) / loans.periods()
    end
  end
  return debt
end

--- Why a force with reputation `score`, open contracts `open` and `arrears` may not borrow
--- `principal` (in-arrears, debt-cap), or nil when it may.
function loans.refusal(principal, score, open, arrears)
  if arrears > 0 then return "in-arrears" end
  if loans.outstanding(open, arrears) + principal > loans.cap(score) then return "debt-cap" end
  return nil
end

--- What a balance of `balance` pays now of `arrears`.
function loans.collect(arrears, balance)
  return math.min(arrears, math.max(0, balance))
end

--- Gives a force state its arrears if it lacks them (saves made before loans had none).
function loans.init(state)
  state.arrears = state.arrears or 0
end

--- Adds a merged force's arrears to the destination's.
function loans.merge(destination, source)
  loans.init(destination)
  loans.init(source)
  destination.arrears = destination.arrears + source.arrears
end

return loans
