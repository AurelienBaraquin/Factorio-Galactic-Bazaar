-- Per-force economy state registry (ADR-0001). Pure Lua: operates on a plain table
-- `forces` keyed by force index, so it runs identically in the game and under busted.
local account = require("scripts.core.account")
local contracts = require("scripts.core.contracts")

local force_registry = {}

--- Returns the state of `force_index`, creating it if it is missing and filling in any field it
--- lacks (which also upgrades states saved by an older version of the mod).
function force_registry.ensure(forces, force_index)
  local state = forces[force_index]
  if not state then
    state = {}
    forces[force_index] = state
  end
  account.init(state)
  contracts.init_book(state)
  state.markets = state.markets or {}
  return state
end

--- Makes `forces` hold exactly the indices in `force_indices`: creates the missing states and
--- drops the states of forces that no longer exist.
function force_registry.sync(forces, force_indices)
  local wanted = {}
  for _, force_index in ipairs(force_indices) do
    wanted[force_index] = true
    force_registry.ensure(forces, force_index)
  end
  local stale = {}
  for force_index in pairs(forces) do
    if not wanted[force_index] then stale[#stale + 1] = force_index end
  end
  for _, force_index in ipairs(stale) do forces[force_index] = nil end
end

--- Folds the state of `source_index` into `destination_index`, then removes the source.
--- Each field added to the force state must define here how two values combine. Markets and feed:
--- the destination keeps its own; the source's are dropped with it. Contracts: the source's open
--- contracts carry on in the destination's book; only a reputation debt follows.
function force_registry.merge(forces, source_index, destination_index)
  local destination = force_registry.ensure(forces, destination_index)
  local source = forces[source_index]
  if source then
    account.init(source)
    account.merge(destination, source)
    contracts.merge_books(destination, source)
  end
  forces[source_index] = nil
end

return force_registry
