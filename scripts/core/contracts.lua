-- The contract engine (ADR-0015). Pure Lua: contracts are plain tables, and every function returns
-- what changed instead of touching an account, so the adapter applies money and reputation.
--
-- One model for every exchange: a counterparty `provides` goods to the force, the force `requires`
-- goods back to it, before a deadline. On acceptance the force puts up a guarantee — the `deposit`
-- plus the `penalty` — so a failure always costs what it says. When every required unit is
-- delivered in time it gets the guarantee back with the `reward`; when the deadline passes first it
-- loses the guarantee. An offer not accepted by `accept_by` expires; one can be declined. A contract
-- with `installment_ticks` pays its reward in installments while active: every period, the share of
-- the reward its deliveries earned so far (ADR-0017); the rest comes on fulfilment, and installments
-- already paid stay paid when it fails. A contract with a `charge` is a service the force pays for
-- (ADR-0019): it requires no goods, the force pays the charge every installment period, and it is
-- fulfilled when its term ends with every charge paid; a charge the force cannot pay, or an abandon,
-- defaults it (failed). A contract with an `advance` is a loan (ADR-0020): the advance is paid to the
-- force at acceptance and its charge repays it, with interest, with no service; a default leaves the
-- installments not paid owed as arrears, and the force repays a loan (`repay`) instead of abandoning it.
local reputation = require("scripts.core.reputation")

local contracts = {}

contracts.OFFERED, contracts.ACTIVE = "offered", "active"
contracts.FULFILLED, contracts.FAILED = "fulfilled", "failed"
contracts.EXPIRED, contracts.DECLINED = "expired", "declined"
contracts.VOIDED = "voided"

-- Largest credits a contract may name, so that every sum stays finite.
contracts.MAX_CREDITS = 1e12
-- Below this, a required amount still owed counts as delivered (fluid amounts are fractional).
contracts.EPSILON = 1e-6

local KINDS = { item = true, fluid = true }

--- The key of goods in `delivered`: "kind/name", with "@quality" for an item quality other than
--- normal (as market keys).
local function key_of(goods)
  local key = goods.kind .. "/" .. goods.name
  if goods.quality and goods.quality ~= "normal" then key = key .. "@" .. goods.quality end
  return key
end

local function finite_positive(n)
  return type(n) == "number" and n == n and n > 0 and n < math.huge
end

local function check_credits(n)
  return type(n) == "number" and n == n and n >= 0 and n <= contracts.MAX_CREDITS
end

