-- Runtime stage: registers every event handler of the mod. Factorio keeps one handler per event
-- per mod, so handlers from several modules are composed here, never registered in the modules.
local cargo = require("scripts.cargo")
local forces = require("scripts.forces")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local market_gui = require("scripts.market_gui")
local circuit_orders = require("scripts.circuit_orders")
local power = require("scripts.power")
local price_signals = require("scripts.price_signals")
local value_overrides = require("scripts.value_overrides")

local function init()
  forces.init()
  value_overrides.rebuild()
  hubs.init()
  cargo.init()
  freight.init()
  power.init()
  price_signals.init()
  circuit_orders.init()
  market_gui.init()
end

remote.add_interface("galactic-bazaar", value_overrides.REMOTE)

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_force_created, forces.on_force_created)
script.on_event(defines.events.on_forces_merging, function(event)
  freight.on_forces_merging(event)
  forces.on_forces_merging(event)
end)
script.on_event(defines.events.on_forces_merged, function(event)
  cargo.on_forces_merged(event)
  power.on_forces_merged(event)
  price_signals.on_forces_merged(event)
  circuit_orders.on_forces_merged(event)
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
}
for _, kinds in ipairs({ cargo.KINDS, power.KINDS, price_signals.KINDS }) do
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
    price_signals.on_hub_built(entity)
    circuit_orders.on_hub_built(entity)
  elseif not (power.on_built(entity) or price_signals.on_built(entity) or circuit_orders.on_built(entity)) then
    cargo.on_built(entity)
  end
end

for _, event in ipairs(BUILT_EVENTS) do
  script.on_event(event, on_built, BUILDING_FILTER)
end

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type ~= defines.target_type.entity then return end
  if hubs.forget(event.useful_id) then
    cargo.on_hub_removed(event.useful_id)
    power.on_hub_removed(event.useful_id)
    price_signals.on_hub_removed(event.useful_id)
    circuit_orders.on_hub_removed(event.useful_id)
    freight.on_hub_removed(event.useful_id)
    market_gui.on_hub_removed(event.useful_id)
  elseif not (power.forget(event.useful_id) or price_signals.forget(event.useful_id)
    or circuit_orders.forget(event.useful_id)) then
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
every(market_gui.SLOT_TICKS, market_gui.on_refresh_tick)
every(freight.UNLOAD_INTERVAL, freight.on_unload_tick)
every(power.SETTLE_TICKS, power.on_settle_tick)
every(price_signals.PASS_TICKS, price_signals.on_pass_tick)
every(circuit_orders.PASS_TICKS, circuit_orders.on_pass_tick)
for ticks, handlers in pairs(periodic) do
  script.on_nth_tick(ticks, function(event)
    for _, handler in ipairs(handlers) do handler(event) end
  end)
end

script.on_event(market_gui.INPUT, market_gui.on_open_input)
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  price_signals.on_settings_pasted(event)
  circuit_orders.on_settings_pasted(event)
end)
script.on_event(defines.events.on_gui_click, market_gui.on_gui_click)
script.on_event(defines.events.on_gui_text_changed, market_gui.on_gui_text_changed)
script.on_event(defines.events.on_gui_closed, market_gui.on_gui_closed)
script.on_event({
  defines.events.on_player_left_game, defines.events.on_player_changed_force, defines.events.on_player_removed,
}, market_gui.on_player_event)

if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")(
    { "tests/forces", "tests/recipe_graph", "tests/pricing", "tests/overrides", "tests/quality", "tests/market",
      "tests/hubs", "tests/cargo", "tests/freight", "tests/power", "tests/price_signals", "tests/circuit_orders",
      "tests/telecom", "tests/market_gui" },
    { load_luassert = true }
  )
end
