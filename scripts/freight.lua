-- Purchase deliveries by orbital capsule (ADR-0006): a purchase is paid at once with its freight
-- fee, then lands in the hub's import chests (items) or import manifolds (fluids) capsule by
-- capsule. Queues live in storage.freight.hubs[hub_unit_number] = {next_launch, capsules =
-- {{force_index, kind, name, count, unit_cost, arrival}, ...}}, in landing order; the force that paid
-- and the market price it paid per unit are kept per capsule (ADR-0001), so cargo that can never land
-- is settled. `kind` is "item" or "fluid" (nil in capsules queued before fluids, meaning "item").
local account = require("scripts.core.account")
local cargo = require("scripts.cargo")
local core = require("scripts.core.freight")
local hubs = require("scripts.hubs")
local manifold = require("scripts.manifold")
local market = require("scripts.market")
local pricing = require("scripts.pricing")

local freight = {}

freight.TIER = core.TIERS.capsule
-- Ticks between two unloading passes over the hubs' landed capsules.
freight.UNLOAD_INTERVAL = 60
-- Fluid units that take the room of one item stack in a capsule (a stack of 10 barrels).
freight.FLUID_UNITS_PER_STACK = 500

-- How each kind of cargo is sized, received and stored.
local CARGO = {
  item = {
    stack_size = function(name) return prototypes.item[name] and prototypes.item[name].stack_size end,
    has_receiver = function(hub_unit_number) return cargo.has_import(hub_unit_number) end,
    deliver = function(hub_unit_number, name, count) return cargo.deliver(hub_unit_number, name, count) end,
    no_receiver = "no-import-chest",
  },
  fluid = {
    stack_size = function(name) return prototypes.fluid[name] and freight.FLUID_UNITS_PER_STACK end,
    has_receiver = function(hub_unit_number, name) return manifold.can_receive(hub_unit_number, name) end,
    deliver = function(hub_unit_number, name, count) return manifold.deliver(hub_unit_number, name, count) end,
    no_receiver = "no-import-manifold",
  },
}

local function queue_of(hub_unit_number)
  local queues = storage.freight.hubs
  queues[hub_unit_number] = queues[hub_unit_number] or { next_launch = 0, capsules = {} }
  return queues[hub_unit_number]
end

--- Capsules queued at a hub, landed ones waiting for room included.
function freight.queued(hub_unit_number)
  local queue = storage.freight.hubs[hub_unit_number]
  return queue and #queue.capsules or 0
end

--- The capsules queued at a hub, in landing order (read only).
function freight.capsules(hub_unit_number)
  local queue = storage.freight.hubs[hub_unit_number]
  return queue and queue.capsules or {}
end

--- What buying `units` × `name` (`kind` "item", default, or "fluid") through a hub would cost right
--- now: the market cost and the freight fee, or nil and a reason.
function freight.preview(force_index, name, units, kind)
  local cost, reason = market.preview(force_index, kind or "item", name, "buy", units)
  if not cost then return nil, reason end
  return cost, core.fee(cost, freight.TIER)
end

