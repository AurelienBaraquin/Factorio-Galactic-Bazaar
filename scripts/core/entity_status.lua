-- What each building of the mod tells the player about itself (#106). Pure Lua: every function takes
-- plain facts the adapter (scripts/entity_status.lua) read from the game and returns a status
-- descriptor {diode = "green" | "yellow" | "red", label = LocalisedString, alert = nil | "no-hub" |
-- "hub-unpowered" | "unpowered"}, or nil when the building keeps the game's own status: the diode
-- and label go to the entity's custom status, an alert is drawn on the entity so that what is wrong
-- shows at a glance. Labels hold no moving value (an age, a countdown): a status is refreshed every
-- few seconds and written only when it changed.
local catalog = require("scripts.core.catalog")

local status = {}

status.GREEN, status.YELLOW, status.RED = "green", "yellow", "red"
-- Alerts: no hub of the building's force in range; its hub has no power; it has no power itself.
status.NO_HUB, status.HUB_UNPOWERED, status.UNPOWERED = "no-hub", "hub-unpowered", "unpowered"
-- Goods a contract chest's status names; the others are counted. A LocalisedString holds at most 20
-- parameters: this list takes 2 × MAX_LISTED.
status.MAX_LISTED = 4
-- Refusals of an order that have a text of their own in the Market tab ([gb-gui] refused-*).
local KNOWN_REFUSALS = {
  ["no-import-chest"] = true, ["no-import-manifold"] = true, ["insufficient-funds"] = true,
  ["insufficient-liquidity"] = true, ["not-tradeable"] = true, ["invalid-quantity"] = true,
}

local function descriptor(diode, label, alert)
  return { diode = diode, label = label, alert = alert }
end

local function percent(share)
  return math.floor(share * 100 + 1e-9)
end

--- The status of a module attached to a hub (ADR-0005): `hub` is "none" (no hub of its force),
--- "unpowered" or "powered"; `needs_power` says whether the module stops without a powered hub;
--- `attached` is the module's own status (nil: the game's own), given while its hub has power, or
--- kept under a warning when the module works on without it.
function status.module(hub, needs_power, attached)
  if hub == "none" then return descriptor(status.RED, { "gb-status.no-hub" }, status.NO_HUB) end
  if hub == "unpowered" then
    if needs_power then return descriptor(status.RED, { "gb-status.stopped-no-power" }, status.HUB_UNPOWERED) end
    if not attached then return descriptor(status.YELLOW, { "gb-status.hub-unpowered-only" }) end
    return descriptor(status.YELLOW, { "gb-status.hub-unpowered-then", attached.label })
  end
  return attached
end

--- A trading hub: {powered, modules (attached, of its force), queued (shipments), tier (name)}.
function status.hub(facts)
  if not facts.powered then
    return descriptor(status.RED, { "gb-status.hub-unpowered", facts.modules, facts.queued }, status.UNPOWERED)
  end
  return descriptor(status.GREEN, { "gb-status.hub", facts.modules, facts.queued, { "gb-gui.tier-" .. facts.tier } })
end

--- An export chest: {empty, held (its last visit sold nothing of what it holds)}.
function status.export_chest(facts)
  if facts.empty then return descriptor(status.GREEN, { "gb-status.export-empty" }) end
  if facts.held then return descriptor(status.YELLOW, { "gb-status.export-held" }) end
  return descriptor(status.GREEN, { "gb-status.export-selling" })
end

--- An import chest: {queued (shipments on the way to its hub)}.
function status.import_chest(facts)
  if facts.queued > 0 then return descriptor(status.GREEN, { "gb-status.import-receiving", facts.queued }) end
  return descriptor(status.GREEN, { "gb-status.import-ready" })
end

--- An export manifold: {fluid (name, nil when empty), held (its last visit sold none of it)}.
function status.fluid_export(facts)
  if not facts.fluid then return descriptor(status.GREEN, { "gb-status.fluid-export-empty" }) end
  local fluid = "[fluid=" .. facts.fluid .. "]"
  if facts.held then return descriptor(status.YELLOW, { "gb-status.fluid-export-held", fluid }) end
  return descriptor(status.GREEN, { "gb-status.fluid-export-selling", fluid })
end

--- An import manifold: {fluid (the name it holds, nil when empty)}.
function status.fluid_import(facts)
  if not facts.fluid then return descriptor(status.GREEN, { "gb-status.fluid-import-ready" }) end
  return descriptor(status.GREEN, { "gb-status.fluid-import-holds", "[fluid=" .. facts.fluid .. "]" })
end

--- A power substation: {direction ("export" or "import"), last (its force's last settlement in that
--- direction, nil before the first: {units (MJ traded), held (exports kept energy the price floor did
--- not sell), short (imports lacked energy that was not bought)})}.
function status.power(facts)
  local last, export = facts.last, facts.direction == "export"
  if last and last.units > 0 then
    return descriptor(status.GREEN, { export and "gb-status.power-export" or "gb-status.power-import",
      string.format("%.1f", last.units) })
  end
  if export then
    if last and last.held then return descriptor(status.YELLOW, { "gb-status.power-export-held" }) end
    return descriptor(status.GREEN, { "gb-status.power-export-waiting" })
  end
  if last and last.short then return descriptor(status.YELLOW, { "gb-status.power-import-blocked" }) end
  return descriptor(status.GREEN, { "gb-status.power-import-waiting" })
end

