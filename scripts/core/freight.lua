-- Scheduling of purchase deliveries by logistics tier (ADR-0006). Pure Lua.
--
-- A purchase is split into capsules of at most `capacity_stacks` stacks. A hub launches one capsule
-- every `launch_interval_ticks`, and a capsule lands `delay_ticks` after its launch. A hub queues at
-- most `max_capsules` capsules, landed ones waiting for room included. The buyer pays a freight fee
-- of `fee_rate` times the market cost.
local freight = {}

freight.TIERS = {
  capsule = {
    delay_ticks = 1800,
    launch_interval_ticks = 600,
    capacity_stacks = 10,
    fee_rate = 0.05,
    max_capsules = 20,
  },
}

--- Freight fee of a purchase that cost `cost` credits.
function freight.fee(cost, tier)
  return cost * tier.fee_rate
end

--- Units one capsule carries of an item whose stacks hold `stack_size`.
function freight.capsule_units(stack_size, tier)
  return stack_size * tier.capacity_stacks
end

--- Most units a hub whose queue holds `queued` capsules can still order.
function freight.max_order(queued, stack_size, tier)
  return math.max(0, tier.max_capsules - queued) * freight.capsule_units(stack_size, tier)
end

--- Capsules carrying `units` units, launched from `now` at the earliest and not before
--- `next_launch` (the hub's next free launch tick). Returns the capsules ({count, arrival}, in
--- launch order) and the hub's new next free launch tick; nil and "queue-full" when the order needs
--- more capsules than the `queued` ones leave room for, nil and "invalid-quantity" when `units` is
--- not a positive whole number.
function freight.schedule(units, stack_size, tier, queued, next_launch, now)
  if units ~= units or units < 1 or units % 1 ~= 0 then return nil, "invalid-quantity" end
  if units > freight.max_order(queued, stack_size, tier) then return nil, "queue-full" end
  local per_capsule = freight.capsule_units(stack_size, tier)
  local launch = math.max(now, next_launch)
  local capsules = {}
  local remaining = units
  while remaining > 0 do
    local count = math.min(remaining, per_capsule)
    capsules[#capsules + 1] = { count = count, arrival = launch + tier.delay_ticks }
    remaining = remaining - count
    launch = launch + tier.launch_interval_ticks
  end
  return capsules, launch
end

return freight
