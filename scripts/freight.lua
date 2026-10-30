-- Purchase deliveries by orbital capsule (ADR-0006): a purchase is paid at once with its freight
-- fee, then lands in the hub's import chests capsule by capsule. Queues live in
-- storage.freight.hubs[hub_unit_number] = {next_launch, capsules = {{force_index, name, count,
-- unit_cost, arrival}, ...}}, in landing order; the force that paid and the market price it paid per
-- unit are kept per capsule (ADR-0001), so cargo that can never land is settled.
local account = require("scripts.core.account")
local cargo = require("scripts.cargo")
local core = require("scripts.core.freight")
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local pricing = require("scripts.pricing")

local freight = {}

freight.TIER = core.TIERS.capsule
-- Ticks between two unloading passes over the hubs' landed capsules.
freight.UNLOAD_INTERVAL = 60

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

--- What buying `units` × `name` through a hub would cost right now: the market cost and the freight
--- fee, or nil and a reason.
function freight.preview(force_index, name, units)
  local cost, reason = market.preview(force_index, "item", name, "buy", units)
  if not cost then return nil, reason end
  return cost, core.fee(cost, freight.TIER)
end

--- Buys `units` × `name` for a force and queues them at a hub. Pays the market cost and the freight
--- fee, or changes nothing. Returns true, the cost, the fee and the landing tick of the last
--- capsule; or false and a reason (no-import-chest, queue-full, invalid-quantity, a market refusal,
--- insufficient-funds).
function freight.order(force_index, hub_unit_number, name, units)
  local item = prototypes.item[name]
  if not item then return false, "not-tradeable" end
  if not cargo.has_import(hub_unit_number) then return false, "no-import-chest" end
  local existing = storage.freight.hubs[hub_unit_number]
  local capsules, next_launch = core.schedule(units, item.stack_size, freight.TIER, freight.queued(hub_unit_number),
    existing and existing.next_launch or 0, game.tick)
  if not capsules then return false, next_launch end
  local cost, fee = freight.preview(force_index, name, units)
  if not cost then return false, fee end
  local state = storage.forces[force_index]
  if state.balance < cost + fee then return false, "insufficient-funds" end
  local bought, paid = market.buy(force_index, "item", name, units)
  if not bought then return false, paid end
  -- The balance covered cost and fee in this tick; the cap only absorbs float rounding, so the debit
  -- cannot be refused.
  fee = math.min(fee, state.balance)
  account.apply(state, -fee, { tick = game.tick, kind = "freight", key = pricing.key("item", name), quantity = units })
  local queue = queue_of(hub_unit_number)
  for _, capsule in ipairs(capsules) do
    capsule.force_index, capsule.name, capsule.unit_cost = force_index, name, paid / units
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
    { tick = game.tick, kind = "freight-refund", key = pricing.key("item", capsule.name), quantity = capsule.count })
end

-- Unloads the landed capsules of one queue, in order; a capsule that does not fit whole stays
-- landed with what is left, and holds back the ones behind it.
local function unload(hub_unit_number, queue, tick)
  local capsules = queue.capsules
  while capsules[1] and capsules[1].arrival <= tick do
    local capsule = capsules[1]
    capsule.count = capsule.count - cargo.deliver(hub_unit_number, capsule.name, capsule.count)
    if capsule.count > 0 then return end
    table.remove(capsules, 1)
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
    if not market.sell(capsule.force_index, "item", capsule.name, capsule.count) then refund(capsule) end
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

-- Refunds and drops capsules of items that no longer exist (a mod was removed): they cannot land.
local function drop_unknown_items(queue)
  local kept = {}
  for _, capsule in ipairs(queue.capsules) do
    if prototypes.item[capsule.name] then
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
    drop_unknown_items(queue)
    if not hubs.get(hub_unit_number) then gone[#gone + 1] = hub_unit_number end
  end
  for _, hub_unit_number in ipairs(gone) do freight.on_hub_removed(hub_unit_number) end
end

return freight