--- A price combinator: {side ("buy" or "sell"), ready (its force has a snapshot), count (prices it
--- emits), period_seconds (how often the snapshot is taken again)}.
function status.price_combinator(facts)
  if not facts.ready then return descriptor(status.YELLOW, { "gb-status.price-waiting" }) end
  return descriptor(status.GREEN, { "gb-status.price-emitting-" .. facts.side, facts.count, facts.period_seconds })
end

local ORDER_RESULTS = {
  refused = { status.RED, "gb-status.order-refused" },
  ["no-budget"] = { status.YELLOW, "gb-status.order-no-budget" },
  ["no-orders"] = { status.GREEN, "gb-status.order-no-orders" },
  ["queue-full"] = { status.YELLOW, "gb-status.order-queue-full" },
  ["budget-spent"] = { status.YELLOW, "gb-status.order-budget-spent" },
  ["no-funds"] = { status.YELLOW, "gb-status.order-no-funds" },
}

--- An order combinator: {last (its last reading, nil before the first)}. `last.result` is "placed"
--- (with `placed` orders, the `budget_left` and, when the last request was refused, its `reason` and
--- the `allowance` it had: the budget left, or less when the funds were lower) or one of the refusals
--- in ORDER_RESULTS.
function status.order_combinator(facts)
  local last = facts.last
  if not last then return descriptor(status.GREEN, { "gb-status.order-waiting" }) end
  local refusal = ORDER_RESULTS[last.result]
  if refusal then return descriptor(refusal[1], { refusal[2] }) end
  local budget_left = catalog.format_credits(last.budget_left)
  if last.placed > 0 then return descriptor(status.GREEN, { "gb-status.order-placed", last.placed, budget_left }) end
  if last.reason == "over-budget" then
    if last.allowance < last.budget_left then return descriptor(status.YELLOW, { "gb-status.order-over-funds" }) end
    return descriptor(status.YELLOW, { "gb-status.order-over-budget", budget_left })
  end
  local reason = KNOWN_REFUSALS[last.reason] and { "gb-gui.refused-" .. last.reason }
    or { "gb-status.order-failed-other" }
  return descriptor(status.YELLOW, { "gb-status.order-failed", reason })
end

--- A docking bay: {fuel_mj (its own), shipment_mj (what a shipment burns), fueled (its hub's bays
--- hold a shipment's fuel), tier (the tier its hub ships by now)}.
function status.docking_bay(facts)
  local fuel, need = string.format("%.0f", facts.fuel_mj), string.format("%.0f", facts.shipment_mj)
  local tier = { "gb-gui.tier-" .. facts.tier }
  if facts.fueled then return descriptor(status.GREEN, { "gb-status.bay-fueled", fuel, need, tier }) end
  return descriptor(status.YELLOW, { "gb-status.bay-no-fuel", fuel, need, tier })
end

--- A teleporter: {powered, charge (share of its buffer)}.
function status.teleporter(facts)
  if facts.powered then return descriptor(status.GREEN, { "gb-status.teleporter-powered" }) end
  return descriptor(status.RED, { "gb-status.teleporter-unpowered", percent(facts.charge) }, status.UNPOWERED)
end

--- A catapult: {charge (share of its capacitor), shot_share (share a shot needs), empty, held (its
--- last shot attempt sold nothing), shot_seconds (shortest time between two shots)}.
function status.catapult(facts)
  local charge = percent(facts.charge)
  if facts.charge < facts.shot_share then
    return descriptor(status.YELLOW, { "gb-status.catapult-charging", charge, percent(facts.shot_share) })
  end
  if facts.empty then return descriptor(status.GREEN, { "gb-status.catapult-empty", charge }) end
  if facts.held then return descriptor(status.YELLOW, { "gb-status.catapult-held", charge }) end
  return descriptor(status.GREEN, { "gb-status.catapult-ready", charge, facts.shot_seconds })
end

--- A contract chest: {needs = {{name, count}...}}, the items its force's active incoming contracts
--- still need, in the order the chest hands them over.
function status.contract_chest(facts)
  local needs = facts.needs
  if #needs == 0 then return descriptor(status.GREEN, { "gb-status.contract-chest-idle" }) end
  local list = { "" }
  for i = 1, math.min(#needs, status.MAX_LISTED) do
    if i > 1 then list[#list + 1] = ", " end
    list[#list + 1] = "[item=" .. needs[i].name .. "] " .. needs[i].count
  end
  local shown = #needs > status.MAX_LISTED and { "gb-status.contract-chest-more", list, #needs - status.MAX_LISTED }
    or list
  return descriptor(status.GREEN, { "gb-status.contract-chest-needs", shown })
end

--- A rental assembler: {state ("idle", "offered" or "rented"), id (its contract)}. A rented machine
--- keeps the game's own status (nil), which tells what the crafting needs.
function status.rental(facts)
  if facts.state == "offered" then return descriptor(status.YELLOW, { "gb-status.rental-offered", facts.id }) end
  if facts.state == "rented" then return nil end
  return descriptor(status.GREEN, { "gb-status.rental-idle" })
end

-- Whether two labels (LocalisedStrings: strings, numbers or nested arrays) are equal.
local function same_label(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if not same_label(a[i], b[i]) then return false end
  end
  return true
end

--- Whether two descriptors show the same thing (either may be nil: the game's own status), so that
--- an unchanged status is not written again.
function status.same(a, b)
  if a == nil or b == nil then return a == b end
  return a.diode == b.diode and a.alert == b.alert and same_label(a.label, b.label)
end

--- Buildings to refresh per pass so that `count` of them are each refreshed once every `passes`
--- passes, at most `max_visits` per pass (beyond, a cycle takes longer).
function status.visits(count, passes, max_visits)
  return math.min(max_visits, math.ceil(count / passes))
end

return status
