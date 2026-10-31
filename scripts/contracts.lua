-- Contracts of each force (ADR-0015): the runtime side of the contract engine. Contracts live in
-- each force's book (storage.forces[i].contracts) under ids unique across all forces
-- (storage.contract_next_id), so references survive a force merge; money moves through the force's
-- account, the reputation score is the force's (storage.forces[i].reputation). Every SETTLE_TICKS,
-- open contracts whose time has come are settled. Goods are moved by the features that offer
-- contracts. A loan (ADR-0021) pays its advance at acceptance, is repaid by its charge with no
-- service, leaves its unpaid installments as the force's arrears when it defaults, and is repaid in
-- full instead of abandoned.
local account = require("scripts.core.account")
local core = require("scripts.core.contracts")
local insolvency = require("scripts.core.insolvency")
local notifications = require("scripts.notifications")
local reputation = require("scripts.core.reputation")

local contracts = {}

contracts.SETTLE_TICKS = 60
-- Kinds of contracts offered to the force by counterparties, shown in the Contracts tab, and how
-- many of them may be open at once (the window's rows).
contracts.LISTED_KINDS = { incoming = true, rental = true, concession = true, outsourcing = true, loan = true }
contracts.MAX_LISTED = 8

-- The state of a force that has a contract book, or nil.
local function state_of(force_index)
  local state = storage.forces[force_index]
  return state and state.contracts and state or nil
end

-- Records a contract's money movement in the force's account; a refusal would mean a bug in the
-- engine's bounds, so it is logged rather than ignored.
local function move(state, amount, kind, id)
  local ok, reason = account.apply(state, amount, { tick = game.tick, kind = kind, key = "contract/" .. id })
  if not ok then
    log("[galactic-bazaar] contract " .. id .. ": " .. kind .. " of " .. amount .. " refused: " .. reason)
  end
  return ok
end

--- Files an offer for a force from `spec` (see scripts/core/contracts.lua); returns its id, or nil
--- and a reason.
function contracts.offer(force_index, spec)
  local state = state_of(force_index)
  if not state then return nil, "no-force" end
  local contract, reason = core.new(spec, game.tick)
  if not contract then return nil, reason end
  local id = storage.contract_next_id or 1
  storage.contract_next_id = id + 1
  return core.file(state, contract, id)
end

--- The open contract `id` of a force, or nil.
function contracts.get(force_index, id)
  local state = state_of(force_index)
  return state and state.contracts.open[id]
end

--- Whether a force could accept an offer now, with a guarantee of `guarantee` (the contract's own
--- by default). Returns true, or false and a reason (unknown, not-offered, expired, insolvent: no
--- contract is taken while the force is insolvent, ADR-0022; insufficient-funds).
function contracts.can_accept(force_index, id, guarantee)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  if not contract then return false, "unknown" end
  if contract.state ~= core.OFFERED then return false, "not-offered" end
  if game.tick > contract.accept_by then return false, "expired" end
  if insolvency.insolvent(state) then return false, "insolvent" end
  if account.available(state) < (guarantee or core.guarantee(contract)) then return false, "insufficient-funds" end
  return true
end

--- A force's open contracts of the listed kinds, offers and active ones, by id.
function contracts.listed(force_index)
  local state = state_of(force_index)
  local list = {}
  for _, contract in pairs(state and state.contracts.open or {}) do
    if contracts.LISTED_KINDS[contract.kind] then list[#list + 1] = contract end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--- Accepts an offer: the force puts up the guarantee (deposit plus penalty) and is paid a loan's
--- advance, or nothing changes. Returns true, or false and a reason (see `can_accept`).
function contracts.accept(force_index, id)
  local ok, reason = contracts.can_accept(force_index, id)
  if not ok then return false, reason end
  local state, contract = storage.forces[force_index], contracts.get(force_index, id)
  local guarantee = core.accept(contract, game.tick)
  if guarantee > 0 then move(state, -guarantee, "contract-guarantee", id) end
  if contract.advance then move(state, contract.advance, "contract-advance", id) end
  return true
end

--- Declines an offer: it is filed away. Returns true, or false when it is not an open offer.
function contracts.decline(force_index, id)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  if not (contract and core.decline(contract, game.tick)) then return false end
  core.close(state, id)
  return true
end

--- Records `count` units of `key` ("item/<name>", "fluid/<name>") handed over for an active
--- contract now; returns how many it took (none after its deadline).
function contracts.deliver(force_index, id, key, count)
  local contract = contracts.get(force_index, id)
  return contract and core.deliver(contract, key, count, game.tick) or 0
end

-- Applies an outcome to the force: what it gets back through its account (a failure is journaled
-- too, with nothing back: the guarantee is kept), its reputation and a defaulted loan's arrears; then
-- files the contract away.
local function apply(state, id, outcome)
  if outcome.state ~= core.EXPIRED then move(state, outcome.credits, "contract-" .. outcome.state, id) end
  state.reputation = reputation.add(state.reputation, outcome.reputation)
  if outcome.arrears then state.arrears = (state.arrears or 0) + outcome.arrears end
  core.close(state, id)
end

-- Repays an active loan: every installment left is taken first (`contract-repaid`), and the loan is
-- settled only once that debit went through. Returns the outcome, or nil and maybe a reason.
local function repay(state, id, contract)
  if contract.state ~= core.ACTIVE then return nil end
  local owed = core.payoff(contract)
  if owed > 0 then
    local ok, reason = account.apply(state, -owed,
      { tick = game.tick, kind = "contract-repaid", key = "contract/" .. id })
    if not ok then return nil, reason end
  end
  local outcome = core.repay(contract, game.tick)
  apply(state, id, outcome)
  return outcome
end

--- Abandons an active contract: it is settled at once (failed unless already complete). A loan is
--- repaid instead: the force pays every installment left at once, or nothing changes when its
--- available funds (overdraft included) cannot. Returns the outcome, or nil and maybe a reason
--- (insufficient-funds).
function contracts.abandon(force_index, id)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  if not contract then return nil end
  if contract.advance then return repay(state, id, contract) end
  local outcome = core.abandon(contract, game.tick)
  if outcome then apply(state, id, outcome) end
  return outcome
end

--- Voids an active contract whose goods no longer exist: the guarantee comes back, reputation stays.
--- Returns the outcome, or nil.
function contracts.void(force_index, id)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  local outcome = contract and core.void(contract, game.tick)
  if outcome then apply(state, id, outcome) end
  return outcome
end

-- What serves a period of each kind of contract that charges the force, registered at load:
-- `can_serve(force_index, contract)` tells, without side effects, whether the period can be
-- delivered; `serve(force_index, contract)` delivers it and returns whether it did.
local services = {}

--- Registers, at load (file scope), the service of contracts of `kind` that charge the force.
function contracts.register_service(kind, can_serve, serve)
  services[kind] = { can_serve = can_serve, serve = serve }
end

-- Takes a period's charge. A period that cannot be delivered is skipped, uncharged; otherwise a
-- force whose available funds (overdraft included) cannot pay defaults, and one that can is charged
-- only if the service delivered. A loan's installment needs no service.
local function charge(force_index, state, id, contract, amount, tick)
  local service = services[contract.kind]
  if not (contract.advance or (service and service.can_serve(force_index, contract))) then return end
  if account.available(state) < amount then
    local outcome = core.default(contract, tick, amount)
    apply(state, id, outcome)
    return notifications.contract_settled(force_index, contract, outcome)
  end
  if contract.advance or service.serve(force_index, contract) then move(state, -amount, "contract-charge", id) end
end

--- on_nth_tick(SETTLE_TICKS): settles every open contract whose time has come, and pays or charges
--- the installments due, in id order; the force is told of each outcome and of contracts due soon
--- (scripts/notifications.lua).
function contracts.on_settle_tick(event)
  for force_index, state in pairs(storage.forces) do
    if state.contracts then
      local ids = {}
      for id in pairs(state.contracts.open) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local contract = state.contracts.open[id]
        local outcome = core.settle(contract, event.tick)
        if outcome then
          apply(state, id, outcome)
          notifications.contract_settled(force_index, contract, outcome)
        else
          local installment = core.installment(contract, event.tick)
          if installment and installment > 0 then
            move(state, installment, "contract-installment", id)
          elseif installment then
            charge(force_index, state, id, contract, -installment, event.tick)
          end
          notifications.check_due(force_index, contract)
        end
      end
    end
  end
end

return contracts