-- A copy of a goods list, or nil and a reason; with `distinct`, a key may appear only once.
local function copy_goods(list, distinct)
  if type(list) ~= "table" then return nil, "goods must be a list" end
  local copy, seen = {}, {}
  for _, goods in ipairs(list) do
    if not KINDS[goods.kind] or type(goods.name) ~= "string" then return nil, "goods need a kind and a name" end
    if not finite_positive(goods.count) then return nil, "goods need a positive finite count" end
    local key = key_of(goods)
    if distinct and seen[key] then return nil, "goods are listed twice: " .. key end
    seen[key] = true
    copy[#copy + 1] = { kind = goods.kind, name = goods.name, quality = goods.quality, count = goods.count }
  end
  return copy
end

--- A new offer from `spec` = {kind, counterparty, provides, requires, reward, deposit, penalty,
--- duration_ticks, accept_ticks, installment_ticks (optional), charge (optional, needs
--- installment_ticks), advance (optional, needs a charge)}, offered at `tick`; nil and a reason when
--- the spec is invalid. The goods lists are copied.
function contracts.new(spec, tick)
  local provides, reason = copy_goods(spec.provides or {}, false)
  if not provides then return nil, reason end
  local requires
  requires, reason = copy_goods(spec.requires, true)
  if not requires then return nil, reason end
  if spec.charge ~= nil then
    if not (check_credits(spec.charge) and spec.charge > 0) then
      return nil, "charge must be positive, at most " .. contracts.MAX_CREDITS
    end
    if spec.installment_ticks == nil then return nil, "a charge needs installments" end
  elseif #requires == 0 then
    return nil, "a contract requires goods"
  end
  if spec.advance ~= nil then
    if not (check_credits(spec.advance) and spec.advance > 0) then
      return nil, "advance must be positive, at most " .. contracts.MAX_CREDITS
    end
    if spec.charge == nil then return nil, "an advance needs a charge to repay it" end
  end
  for _, field in ipairs({ "reward", "deposit", "penalty" }) do
    if not check_credits(spec[field]) then return nil, field .. " must be from 0 to " .. contracts.MAX_CREDITS end
  end
  if not finite_positive(spec.duration_ticks) then return nil, "duration must be positive and finite" end
  if not finite_positive(spec.accept_ticks) then return nil, "the offer must stand a positive, finite time" end
  if spec.installment_ticks ~= nil and not finite_positive(spec.installment_ticks) then
    return nil, "installments must come at a positive, finite period"
  end
  local delivered = {}
  for _, goods in ipairs(requires) do delivered[key_of(goods)] = 0 end
  return {
    kind = spec.kind, counterparty = spec.counterparty, provides = provides, requires = requires,
    reward = spec.reward, deposit = spec.deposit, penalty = spec.penalty,
    duration_ticks = spec.duration_ticks, offered_tick = tick, accept_by = tick + spec.accept_ticks,
    state = contracts.OFFERED, delivered = delivered,
    installment_ticks = spec.installment_ticks, paid = 0, charge = spec.charge, advance = spec.advance,
  }
end

--- The guarantee a force puts up to accept a contract: its deposit plus its penalty.
function contracts.guarantee(contract)
  return contract.deposit + contract.penalty
end

--- Accepts an offer at `tick`: it becomes active with its deadline. Returns the guarantee to hold,
--- or nil and a reason (not an offer, expired).
function contracts.accept(contract, tick)
  if contract.state ~= contracts.OFFERED then return nil, "not-offered" end
  if tick > contract.accept_by then return nil, "expired" end
  contract.state = contracts.ACTIVE
  contract.accepted_tick = tick
  contract.due_tick = tick + contract.duration_ticks
  if contract.installment_ticks then contract.next_installment = tick + contract.installment_ticks end
  return contracts.guarantee(contract)
end

--- Declines an offer: it is closed as declined. Returns true, or false when it is not an offer.
function contracts.decline(contract, tick)
  if contract.state ~= contracts.OFFERED then return false end
  contract.state, contract.settled_tick = contracts.DECLINED, tick
  return true
end

--- Units of each required key still to deliver: {[key] = units}.
function contracts.remaining(contract)
  local left = {}
  for _, goods in ipairs(contract.requires) do
    local key = key_of(goods)
    local owed = goods.count - contract.delivered[key]
    left[key] = owed > contracts.EPSILON and owed or 0
  end
  return left
end

--- Records `count` units of `key` delivered at `tick` to an active contract; returns how many it
--- took (at most what is still owed, none after the deadline).
function contracts.deliver(contract, key, count, tick)
  if contract.state ~= contracts.ACTIVE or tick > contract.due_tick then return 0 end
  local owed = contracts.remaining(contract)[key]
  if not owed then return 0 end
  local taken = math.max(0, math.min(count, owed))
  contract.delivered[key] = contract.delivered[key] + taken
  if taken > 0 and contracts.complete(contract) then contract.completed_tick = contract.completed_tick or tick end
  return taken
end

--- Whether every required unit was delivered.
function contracts.complete(contract)
  for _, owed in pairs(contracts.remaining(contract)) do
    if owed > 0 then return false end
  end
  return true
end

--- Settles a contract at `tick` if its time has come. Returns nil when nothing happens, otherwise an
--- outcome {state, credits, reputation}: `credits` to give back to the force (reward plus guarantee
--- when fulfilled, nothing otherwise: a failed contract's guarantee is kept) and a reputation change
--- (+1, -1, 0). The contract's state is updated.
function contracts.settle(contract, tick)
  if contract.state == contracts.OFFERED and tick > contract.accept_by then
    contract.state, contract.settled_tick = contracts.EXPIRED, tick
    return { state = contracts.EXPIRED, credits = 0, reputation = 0 }
  end
  if contract.state ~= contracts.ACTIVE then return nil end
  if contract.charge then
    -- Fulfilled once its term ended and its last period (scheduled up to the deadline) was charged.
    if tick <= contract.due_tick or contract.next_installment <= contract.due_tick then return nil end
    contract.state, contract.settled_tick = contracts.FULFILLED, tick
    return { state = contracts.FULFILLED, credits = contracts.guarantee(contract), reputation = 0 }
  end
  if contracts.complete(contract) then
    contract.state, contract.settled_tick = contracts.FULFILLED, tick
    return {
      state = contracts.FULFILLED, credits = contract.reward - (contract.paid or 0) + contracts.guarantee(contract),
      reputation = 1,
    }
  end
  if tick > contract.due_tick then
    contract.state, contract.settled_tick = contracts.FAILED, tick
    return { state = contracts.FAILED, credits = 0, reputation = -1 }
  end
  return nil
end

-- Share of a contract's required units delivered, from 0 to 1.
local function delivered_share(contract)
  local owed, delivered = 0, 0
  for _, goods in ipairs(contract.requires) do
    owed = owed + goods.count
    delivered = delivered + math.min(goods.count, contract.delivered[key_of(goods)])
  end
  return delivered / owed
end

--- Pays an active contract's installment at `tick` if one is due: the share of the reward its
--- deliveries earned, less what was already paid; for a contract with a charge, the charge the
--- force owes, as negative credits (none after its term). Returns the credits to give the force, or
--- nil.
function contracts.installment(contract, tick)
  if contract.state ~= contracts.ACTIVE or not contract.next_installment or tick < contract.next_installment then
    return nil
  end
  if contract.charge then
    -- Periods follow their schedule, not the tick they are settled at, so that every period up to
    -- the deadline is charged however late settlement runs.
    local scheduled = contract.next_installment
    if scheduled > contract.due_tick then return nil end
    contract.next_installment = scheduled + contract.installment_ticks
    return -contract.charge
  end
  contract.next_installment = tick + contract.installment_ticks
  local earned = contract.reward * delivered_share(contract) - contract.paid
  if earned <= 0 then return nil end
  contract.paid = contract.paid + earned
  return earned
end

--- What an active contract with a charge still has to take: its periods scheduled from its next
--- installment up to its deadline, times the charge; 0 for any other contract.
function contracts.payoff(contract)
  if contract.state ~= contracts.ACTIVE or not contract.charge or contract.next_installment > contract.due_tick then
    return 0
  end
  local left = math.floor((contract.due_tick - contract.next_installment) / contract.installment_ticks) + 1
  return left * contract.charge
end

--- Defaults an active contract at `tick` (a charge of `unpaid` credits the force could not pay): it
--- fails at once, the guarantee kept. A loan's outcome also carries the `arrears` the force still
--- owes: the unpaid charge and every one left. Returns the outcome, or nil when it is not active.
function contracts.default(contract, tick, unpaid)
  if contract.state ~= contracts.ACTIVE then return nil end
  local arrears = contract.advance and (unpaid or 0) + contracts.payoff(contract) or nil
  contract.state, contract.settled_tick = contracts.FAILED, tick
  return { state = contracts.FAILED, credits = 0, reputation = -1, arrears = arrears }
end

--- Repays an active loan at `tick`: it is fulfilled at once, the force paying every charge left
--- (`payoff`, as negative credits, plus its guarantee back), without reputation. Returns the outcome,
--- or nil when it is not an active loan. The adapter checks the force can pay first.
function contracts.repay(contract, tick)
  if contract.state ~= contracts.ACTIVE or not contract.advance then return nil end
  local owed = contracts.payoff(contract)
  contract.state, contract.settled_tick = contracts.FULFILLED, tick
  return { state = contracts.FULFILLED, credits = contracts.guarantee(contract) - owed, reputation = 0 }
end

--- Abandons an active contract at `tick`: it is settled at once, failed unless every required unit
--- was already delivered (then it is fulfilled); a contract with a charge defaults. A loan cannot be
--- abandoned (nil): it is repaid.
function contracts.abandon(contract, tick)
  if contract.state ~= contracts.ACTIVE or contract.advance then return nil end
  if contract.charge then return contracts.default(contract, tick) end
  contract.due_tick = math.min(contract.due_tick, tick - 1)
  return contracts.settle(contract, tick)
end

--- Voids an active contract at `tick` that can no longer be fulfilled through no fault of the force
--- (its goods no longer exist): the outcome gives the whole guarantee back, without reputation.
--- Returns nil when it is not active.
function contracts.void(contract, tick)
  if contract.state ~= contracts.ACTIVE then return nil end
  contract.state, contract.settled_tick = contracts.VOIDED, tick
  return { state = contracts.VOIDED, credits = contracts.guarantee(contract), reputation = 0 }
end

contracts.key = key_of

-- Settled contracts a force keeps for its interface.
contracts.HISTORY_SIZE = 20

--- Gives a force state its contract book if it lacks one: {open = {[id] = contract}, history =
--- {contract...}}, and its reputation score, brought within its bounds (saves before 0.1.17 had
--- none).
function contracts.init_book(state)
  state.contracts = state.contracts or { open = {}, history = {} }
  state.reputation = reputation.add(state.reputation or 0, 0)
end

--- Files a contract in a force's book under `id`, unique across all forces (the adapter's counter),
--- so that references to it survive a force merge.
function contracts.file(state, contract, id)
  contract.id = id
  state.contracts.open[id] = contract
  return id
end

--- Moves a settled contract from the open contracts to the history, which keeps the newest.
function contracts.close(state, id)
  local book = state.contracts
  local contract = book.open[id]
  if not contract then return end
  book.open[id] = nil
  book.history[#book.history + 1] = contract
  while #book.history > contracts.HISTORY_SIZE do table.remove(book.history, 1) end
end

--- Folds a merged force's book into the destination's: its open contracts carry on under the same
--- ids, only a reputation debt follows it (core/reputation.lua); its history is dropped.
function contracts.merge_books(destination, source)
  contracts.init_book(destination)
  contracts.init_book(source)
  for id, contract in pairs(source.contracts.open) do destination.contracts.open[id] = contract end
  destination.reputation = reputation.merge(destination.reputation, source.reputation)
end

return contracts
