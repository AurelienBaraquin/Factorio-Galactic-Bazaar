-- The contract engine (ADR-0015). Pure Lua: contracts are plain tables, and every function returns
-- what changed instead of touching an account, so the adapter applies money and reputation.
--
-- One model for every exchange: a counterparty `provides` goods to the force, the force `requires`
-- goods back to it, before a deadline; the force pays a `deposit` on acceptance, gets it back with
-- the `reward` when every required unit is delivered in time, and loses it plus a `penalty` when the
-- deadline passes first. An offer not accepted by `accept_by` expires.
local contracts = {}

contracts.OFFERED, contracts.ACTIVE = "offered", "active"
contracts.FULFILLED, contracts.FAILED, contracts.EXPIRED = "fulfilled", "failed", "expired"

local KINDS = { item = true, fluid = true }

local function key_of(goods)
  return goods.kind .. "/" .. goods.name
end

local function check_goods(list)
  if type(list) ~= "table" then return "goods must be a list" end
  for _, goods in ipairs(list) do
    if not KINDS[goods.kind] or type(goods.name) ~= "string" then return "goods need a kind and a name" end
    if type(goods.count) ~= "number" or goods.count <= 0 or goods.count ~= goods.count then
      return "goods need a positive count"
    end
  end
  return nil
end

local function non_negative(n)
  return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

--- A new offer from `spec` = {kind, counterparty, provides, requires, reward, deposit, penalty,
--- duration_ticks, accept_ticks}, offered at `tick`; nil and a reason when the spec is invalid.
function contracts.new(spec, tick)
  local reason = check_goods(spec.provides or {}) or check_goods(spec.requires)
  if reason then return nil, reason end
  if #spec.requires == 0 then return nil, "a contract requires goods" end
  for _, field in ipairs({ "reward", "deposit", "penalty" }) do
    if not non_negative(spec[field]) then return nil, field .. " must be a non-negative number" end
  end
  if not (non_negative(spec.duration_ticks) and spec.duration_ticks > 0) then
    return nil, "duration must be positive"
  end
  local delivered = {}
  for _, goods in ipairs(spec.requires) do delivered[key_of(goods)] = 0 end
  return {
    kind = spec.kind, counterparty = spec.counterparty, provides = spec.provides or {}, requires = spec.requires,
    reward = spec.reward, deposit = spec.deposit, penalty = spec.penalty,
    duration_ticks = spec.duration_ticks, offered_tick = tick, accept_by = tick + (spec.accept_ticks or math.huge),
    state = contracts.OFFERED, delivered = delivered,
  }
end

--- Accepts an offer at `tick`: it becomes active with its deadline. Returns the deposit to hold, or
--- nil and a reason (not an offer, expired).
function contracts.accept(contract, tick)
  if contract.state ~= contracts.OFFERED then return nil, "not-offered" end
  if tick > contract.accept_by then return nil, "expired" end
  contract.state = contracts.ACTIVE
  contract.accepted_tick = tick
  contract.due_tick = tick + contract.duration_ticks
  return contract.deposit
end

--- Units of each required key still to deliver: {[key] = units}.
function contracts.remaining(contract)
  local left = {}
  for _, goods in ipairs(contract.requires) do
    local key = key_of(goods)
    left[key] = math.max(0, goods.count - contract.delivered[key])
  end
  return left
end

--- Records `count` units of `key` delivered to an active contract; returns how many it took (at most
--- what is still owed).
function contracts.deliver(contract, key, count)
  if contract.state ~= contracts.ACTIVE then return 0 end
  local owed = contracts.remaining(contract)[key]
  if not owed then return 0 end
  local taken = math.max(0, math.min(count, owed))
  contract.delivered[key] = contract.delivered[key] + taken
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
--- outcome {state, credits, reputation}: `credits` to add to the force (reward plus deposit when
--- fulfilled, minus the penalty when failed, 0 when expired) and a reputation change (+1, -1, 0).
--- The contract's state is updated.
function contracts.settle(contract, tick)
  if contract.state == contracts.OFFERED and tick > contract.accept_by then
    contract.state, contract.settled_tick = contracts.EXPIRED, tick
    return { state = contracts.EXPIRED, credits = 0, reputation = 0 }
  end
  if contract.state ~= contracts.ACTIVE then return nil end
  if contracts.complete(contract) then
    contract.state, contract.settled_tick = contracts.FULFILLED, tick
    return { state = contracts.FULFILLED, credits = contract.reward + contract.deposit, reputation = 1 }
  end
  if tick > contract.due_tick then
    contract.state, contract.settled_tick = contracts.FAILED, tick
    return { state = contracts.FAILED, credits = -contract.penalty, reputation = -1 }
  end
  return nil
end

--- Abandons an active contract at `tick`: it fails at once (deposit lost, penalty due).
function contracts.abandon(contract, tick)
  if contract.state ~= contracts.ACTIVE then return nil end
  contract.due_tick = math.min(contract.due_tick, tick - 1)
  return contracts.settle(contract, tick)
end

contracts.key = key_of

-- Settled contracts a force keeps for its interface.
contracts.HISTORY_SIZE = 20

--- Gives a force state its contract book if it lacks one: {next_id, open = {[id] = contract},
--- history = {contract...}}, and its reputation score.
function contracts.init_book(state)
  state.contracts = state.contracts or { next_id = 1, open = {}, history = {} }
  state.reputation = state.reputation or 0
end

--- Files a contract in a force's book; returns its id.
function contracts.file(state, contract)
  local book = state.contracts
  local id = book.next_id
  book.next_id = id + 1
  contract.id = id
  book.open[id] = contract
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

--- Folds a merged force's book into the destination's: its open contracts carry on under new ids,
--- its reputation adds up; its history is dropped.
function contracts.merge_books(destination, source)
  contracts.init_book(destination)
  contracts.init_book(source)
  local ids = {}
  for id in pairs(source.contracts.open) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do contracts.file(destination, source.contracts.open[id]) end
  destination.reputation = destination.reputation + source.reputation
end

return contracts
