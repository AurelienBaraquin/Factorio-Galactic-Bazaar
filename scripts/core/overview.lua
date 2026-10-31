-- The figures of the central window's Overview tab (#105, ADR-0023). Pure Lua: reads a force's state
-- from storage.forces and computes, at a tick, what the player needs to understand its position: the
-- account and its overdraft, the next interest charge, the reputation and its effects, the solvency
-- and the open commitments. It changes nothing.
local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")
local insolvency = require("scripts.core.insolvency")
local loans = require("scripts.core.loans")
local reputation = require("scripts.core.reputation")

local overview = {}

-- The solvency of a force at `tick`: `name` "insolvent" (with the grace left, the balance to keep to
-- recover and, while it keeps it, the time left before it recovers), "banned" (credit refused after a
-- bankruptcy) or "solvent"; `ban_left` while credit is refused, the bankruptcy debt and bankruptcies.
local function solvency(state, tick)
  local result = { name = "solvent", debt = state.bankruptcy_debt or 0, bankruptcies = state.bankruptcies or 0 }
  result.ban_left = insolvency.ban_left(state, tick)
  if result.ban_left then result.name = "banned" end
  result.grace_left = insolvency.grace_left(state, tick)
  if result.grace_left then
    result.name = "insolvent"
    result.recovery_balance = insolvency.recovery_balance(state)
    if state.recovering_since then
      result.recovering_left = math.max(0, state.recovering_since + insolvency.RECOVERY_TICKS - tick)
    end
  end
  return result
end

-- Open contracts counted by kind ({[kind] = {offered, active}}), and the nearest deadline of an
-- active one ({ticks, kind}, nil without any).
local function commitments(open, tick)
  local counts, next_due = {}, nil
  for _, contract in pairs(open) do
    local count = counts[contract.kind] or { offered = 0, active = 0 }
    counts[contract.kind] = count
    if contract.state == contracts.OFFERED then
      count.offered = count.offered + 1
    elseif contract.state == contracts.ACTIVE then
      count.active = count.active + 1
      local ticks = contract.due_tick - tick
      if not next_due or ticks < next_due.ticks or (ticks == next_due.ticks and contract.kind < next_due.kind) then
        next_due = { ticks = ticks, kind = contract.kind }
      end
    end
  end
  return counts, next_due
end

--- The Overview figures of a force's `state` at `tick`. The interest charge runs every
--- account.INTEREST_TICKS from tick 0, so `interest_in` is the ticks until the next one and
--- `interest_due` what it would take if it ran now.
function overview.figures(state, tick)
  local score = state.reputation or 0
  local open = state.contracts and state.contracts.open or {}
  local arrears = state.arrears or 0
  local figures = {
    balance = state.balance,
    overdraft_limit = account.overdraft_limit(state),
    overdraft_used = math.max(0, -state.balance),
    overdraft_left = account.overdraft_left(state),
    interest_rate = account.INTEREST_RATE,
    interest_ticks = account.INTEREST_TICKS,
    interest_due = account.interest_due(state),
    interest_in = account.INTEREST_TICKS - tick % account.INTEREST_TICKS,
    reputation = score,
    fee_factor = reputation.fee_factor(score),
    contract_scale = reputation.contract_scale(score),
    loan_rate = loans.rate(score),
    loan_cap = loans.cap(score),
    loan_debt = loans.outstanding(open, arrears),
    arrears = arrears,
    solvency = solvency(state, tick),
  }
  figures.commitments, figures.next_due = commitments(open, tick)
  return figures
end

return overview
