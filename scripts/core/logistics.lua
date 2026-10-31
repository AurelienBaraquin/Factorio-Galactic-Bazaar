-- What the Logistics tab of the Galactic Bazaar window shows (#109): a force's hubs, the shipments
-- queued and in flight at one of them and the modules attached to it. Pure Lua: every function takes
-- plain data the adapter (scripts/logistics_gui.lua) read from storage and the game, and returns the
-- rows to show; nothing here changes its inputs.
local logistics = {}

-- Rows on one page of each list of the tab.
logistics.HUB_ROWS = 5
logistics.SHIPMENT_ROWS = 8
logistics.MODULE_ROWS = 8

local DEFAULT_TIER = "capsule"

--- One page of `list`: {items = slice, page, pages}, `page` clamped to the pages that exist (one
--- empty page for an empty list).
function logistics.page(list, page, size)
  local pages = math.max(1, math.ceil(#list / size))
  page = math.max(1, math.min(math.floor(page or 1), pages))
  local items = {}
  for i = (page - 1) * size + 1, math.min(page * size, #list) do items[#items + 1] = list[i] end
  return { items = items, page = page, pages = pages }
end

--- A game tick as the time of the game it falls on, "h:mm:ss".
function logistics.clock(tick)
  local seconds = math.floor(tick / 60)
  return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

--- The hubs ({unit_number, surface_index, ...}) ordered by surface, then unit number: a new list.
function logistics.hubs(list)
  local sorted = {}
  for i, hub in ipairs(list) do sorted[i] = hub end
  table.sort(sorted, function(a, b)
    if a.surface_index ~= b.surface_index then return a.surface_index < b.surface_index end
    return a.unit_number < b.unit_number
  end)
  return sorted
end

--- The hub to show in detail among `hubs` ({unit_number}...): `selected` while it is listed, otherwise
--- `preferred` (the window's hub) when listed, otherwise the first one; nil without a hub.
function logistics.select(hubs, selected, preferred)
  local first, found_preferred
  for _, hub in ipairs(hubs) do
    if hub.unit_number == selected then return selected end
    if hub.unit_number == preferred then found_preferred = preferred end
    first = first or hub.unit_number
  end
  return found_preferred or first
end

--- How full each tier's queue is at a hub: {{name, queued, max}...}, best tier first, for each tier
--- with a shipment queued, plus `current` (the tier the hub ships by now) even when empty. Shipments
--- queued before tiers were recorded are the orbital capsule's.
function logistics.queue_use(capsules, tiers, current)
  local queued = {}
  if current then queued[current] = 0 end
  for _, capsule in ipairs(capsules) do
    local tier = capsule.tier or DEFAULT_TIER
    queued[tier] = (queued[tier] or 0) + 1
  end
  local use = {}
  for name, count in pairs(queued) do
    local tier = tiers[name]
    if tier then use[#use + 1] = { name = name, queued = count, max = tier.max_capsules } end
  end
  table.sort(use, function(a, b) return tiers[a.name].rank > tiers[b.name].rank end)
  return use
end

-- Where a shipment comes from: "purchase" (no contract), "incoming" (an incoming contract's
-- ingredients, which the force does not pay for), the kind of the contract that shipped it from a
-- planet ("concession", "outsourcing"), or "planet" when that contract is no longer known (a paid
-- contract shipment queued before planets were recorded is one); and the planet's name.
local function origin(capsule, contracts)
  if not capsule.contract then return "purchase" end
  local contract = contracts[capsule.contract]
  local from_planet = contract and (contract.kind == "concession" or contract.kind == "outsourcing")
  if capsule.planet or from_planet or capsule.unit_cost > 0 then
    return from_planet and contract.kind or "planet", capsule.planet or from_planet and contract.counterparty or nil
  end
  return "incoming"
end

--- A shipment's row at tick `now`: {kind, name, count, tier, arrival, left (ticks until it lands, at
--- least 0), launch (its launch tick, nil from a planet), state, origin, contract, planet, loss,
--- unit_cost}. `state` is "queued" (waiting for its launch: the tier launches one shipment per
--- interval), "in-flight", "in-transit" (from a planet), "unloading" (landed since the last unloading
--- pass, which runs on every tick that is a multiple of `unload_ticks`: the next one takes it),
--- "no-room" (landed, and a pass found no room for it in the import chests or manifolds) or "held"
--- (landed, but its tier cannot deliver at the hub now: `facts.held[tier]`).
--- `facts` = {unload_ticks, held = {[tier] = true}, contracts = {[id] = {kind, counterparty}}}.
function logistics.shipment(capsule, now, tiers, facts)
  local tier_name = capsule.tier or DEFAULT_TIER
  local tier = tiers[tier_name] or tiers[DEFAULT_TIER]
  local kind, planet = origin(capsule, facts.contracts)
  local row = {
    kind = capsule.kind or "item", name = capsule.name, count = capsule.count, tier = tier_name,
    arrival = capsule.arrival, left = math.max(0, capsule.arrival - now), origin = kind, contract = capsule.contract,
    planet = planet, loss = capsule.loss, unit_cost = capsule.unit_cost,
  }
  if capsule.arrival <= now then
    if facts.held[tier_name] then
      row.state = "held"
    else
      row.state = capsule.arrival > now - now % facts.unload_ticks and "unloading" or "no-room"
    end
  elseif kind ~= "purchase" and kind ~= "incoming" then
    row.state = "in-transit"
  else
    row.launch = capsule.arrival - tier.delay_ticks
    row.state = now < row.launch and "queued" or "in-flight"
  end
  return row
end

--- The rows of the shipments a force has at a hub (see `logistics.shipment`), by landing tick, in
--- queue order on a tie (`index`, the capsule's position in the queue).
function logistics.shipments(capsules, force_index, now, tiers, facts)
  local rows = {}
  for index, capsule in ipairs(capsules) do
    if capsule.force_index == force_index then
      local row = logistics.shipment(capsule, now, tiers, facts)
      row.index = index
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, function(a, b)
    if a.arrival ~= b.arrival then return a.arrival < b.arrival end
    return a.index < b.index
  end)
  return rows
end

--- The modules attached to a hub, from {{rank (their kind's order), name (the building), unit_number,
--- descriptor (its status: a descriptor, false for the game's own, nil before its first refresh)}...}:
--- {rows = {{rank, name, unit_number, diode}...} ordered by kind, building and unit number (`diode`
--- nil without a descriptor), groups = {{name, count, green, yellow, red}...} one per building in the
--- same order}.
function logistics.modules(modules)
  local rows = {}
  for i, module in ipairs(modules) do
    local descriptor = module.descriptor
    rows[i] = {
      rank = module.rank, name = module.name, unit_number = module.unit_number,
      diode = descriptor and descriptor.diode or nil,
    }
  end
  table.sort(rows, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.name ~= b.name then return a.name < b.name end
    return a.unit_number < b.unit_number
  end)
  local groups, last = {}, nil
  for _, row in ipairs(rows) do
    if not (last and last.name == row.name) then
      last = { name = row.name, count = 0, green = 0, yellow = 0, red = 0 }
      groups[#groups + 1] = last
    end
    last.count = last.count + 1
    if row.diode then last[row.diode] = last[row.diode] + 1 end
  end
  return { rows = rows, groups = groups }
end

return logistics
