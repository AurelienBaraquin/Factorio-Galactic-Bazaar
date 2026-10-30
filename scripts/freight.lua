-- Purchase deliveries by orbital capsule (ADR-0006): a purchase is paid at once with its freight
-- fee, then lands in the hub's import chests (items) or import manifolds (fluids) capsule by
-- capsule. Queues live in storage.freight.hubs[hub_unit_number] = {launches = {[tier] = next free
-- launch tick}, next_launch (the capsule's, before 0.1.10), capsules =
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

freight.TIERS = core.TIERS

-- Functions that say which tier a hub has through a building of theirs (ADR-0014): each takes a hub
-- unit number and returns a tier name or nil. They must have no side effect (they are asked on every
-- read: previews, window refreshes) and be registered at file scope when their module loads, the same
-- on every peer, never from an event handler.
local tier_providers = {}

--- Registers a tier provider (see above).
function freight.register_tier_provider(provider)
  tier_providers[#tier_providers + 1] = provider
end

--- The tier a hub ships by now: the best one its buildings provide, the orbital capsule otherwise.
function freight.tier(hub_unit_number)
  local available = {}
  for _, provider in ipairs(tier_providers) do
    local name = hub_unit_number and provider(hub_unit_number)
    if name then available[#available + 1] = name end
  end
  return core.best(available)
end
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
  queues[hub_unit_number] = queues[hub_unit_number] or { launches = {}, capsules = {} }
  queues[hub_unit_number].launches = queues[hub_unit_number].launches or {}
  return queues[hub_unit_number]
end

-- Each tier launches on its own schedule (ADR-0014): a fast tier never waits behind a slow one.
local function next_launch(queue, tier_name)
  if not queue then return 0 end
  local launch = queue.launches and queue.launches[tier_name]
  if launch then return launch end
  return tier_name == core.DEFAULT_TIER and queue.next_launch or 0
end

--- Shipments queued at a hub, landed ones waiting for room included; only those of `tier_name` when
--- given (shipments queued before 0.1.10 are capsules).
function freight.queued(hub_unit_number, tier_name)
  local queue = storage.freight.hubs[hub_unit_number]
  if not queue then return 0 end
  if not tier_name then return #queue.capsules end
  local count = 0
  for _, capsule in ipairs(queue.capsules) do
    if (capsule.tier or core.DEFAULT_TIER) == tier_name then count = count + 1 end
  end
  return count
end

--- The capsules queued at a hub, in landing order (read only).
function freight.capsules(hub_unit_number)
  local queue = storage.freight.hubs[hub_unit_number]
  return queue and queue.capsules or {}
end

--- What buying `units` × `name` (`kind` "item", default, or "fluid") through a hub would cost right
--- now: the market cost and the freight fee of the hub's tier (the capsule's without a hub), or nil
--- and a reason.
function freight.preview(force_index, name, units, kind, hub_unit_number)
  local cost, reason = market.preview(force_index, kind or "item", name, "buy", units)
  if not cost then return nil, reason end
  return cost, core.fee(cost, freight.tier(hub_unit_number))
end

--- Buys `units` × `name` for a force and queues them at a hub. Pays the market cost and the freight
--- fee, or changes nothing. Returns true, the cost, the fee and the landing tick of the last
--- capsule; or false and a reason (no-import-chest, no-import-manifold, queue-full, invalid-quantity,
--- a market refusal, insufficient-funds, over-budget). `merge_ticks` (optional) merges the journal
--- entries of recurring orders; `max_cost` (optional) refuses an order whose cost and fee exceed it;
--- `kind` is "item" (default) or "fluid"; `expected_tier` (optional) refuses the order with
--- `tier-changed` when the hub's tier is no longer that one (what a player saw in a preview).
function freight.order(force_index, hub_unit_number, name, units, merge_ticks, max_cost, kind, expected_tier)
  kind = kind or "item"
  local cargo_kind = CARGO[kind]
  local stack_size = cargo_kind and cargo_kind.stack_size(name)
  if not stack_size then return false, "not-tradeable" end
  if not cargo_kind.has_receiver(hub_unit_number, name) then return false, cargo_kind.no_receiver end
  local existing = storage.freight.hubs[hub_unit_number]
  local tier = freight.tier(hub_unit_number)
  if expected_tier and tier.name ~= expected_tier then return false, "tier-changed" end
  local capsules, launch = core.schedule(units, stack_size, tier, freight.queued(hub_unit_number, tier.name),
    next_launch(existing, tier.name), game.tick)
  if not capsules then return false, launch end
  local cost, reason = market.preview(force_index, kind, name, "buy", units)
  if not cost then return false, reason end
  local fee = core.fee(cost, tier)
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
    capsule.tier = tier.name
    queue.capsules[#queue.capsules + 1] = capsule
  end
  queue.launches[tier.name] = launch
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

-- Unloads every landed shipment of one queue, in the order they were ordered; tiers land on their
-- own schedules, so a shipment still in flight never holds back a landed one behind it. A shipment
-- that does not fit whole stays landed with what is left and is retried, without holding back the
-- others either (a fluid whose manifold holds another fluid must not stop the items behind it).
local function unload(hub_unit_number, queue, tick)
  local capsules = queue.capsules
  local index = 1
  while capsules[index] do
    local capsule = capsules[index]
    local remaining = capsule.count
    if capsule.arrival <= tick then
      remaining = remaining - CARGO[capsule.kind or "item"].deliver(hub_unit_number, capsule.name, remaining)
      capsule.count = remaining
    end
    if capsule.arrival <= tick and remaining <= DELIVERED_EPSILON then
      table.remove(capsules, index)
    else
      index = index + 1
    end
  end
end

-- Whether a queue has nothing left to unload or to space out: it can be forgotten.
local function idle(queue, tick)
  if #queue.capsules > 0 or (queue.next_launch or 0) > tick then return false end
  for _, launch in pairs(queue.launches or {}) do
    if launch > tick then return false end
  end
  return true
end

--- on_nth_tick(UNLOAD_INTERVAL): unloads landed capsules and forgets idle queues.
function freight.on_unload_tick(event)
  local queues = storage.freight.hubs
  for hub_unit_number, queue in pairs(queues) do
    unload(hub_unit_number, queue, event.tick)
    if idle(queue, event.tick) then queues[hub_unit_number] = nil end
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
