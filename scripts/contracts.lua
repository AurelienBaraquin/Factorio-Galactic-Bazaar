-- Contracts of each force (ADR-0015): the runtime side of the contract engine. Contracts live in
-- each force's book (storage.forces[i].contracts); money moves through the force's account, the
-- reputation score is the force's (storage.forces[i].reputation). Every SETTLE_TICKS, open contracts
-- whose time has come are settled. Goods are moved by the features that offer contracts.
local account = require("scripts.core.account")
local core = require("scripts.core.contracts")

local contracts = {}

contracts.SETTLE_TICKS = 60

-- The state of a force that has a contract book, or nil.
local function state_of(force_index)
  local state = storage.forces[force_index]
  return state and state.contracts and state or nil
end

--- Files an offer for a force from `spec` (see scripts/core/contracts.lua); returns its id, or nil
--- and a reason.
function contracts.offer(force_index, spec)
  local state = state_of(force_index)
  if not state then return nil, "no-force" end
  local contract, reason = core.new(spec, game.tick)
  if not contract then return nil, reason end
  return core.file(state, contract)
end

--- The open contract `id` of a force, or nil.
function contracts.get(force_index, id)
  local state = state_of(force_index)
  return state and state.contracts.open[id]
end

--- Accepts an offer: the force pays its deposit, or nothing changes. Returns true, or false and a
--- reason (unknown, not-offered, expired, insufficient-funds).
function contracts.accept(force_index, id)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  if not contract then return false, "unknown" end
  if contract.state ~= core.OFFERED then return false, "not-offered" end
  if game.tick > contract.accept_by then return false, "expired" end
  if state.balance < contract.deposit then return false, "insufficient-funds" end
  local deposit = core.accept(contract, game.tick)
  account.apply(state, -deposit, { tick = game.tick, kind = "contract-deposit", key = "contract/" .. id })
  return true
end

--- Records `count` units of `key` ("item/<name>") handed over for an active contract; returns how
--- many it took.
function contracts.deliver(force_index, id, key, count)
  local contract = contracts.get(force_index, id)
  return contract and core.deliver(contract, key, count) or 0
end

-- Applies an outcome to the force: credits through its account (a penalty takes at most what the
-- force has: debt is for the finance milestone) and reputation; then files the contract away.
local function apply(state, id, outcome)
  local credits = outcome.credits
  if credits < 0 then credits = -math.min(-credits, state.balance) end
  if credits ~= 0 then
    account.apply(state, credits, { tick = game.tick, kind = "contract-" .. outcome.state, key = "contract/" .. id })
  end
  state.reputation = state.reputation + outcome.reputation
  core.close(state, id)
end

--- Abandons an active contract: it fails at once. Returns the outcome, or nil.
function contracts.abandon(force_index, id)
  local state = state_of(force_index)
  local contract = state and state.contracts.open[id]
  if not contract then return nil end
  local outcome = core.abandon(contract, game.tick)
  if outcome then apply(state, id, outcome) end
  return outcome
end

--- on_nth_tick(SETTLE_TICKS): settles every open contract whose time has come, in id order.
function contracts.on_settle_tick(event)
  for _, state in pairs(storage.forces) do
    if state.contracts then
      local ids = {}
      for id in pairs(state.contracts.open) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local outcome = core.settle(state.contracts.open[id], event.tick)
        if outcome then apply(state, id, outcome) end
      end
    end
  end
end

return contracts
