-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local bazaar_gui = require("scripts.bazaar_gui")
local cargo = require("scripts.cargo")
local catapult = require("scripts.catapult")
local forces = require("scripts.forces")
local finance = require("scripts.finance")
local docking_bay = require("scripts.docking_bay")
local entity_status = require("scripts.entity_status")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local insolvency = require("scripts.insolvency")
local loans = require("scripts.loans")
local manifold = require("scripts.manifold")
local market_events = require("scripts.market_events")
local notifications = require("scripts.notifications")
local circuit_orders = require("scripts.circuit_orders")
local contracts = require("scripts.contracts")
local power = require("scripts.power")
local teleporter = require("scripts.teleporter")
local price_signals = require("scripts.price_signals")
local concessions = require("scripts.concessions")
local planets = require("scripts.planets")
local rental = require("scripts.rental")
local value_overrides = require("scripts.value_overrides")
local vaults = require("scripts.vaults")
local warehouses = require("scripts.warehouses")
-- The tabs of the Galactic Bazaar window register themselves with it when loaded, in this order.
require("scripts.overview_gui")
require("scripts.market_gui")
require("scripts.market_events_gui")
require("scripts.logistics_gui")
require("scripts.contracts_gui")
require("scripts.planets_gui")
require("scripts.statement_gui")

local function init()
  forces.init()
  finance.init()
  notifications.init()
  local dropped = planets.init()
  value_overrides.rebuild()
  market_events.init()
  hubs.init()
  cargo.init()
  manifold.init()
  freight.init()
  docking_bay.init()
  teleporter.init()
  catapult.init()
  power.init()
  price_signals.init()
  circuit_orders.init()
  incoming.init()
  rental.init()
  warehouses.init()
  vaults.init()
  concessions.init(dropped)
  entity_status.init()
  bazaar_gui.init()
end

remote.add_interface("galactic-bazaar", value_overrides.REMOTE)

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event({ defines.events.on_research_finished, defines.events.on_research_reversed }, function(event)
  finance.on_research_changed(event)
  bazaar_gui.on_research_changed(event)
end)
script.on_event({ defines.events.on_force_reset, defines.events.on_technology_effects_reset }, function(event)
  finance.on_force_event(event)
  bazaar_gui.on_force_event(event)
end)
script.on_event(defines.events.on_forces_merging, function(event)
  freight.on_forces_merging(event)
  forces.on_forces_merging(event)
end)
script.on_event(defines.events.on_forces_merged, function(event)
  cargo.on_forces_merged(event)
  power.on_forces_merged(event)
  manifold.on_forces_merged(event)
  docking_bay.on_forces_merged(event)
  teleporter.on_forces_merged(event)
  catapult.on_forces_merged(event)
  incoming.on_forces_merged(event)
  rental.on_forces_merged(event)
  warehouses.reattach()
  vaults.on_forces_merged(event)
  planets.on_forces_merged(event)
  concessions.on_forces_merged(event)
  price_signals.on_forces_merged(event)
  circuit_orders.on_forces_merged(event)
  notifications.on_forces_merged(event)
end)

-- Every way an entity can appear, filtered to the mod's buildings.
local BUILT_EVENTS = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_entity_cloned,
}
local BUILDING_FILTER = {
  { filter = "name", name = hubs.NAME }, { filter = "name", name = circuit_orders.NAME, mode = "or" },
  { filter = "name", name = docking_bay.NAME, mode = "or" }, { filter = "name", name = teleporter.NAME, mode = "or" },
  { filter = "name", name = catapult.NAME, mode = "or" }, { filter = "name", name = incoming.CHEST, mode = "or" },
  { filter = "name", name = rental.NAME, mode = "or" }, { filter = "name", name = warehouses.NAME, mode = "or" },
  { filter = "name", name = vaults.UPLINK, mode = "or" },
}
for _, kinds in ipairs({ cargo.KINDS, power.KINDS, price_signals.KINDS, manifold.KINDS }) do
  for name in pairs(kinds) do
    table.insert(BUILDING_FILTER, { filter = "name", name = name, mode = "or" })
  end
end

local function on_built(event)
  local entity = event.entity or event.destination
  if not (entity and entity.valid) then return end
  if hubs.on_built(entity) then
    cargo.on_hub_built(entity)
    power.on_hub_built(entity)
    manifold.on_hub_built(entity)
    docking_bay.on_hub_built(entity)
    teleporter.on_hub_built(entity)
    catapult.on_hub_built(entity)
    incoming.reattach()
    rental.reattach()
    warehouses.reattach()
    vaults.reattach()
    price_signals.on_hub_built(entity)
    circuit_orders.on_hub_built(entity)
  elseif not (power.on_built(entity) or price_signals.on_built(entity) or circuit_orders.on_built(entity)
    or manifold.on_built(entity) or docking_bay.on_built(entity) or teleporter.on_built(entity)
    or catapult.on_built(entity) or incoming.on_built(entity) or rental.on_built(entity)
    or warehouses.on_built(entity) or vaults.on_built(entity)) then
    cargo.on_built(entity)
  end
  entity_status.on_built(entity)
end

for _, event in ipairs(BUILT_EVENTS) do
  script.on_event(event, on_built, BUILDING_FILTER)