--- Buys `units` × `name` for a force and queues them at a hub. Pays the market cost and the freight
--- fee, or changes nothing. Returns true, the cost, the fee and the landing tick of the last
--- capsule; or false and a reason (no-import-chest, no-import-manifold, queue-full, invalid-quantity,
--- a market refusal, insufficient-funds, over-budget). `merge_ticks` (optional) merges the journal
--- entries of recurring orders; `max_cost` (optional) refuses an order whose cost and fee exceed it;
--- `kind` is "item" (default) or "fluid".
function freight.order(force_index, hub_unit_number, name, units, merge_ticks, max_cost, kind)
  kind = kind or "item"
  local cargo_kind = CARGO[kind]
  local stack_size = cargo_kind and cargo_kind.stack_size(name)
  if not stack_size then return false, "not-tradeable" end
  if not cargo_kind.has_receiver(hub_unit_number, name) then return false, cargo_kind.no_receiver end
  local existing = storage.freight.hubs[hub_unit_number]
  local capsules, next_launch = core.schedule(units, stack_size, freight.TIER, freight.queued(hub_unit_number),
    existing and existing.next_launch or 0, game.tick)
  if not capsules then return false, next_launch end
  local cost, fee = freight.preview(force_index, name, units, kind)
  if not cost then return false, fee end
  if max_cost and cost + fee > max_cost then return false, "over-budget" end
  local state = storage.forces[force_index]
  if state.balance < cost + fee then return false, "insufficient-funds" end
  local bought, paid = market.buy(force_index, kind, name, units, nil, merge_ticks)
  if not bought then return false, paid end
  -- The balance covered cost and fee in this tick; the cap only absorbs float rounding, so the debit
  -- cannot be refused.
  fee = math.min(fee, state.balance)
  account.apply(state, -fee, {
    tick = game.tick, kind = "freight", key = pricing.key(kind, name), quantity = units, merge_ticks = merge_ticks,
  })
  local queue = queue_of(hub_unit_number)
  for _, capsule in ipairs(capsules) do
    capsule.force_index, capsule.kind, capsule.name, capsule.unit_cost = force_index, kind, name, paid / units
    queue.capsules[#queue.capsules + 1] = capsule
  end
  queue.next_launch = next_launch
  return true, paid, fee, capsules[#capsules].arrival
end

-- Gives back to the force that paid the market price of cargo that cannot be sold back (the fee is
-- not refunded).
local function refund(capsule)
  local state = storage.forces[capsule.force_index]
  if not state then return end
  account.apply(state, capsule.unit_cost * capsule.count,
    { tick = game.tick, kind = "freight-refund", key = pricing.key(capsule.kind or "item", capsule.name),
      quantity = capsule.count })
end

-- Below this, what is left of a capsule's fluid counts as delivered (fluid amounts are fixed-point).
local DELIVERED_EPSILON = 1e-6

-- Unloads every landed capsule of one queue, in landing order; a capsule that does not fit whole
-- stays landed with what is left and is retried, without holding back the others (a fluid whose
-- manifold holds another fluid must not stop the items behind it).
local function unload(hub_unit_number, queue, tick)
  local capsules = queue.capsules
  local index = 1
  while capsules[index] and capsules[index].arrival <= tick do
    local capsule = capsules[index]
    local delivered = CARGO[capsule.kind or "item"].deliver(hub_unit_number, capsule.name, capsule.count)
    capsule.count = capsule.count - delivered
    if capsule.count > DELIVERED_EPSILON then
      index = index + 1
    else
      table.remove(capsules, index)
    end
  end
end

--- on_nth_tick(UNLOAD_INTERVAL): unloads landed capsules and forgets idle queues.
function freight.on_unload_tick(event)
  local queues = storage.freight.hubs
  for hub_unit_number, queue in pairs(queues) do
    unload(hub_unit_number, queue, event.tick)
    if #queue.capsules == 0 and queue.next_launch <= event.tick then queues[hub_unit_number] = nil end
  end
end

--- A hub is gone: the cargo still queued for it is sold back for the forces that paid; what the
--- market refuses (no longer tradeable, no liquidity) is refunded at the price paid.
function freight.on_hub_removed(hub_unit_number)
  local queue = storage.freight.hubs[hub_unit_number]
  if not queue then return end
  storage.freight.hubs[hub_unit_number] = nil
  for _, capsule in ipairs(queue.capsules) do
    local sold = market.sell(capsule.force_index, capsule.kind or "item", capsule.name, capsule.count)
    if not sold then refund(capsule) end
  end
end

--- on_forces_merging: capsules paid by the source force now belong to the destination.
function freight.on_forces_merging(event)
  local source, destination = event.source.index, event.destination.index
  for _, queue in pairs(storage.freight.hubs) do
    for _, capsule in ipairs(queue.capsules) do
      if capsule.force_index == source then capsule.force_index = destination end
    end
  end
end

-- Refunds and drops capsules of items or fluids that no longer exist (a mod was removed): they
-- cannot land.
local function drop_unknown_cargo(queue)
  local kept = {}
  for _, capsule in ipairs(queue.capsules) do
    if CARGO[capsule.kind or "item"].stack_size(capsule.name) then
      kept[#kept + 1] = capsule
    else
      refund(capsule)
    end
  end
  queue.capsules = kept
end

--- on_init and on_configuration_changed: creates the state, drops cargo that no longer exists and
--- settles the queues of hubs that no longer exist.
function freight.init()
  storage.freight = storage.freight or { hubs = {} }
  local gone = {}
  for hub_unit_number, queue in pairs(storage.freight.hubs) do
    drop_unknown_cargo(queue)
    if not hubs.get(hub_unit_number) then gone[#gone + 1] = hub_unit_number end
  end
  for _, hub_unit_number in ipairs(gone) do freight.on_hub_removed(hub_unit_number) end
end

return freight
