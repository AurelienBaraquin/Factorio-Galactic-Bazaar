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

-- Modules that give hubs a better tier through a building of theirs (ADR-0014). A provider is
-- {tier = name, available = fn(hub) -> bool, can_supply = fn(hub, shipments) -> bool (optional),
-- supply = fn(hub, shipments) (optional), delivers = fn(hub) -> bool (optional)}: `available` says
-- whether the hub has the tier now and `can_supply` whether it can ship that many shipments (fuel...),
-- both without side effect, since they are asked on every read (previews, window refreshes); `supply`
-- consumes what the shipments of a paid order need, and is called only after `can_supply` said yes
-- in the same tick; `delivers` says whether shipments of the tier already queued can land at the hub
-- now: true, false (a teleporter without power holds them) or nil when the provider has no building
-- at that hub. Providers
-- are registered at file scope when their module loads, the same on every peer, never from an event
-- handler.
local tier_providers = {}

--- Registers a tier provider (see above).
function freight.register_tier_provider(provider)
  tier_providers[#tier_providers + 1] = provider
end

-- Whether shipments of `tier_name` can land at a hub now. Only a provider with `delivers` can hold
-- its tier's shipments, and only when it has a building at that hub that cannot deliver (a teleporter
-- without power); they land when any provider of the tier delivers, or when none holds them (a
-- shuttle's fuel was paid with the order; the orbital capsule always lands).
local function delivers(hub_unit_number, tier_name)
  local held = false
  for _, provider in ipairs(tier_providers) do
    if provider.tier == tier_name and provider.delivers then
      local answer = provider.delivers(hub_unit_number)
      if answer == true then return true end
      held = held or answer == false
    end
  end
  return not held
end

-- The tiers a hub can ship by now, best first, each with its provider; the orbital capsule last.
local function candidates(hub_unit_number)
  local list = {}
  for _, provider in ipairs(tier_providers) do
    local tier = core.TIERS[provider.tier]
    if tier and hub_unit_number and provider.available(hub_unit_number) then
      list[#list + 1] = { tier = tier, provider = provider }
    end
  end
  table.sort(list, function(a, b) return a.tier.rank > b.tier.rank end)
  list[#list + 1] = { tier = core.TIERS[core.DEFAULT_TIER] }
  return list
end

--- The tier a hub ships by now: the best one its buildings provide, the orbital capsule otherwise.
function freight.tier(hub_unit_number)
  return candidates(hub_unit_number)[1].tier
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

-- How a hub would ship `units` × `name` now: the best tier that has room in its queue and can supply
-- every shipment (a bay short of fuel hands the order down to the next tier). Returns the tier, its
-- provider, the shipments and the tier's next free launch tick; or nil and the last tier's reason.
local function plan(hub_unit_number, units, stack_size)
  local existing = storage.freight.hubs[hub_unit_number]
  local reason
  for _, candidate in ipairs(candidates(hub_unit_number)) do
    local tier, provider = candidate.tier, candidate.provider
    local capsules, launch = core.schedule(units, stack_size, tier, freight.queued(hub_unit_number, tier.name),
      next_launch(existing, tier.name), game.tick)
    if not capsules then
      reason = launch
    elseif not (provider and provider.can_supply) or provider.can_supply(hub_unit_number, #capsules) then
      return tier, provider, capsules, launch
    end
  end
  return nil, reason
end

--- The tier an order of `units` × `name` (`kind` "item", default, or "fluid") would ship by from a hub
--- now, or nil when no tier can take it.
function freight.tier_for(hub_unit_number, name, units, kind)
  local cargo_kind = CARGO[kind or "item"]
  local stack_size = cargo_kind and cargo_kind.stack_size(name)
  if not (stack_size and hub_unit_number) then return nil end
  return (plan(hub_unit_number, units, stack_size))
end

--- What buying `units` × `name` (`kind` "item", default, or "fluid") through a hub would cost right
--- now: the market cost and the freight fee of the tier that order would ship by (the capsule's
--- without a hub), or nil and a reason.
function freight.preview(force_index, name, units, kind, hub_unit_number)
  local cost, reason = market.preview(force_index, kind or "item", name, "buy", units)
  if not cost then return nil, reason end
  local tier = hub_unit_number and freight.tier_for(hub_unit_number, name, units, kind)
    or core.TIERS[core.DEFAULT_TIER]
  return cost, core.fee(cost, tier)
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
  local tier, provider, capsules, launch = plan(hub_unit_number, units, stack_size)
  if not tier then return false, provider end
  if expected_tier and tier.name ~= expected_tier then return false, "tier-changed" end
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
  if provider and provider.supply then provider.supply(hub_unit_number, #capsules) end
  local queue = queue_of(hub_unit_number)
  for _, capsule in ipairs(capsules) do
    capsule.force_index, capsule.kind, capsule.name, capsule.unit_cost = force_index, kind, name, paid / units
    capsule.tier = tier.name
    queue.capsules[#queue.capsules + 1] = capsule
  end
  queue.launches[tier.name] = launch
  return true, paid, fee, capsules[#capsules].arrival
end

--- Ships goods a contract's counterparty provides (ADR-0015) to a hub, free for the force, by
--- orbital capsule (the counterparty's own transport): `goods` = {{kind, name, count}...}. Either
--- every good is queued or none is. Returns true and the landing tick of the last capsule, or false
--- and a reason (no-import-chest, no-import-manifold, queue-full, not-tradeable, invalid-quantity).
--- Such capsules are never sold back: the goods were the counterparty's.
function freight.ship(force_index, hub_unit_number, goods, contract_id)
  local tier = core.TIERS[core.DEFAULT_TIER]
  local existing = storage.freight.hubs[hub_unit_number]
  local queued, launch = freight.queued(hub_unit_number, tier.name), next_launch(existing, tier.name)
  local planned = {}
  for _, entry in ipairs(goods) do
    local cargo_kind = CARGO[entry.kind]
    local stack_size = cargo_kind and cargo_kind.stack_size(entry.name)
    if not stack_size then return false, "not-tradeable" end
    if not cargo_kind.has_receiver(hub_unit_number, entry.name) then return false, cargo_kind.no_receiver end
    local capsules, after = core.schedule(entry.count, stack_size, tier, queued, launch, game.tick)
    if not capsules then return false, after end
    for _, capsule in ipairs(capsules) do
      capsule.force_index, capsule.kind, capsule.name, capsule.unit_cost = force_index, entry.kind, entry.name, 0
      capsule.tier, capsule.contract = tier.name, contract_id
      planned[#planned + 1] = capsule
    end
    queued, launch = queued + #capsules, after
  end
  local queue = queue_of(hub_unit_number)
  for _, capsule in ipairs(planned) do queue.capsules[#queue.capsules + 1] = capsule end
  queue.launches[tier.name] = launch
  return true, planned[#planned] and planned[#planned].arrival
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
    local landed = capsule.arrival <= tick and delivers(hub_unit_number, capsule.tier or core.DEFAULT_TIER)
    if landed then
      remaining = remaining - CARGO[capsule.kind or "item"].deliver(hub_unit_number, capsule.name, remaining)
      capsule.count = remaining
    end
    if landed and remaining <= DELIVERED_EPSILON then
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
    if not capsule.contract then
      local sold = market.sell(capsule.force_index, capsule.kind or "item", capsule.name, capsule.count)
      if not sold then refund(capsule) end
    end
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