end

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type ~= defines.target_type.entity then return end
  entity_status.forget(event.useful_id)
  if hubs.forget(event.useful_id) then
    cargo.on_hub_removed(event.useful_id)
    power.on_hub_removed(event.useful_id)
    manifold.on_hub_removed(event.useful_id)
    docking_bay.on_hub_removed(event.useful_id)
    teleporter.on_hub_removed(event.useful_id)
    catapult.on_hub_removed(event.useful_id)
    incoming.reattach()
    rental.reattach()
    warehouses.reattach()
    vaults.reattach()
    price_signals.on_hub_removed(event.useful_id)
    circuit_orders.on_hub_removed(event.useful_id)
    freight.on_hub_removed(event.useful_id)
    bazaar_gui.on_hub_removed(event.useful_id)
  elseif not (power.forget(event.useful_id) or price_signals.forget(event.useful_id)
    or circuit_orders.forget(event.useful_id) or manifold.forget(event.useful_id)
    or docking_bay.forget(event.useful_id) or teleporter.forget(event.useful_id)
    or catapult.forget(event.useful_id) or incoming.forget(event.useful_id) or rental.forget(event.useful_id)
    or warehouses.forget(event.useful_id) or vaults.forget(event.useful_id)) then
    cargo.forget(event.useful_id)
  end
end)

-- One handler per tick interval is kept by Factorio, so handlers sharing an interval are composed.
local periodic = {}
local function every(ticks, handler)
  periodic[ticks] = periodic[ticks] or {}
  table.insert(periodic[ticks], handler)
end
every(cargo.EXPORT_INTERVAL, cargo.on_export_tick)
every(bazaar_gui.SLOT_TICKS, bazaar_gui.on_refresh_tick)
every(freight.UNLOAD_INTERVAL, freight.on_unload_tick)
every(power.SETTLE_TICKS, power.on_settle_tick)
every(manifold.EXPORT_INTERVAL, manifold.on_export_tick)
every(catapult.PASS_TICKS, catapult.on_pass_tick)
every(contracts.SETTLE_TICKS, contracts.on_settle_tick)
every(forces.INTEREST_TICKS, forces.on_interest_tick)
-- A self-heal of the mod buttons, like the overdraft levels: some research changes raise no event.
every(forces.INTEREST_TICKS, bazaar_gui.sync_buttons)
every(loans.COLLECT_TICKS, loans.on_collect_tick)
-- After the arrears collection, so that arrears the funds can cover are paid before the check.
every(insolvency.CHECK_TICKS, insolvency.on_check_tick)
every(incoming.OFFER_TICKS, incoming.on_offer_tick)
every(incoming.COLLECT_TICKS, incoming.on_collect_tick)
every(rental.OFFER_TICKS, rental.on_offer_tick)
every(rental.SERVICE_TICKS, rental.on_service_tick)
every(concessions.SWEEP_TICKS, concessions.on_sweep_tick)
every(warehouses.OFFER_TICKS, warehouses.on_offer_tick)
every(warehouses.SERVICE_TICKS, warehouses.on_service_tick)
every(vaults.UPLINK_TICKS, vaults.on_uplink_tick)
every(vaults.SWEEP_TICKS, vaults.on_sweep_tick)
every(price_signals.PASS_TICKS, price_signals.on_pass_tick)
every(circuit_orders.PASS_TICKS, circuit_orders.on_pass_tick)
every(entity_status.PASS_TICKS, entity_status.on_pass_tick)
every(market_events.PASS_TICKS, market_events.on_pass_tick)
for ticks, handlers in pairs(periodic) do
  script.on_nth_tick(ticks, function(event)
    for _, handler in ipairs(handlers) do handler(event) end
  end)
end

script.on_event(bazaar_gui.HUB_INPUT, bazaar_gui.on_hub_input)
script.on_event(bazaar_gui.TOGGLE_INPUT, bazaar_gui.on_toggle_input)
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  price_signals.on_settings_pasted(event)
  circuit_orders.on_settings_pasted(event)
  rental.on_settings_pasted(event)
end)
script.on_event(bazaar_gui.GUI_EVENTS, bazaar_gui.on_gui_input)
script.on_event(defines.events.on_gui_selected_tab_changed, bazaar_gui.on_gui_selected_tab_changed)
script.on_event(defines.events.on_gui_closed, bazaar_gui.on_gui_closed)
script.on_event(defines.events.on_player_created, bazaar_gui.on_player_created)
script.on_event({
  defines.events.on_player_left_game, defines.events.on_player_changed_force, defines.events.on_player_removed,
}, bazaar_gui.on_player_event)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "tests/forces", "tests/overdraft", "tests/contracts", "tests/loans", "tests/finance", "tests/insolvency",
      "tests/incoming_contracts",
      "tests/rental", "tests/storage_rental", "tests/planets",
      "tests/concessions", "tests/recipe_graph", "tests/pricing", "tests/overrides", "tests/quality",
      "tests/market", "tests/hubs", "tests/cargo", "tests/catapult", "tests/manifold", "tests/freight",
      "tests/docking_bay", "tests/teleporter", "tests/power", "tests/price_signals", "tests/circuit_orders",
      "tests/telecom", "tests/technologies", "tests/market_gui", "tests/item_detail", "tests/notifications",
      "tests/entity_status", "tests/bazaar_gui", "tests/logistics_gui",
      "tests/statement_gui", "tests/explanations", "tests/market_events", "tests/balance" },
    { load_luassert = true }
  )
end

-- The in-game check of tools/ingame/run.py, in its sandboxed client only (docs/ingame-check.md).
if script.active_mods["gb-ingame-check"] then require("tests.ingame_check.init") end
