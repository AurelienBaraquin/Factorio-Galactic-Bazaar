-- Status of every building of the mod (#106): each gets a custom status (diode and text, shown by the
-- game where it shows an entity's status) from scripts/core/entity_status.lua, and a rendered alert
-- (icon, with a short text in alt mode) while something stops it: no hub of its force in range, its
-- hub without power, or no power of its own. The buildings are kept in one list, in step with build
-- and destroy events; every PASS_TICKS the next ones are refreshed, at most MAX_VISITS per pass, so
-- that each is refreshed about once every CYCLE_TICKS and no tick does more. A building is also
-- refreshed when it is built. A status is written only when it changed. Each hub's modules of its
-- force are counted as they are refreshed, and the count shown from the next cycle on. The costly
-- reads (a hub's delivery tier and bays' fuel, a force's contract needs and price period, a hub's
-- vaults) are made once per hub or force and cycle, and a pass stops after MAX_COSTLY_READS of them.
--
-- State lives in storage.entity_status: the list (`units` and `kinds`, parallel arrays, and `index`
-- {[unit_number] = position}), the `cursor`, the hubs' module counts (`counts`, last cycle's;
-- `pending`, this cycle's), the hubs' modules by unit number (`members`, last cycle's; `joining`, this
-- cycle's: {[hub unit_number] = {[unit_number] = true}}, a hint re-checked on read), the status each
-- building shows (`shown`: {[unit_number] = descriptor},
-- false for the game's own status), the cycle's costly reads (`facts`: {[field] = {[hub or force
-- index] = value}}) and the alerts drawn (`alerts`: {[unit_number] = {alert, force_index, sprite,
-- text}}, render object ids). Every handler creates it when a save predates it.
local catapult = require("scripts.catapult")
local contracts = require("scripts.contracts")
local contracts_core = require("scripts.core.contracts")
local core = require("scripts.core.entity_status")
local docking_bay = require("scripts.docking_bay")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local power = require("scripts.power")
local telecom = require("scripts.telecom")
local teleporter = require("scripts.teleporter")
local vaults = require("scripts.vaults")
local warehouses = require("scripts.warehouses")

local entity_status = {}

entity_status.PASS_TICKS = 10
entity_status.CYCLE_TICKS = 300
entity_status.PASSES = entity_status.CYCLE_TICKS / entity_status.PASS_TICKS
entity_status.MAX_VISITS = 8
entity_status.MAX_COSTLY_READS = 2
entity_status.ALERT_SPRITES = {
  [core.NO_HUB] = "utility/warning_icon",
  [core.HUB_UNPOWERED] = "utility/electricity_icon",
  [core.UNPOWERED] = "utility/electricity_icon",
}

local ALERT_COLOR = { 1, 0.45, 0.35 }
local MJ = 1e6

-- A costly read made once per hub or force and cycle: kept in the cycle's facts, and counted in the
-- `work` of the pass ({facts, costly}).
local function cached(work, field, key, read)
  local values = work.facts[field]
  if not values then
    values = {}
    work.facts[field] = values
  end
  local value = values[key]
  if value == nil then
    value = read(key)
    values[key] = value
    work.costly = work.costly + 1
  end
  return value
end

local function tier_of(hub_unit_number) return freight.tier(hub_unit_number).name end
local function fueled(hub_unit_number)
  return docking_bay.fuel(hub_unit_number, docking_bay.FUEL_MJ_PER_SHIPMENT) >= docking_bay.FUEL_MJ_PER_SHIPMENT
end

-- "none" (no hub of the module's force), "unpowered" or "powered": the hub a module is attached to.
local function hub_state(module)
  local hub = module.hub and hubs.get(module.hub)
  if not (hub and hub.force_index == module.entity.force_index) then return "none" end
  return hubs.has_power(hub) and "powered" or "unpowered"
end

-- Each kind of building: where its modules live, the costly reads its status may make (see `cached`)
-- and how its status is read. `describe(module, hub,
-- tick, work)` returns a descriptor (nil: the game's own status); `hub` is the module's hub state
-- (nil for a hub); `work` carries the cycle's costly reads (see `cached`).
local KINDS = {
  {
    name = "hub",
    costly = 1,
    modules = function() return storage.hubs end,
    describe = function(module, _, _, work)
      local unit_number = module.entity.unit_number
      return core.hub({
        powered = hubs.has_power(module.entity), modules = storage.entity_status.counts[unit_number] or 0,
        queued = freight.queued(unit_number), tier = cached(work, "tiers", unit_number, tier_of),
      })
    end,
  },
  {
    name = "cargo",
    costly = 0,
    modules = function() return storage.cargo.modules end,
    describe = function(module, hub)
      if module.kind == "export" then
        local empty = module.entity.get_inventory(defines.inventory.chest).is_empty()
        return core.module(hub, true, core.export_chest({ empty = empty, held = module.held }))
      end
      return core.module(hub, false, core.import_chest({ queued = module.hub and freight.queued(module.hub) or 0 }))
    end,
  },
  {
    name = "manifold",
    costly = 0,
    modules = function() return storage.manifold.modules end,
    describe = function(module, hub)
      local fluid = module.entity.get_fluid(1)
      local name = fluid and fluid.amount > 0 and fluid.name or nil
      if module.kind == "export" then
        return core.module(hub, true, core.fluid_export({ fluid = name, held = module.held }))
      end
      return core.module(hub, false, core.fluid_import({ fluid = name }))
    end,
  },
  {
    name = "power",
    costly = 0,
    modules = function() return storage.power.modules end,
    describe = function(module, hub)
      local settled = power.settlements()[module.entity.force_index]
      local last = settled and {
        units = settled[module.kind], held = settled.export_held, short = settled.import_short,
      }
      return core.module(hub, true, core.power({ direction = module.kind, last = last }))
    end,
  },
  {
    name = "price",
    costly = 1,
    modules = function() return storage.price_signals.modules end,
    describe = function(module, hub, _, work)
      local force_index = module.entity.force_index
      local snapshot = storage.price_signals.snapshots[force_index]
      return core.module(hub, true, core.price_combinator({
        side = module.side, ready = snapshot ~= nil, count = snapshot and #snapshot[module.side],
        period_seconds = cached(work, "periods", force_index, function()
          return telecom.period(module.entity.force) / 60
        end),
      }))
    end,
  },
  {
    name = "order",
    costly = 0,
    modules = function() return storage.circuit_orders.modules end,
    describe = function(module, hub)
      return core.module(hub, true, core.order_combinator({ last = module.last }))
    end,
  },
  {
    name = "docking-bay",
    costly = 2,
    modules = function() return storage.docking_bays.modules end,
    describe = function(module, hub, _, work)
      local attached = hub ~= "none"
      return core.module(hub, false, core.docking_bay({
        fuel_mj = docking_bay.bay_fuel(module), shipment_mj = docking_bay.FUEL_MJ_PER_SHIPMENT,
        fueled = attached and cached(work, "fueled", module.hub, fueled),
        tier = attached and cached(work, "tiers", module.hub, tier_of) or "capsule",
      }))
    end,
  },
  {
    name = "teleporter",
    costly = 0,
    modules = function() return storage.teleporters.modules end,
    describe = function(module, hub)
      local entity = module.entity
      return core.module(hub, false, core.teleporter({
        powered = teleporter.is_powered(entity), charge = entity.energy / entity.electric_buffer_size,
      }))
    end,
  },
  {
    name = "catapult",
    costly = 0,
    modules = function() return storage.catapults.modules end,
    describe = function(module, hub)
      local capacitor = module.capacitor
      local buffer = capacitor and capacitor.valid and capacitor.electric_buffer_size or 0
      local charge = buffer > 0 and capacitor.energy / buffer or 0
      return core.module(hub, true, core.catapult({
        charge = charge, shot_share = buffer > 0 and math.min(1, catapult.SHOT_MJ * MJ / buffer) or 1,
        empty = module.entity.get_inventory(defines.inventory.chest).is_empty(), held = module.held,
        shot_seconds = catapult.SHOT_TICKS / 60,
      }))
    end,
  },
  {
    name = "contract-chest",
    costly = 1,
    modules = function() return storage.incoming_contracts.chests end,
    describe = function(module, hub, _, work)
      local needs = cached(work, "needs", module.entity.force_index, incoming.needs)
      return core.module(hub, false, core.contract_chest({ needs = needs }))
    end,
  },
  {
    name = "rental",
    costly = 0,
    modules = function() return storage.rentals.machines end,
    describe = function(module, hub)
      local contract = module.contract and contracts.get(module.entity.force_index, module.contract)
      local facts = { state = "idle" }
      if contract and contract.state == contracts_core.OFFERED then
        facts = { state = "offered", id = contract.id }
      elseif contract and contract.state == contracts_core.ACTIVE then
        facts = { state = "rented", id = contract.id }
      end
      return core.module(hub, false, core.rental(facts))
    end,
  },
  {
    name = "vault-uplink",
    costly = 1,
    modules = vaults.uplinks,
    describe = function(module, hub, _, work)
      local count = hub ~= "none" and cached(work, "vaults", module.hub, function(hub_unit_number)
        return vaults.count_at(module.entity.force_index, hub_unit_number)
      end) or 0
      return core.module(hub, false, core.vault_uplink({ vaults = count, held = module.held }))
    end,
  },
  {
    name = "warehouse",
    costly = 0,
    modules = warehouses.chests,
    describe = function(module, hub)
      local contract = module.contract and contracts.get(module.entity.force_index, module.contract)
      local facts = { state = "idle" }
      if contract and contract.state == contracts_core.OFFERED then
        facts = { state = "offered", id = contract.id }
      elseif contract and contract.state == contracts_core.ACTIVE then
        facts = { state = "rented", id = contract.id }
      end
      return core.module(hub, false, core.warehouse(facts))
    end,
  },
}
local KIND_BY_NAME = {}
local KIND_RANK = {}
for rank, kind in ipairs(KINDS) do KIND_BY_NAME[kind.name], KIND_RANK[kind.name] = kind, rank end

local DIODES = {
  [core.GREEN] = defines.entity_status_diode.green,
  [core.YELLOW] = defines.entity_status_diode.yellow,
  [core.RED] = defines.entity_status_diode.red,
}

local function destroy_alert(drawn)
  for _, id in ipairs({ drawn.sprite, drawn.text }) do
    local object = rendering.get_object_by_id(id)
    if object then object.destroy() end
  end
end

-- Appends a building to the list, once.
local function add(state, unit_number, kind_name)
  if state.index[unit_number] then return end
  local n = #state.units + 1
  state.units[n], state.kinds[n], state.index[unit_number] = unit_number, kind_name, n
end

-- Swaps two positions of the list.
local function swap(state, a, b)
  if a == b then return end
  local units, kinds = state.units, state.kinds
  units[a], units[b], kinds[a], kinds[b] = units[b], units[a], kinds[b], kinds[a]
  state.index[units[a]], state.index[units[b]] = a, b
end

-- Removes a building from the list in O(1) (the last one takes its place), with its status and alert.
-- One already refreshed this cycle (before the cursor) first trades places with the last one
-- refreshed, and the cursor steps back onto the entry that replaces it, so no building is skipped.
local function remove(state, unit_number)
  local position = state.index[unit_number]
  if position then
    if position < state.cursor then
      swap(state, position, state.cursor - 1)
      position = state.cursor - 1
      state.cursor = position
    end
    local last = #state.units
    swap(state, position, last)
    state.units[last], state.kinds[last], state.index[unit_number] = nil, nil, nil
  end
  state.shown[unit_number] = nil
  local drawn = state.alerts[unit_number]
  if drawn then
    destroy_alert(drawn)
    state.alerts[unit_number] = nil
  end
end

-- Records that a module is attached to its hub (of its force) in this cycle's `joining`.
local function join(state, module, unit_number)
  local members = state.joining[module.hub]
  if not members then
    members = {}
    state.joining[module.hub] = members
  end
  members[unit_number] = true
end

-- Lists every building of every registry (on init and configuration change, or once in a save that
-- predates the list), and the modules of each hub; alerts of buildings no longer listed go.
local function list_all(state)
  state.units, state.kinds, state.index, state.members, state.joining = {}, {}, {}, {}, {}
  for _, kind in ipairs(KINDS) do
    for unit_number, module in pairs(kind.modules()) do
      if module.entity.valid then
        add(state, unit_number, kind.name)
        if kind.name ~= "hub" and hub_state(module) ~= "none" then join(state, module, unit_number) end
      end
    end
  end
  for unit_number, drawn in pairs(state.alerts) do
    if not state.index[unit_number] then
      destroy_alert(drawn)
      state.alerts[unit_number] = nil
    end
  end
end

-- The state, created (and the buildings listed) when the save predates it.
local function state_of()
  local state = storage.entity_status
  if state and state.index then
    -- A save from 0.1.32 or older lacks the hubs' modules until its configuration change lists them.
    if not state.joining then state.members, state.joining = {}, {} end
    return state
  end
  state = state or {}
  state.alerts, state.counts, state.pending, state.shown = state.alerts or {}, state.counts or {}, {}, {}
  state.facts = {}
  state.cursor = 1
  storage.entity_status = state
  list_all(state)
  return state
end

-- Draws `alert` on the entity (nil: none), replacing what was drawn when it changed or the entity
-- changed force (an alert is only shown to the entity's force).
local function set_alert(state, entity, alert)
  local unit_number = entity.unit_number
  local drawn = state.alerts[unit_number]
  if drawn and drawn.alert == alert and drawn.force_index == entity.force_index then return end
  if drawn then destroy_alert(drawn) end
  state.alerts[unit_number] = nil
  if not alert then return end
  local forces = { entity.force }
  local sprite = rendering.draw_sprite({
    sprite = entity_status.ALERT_SPRITES[alert], target = entity, surface = entity.surface, forces = forces,
    x_scale = 0.5, y_scale = 0.5,
  })
  local text = rendering.draw_text({
    text = { "gb-status.alert-" .. alert }, surface = entity.surface, forces = forces, color = ALERT_COLOR,
    target = { entity = entity, offset = { 0, entity.prototype.tile_height / 2 - 0.3 } },
    scale = 0.8, alignment = "center", only_in_alt_mode = true,
  })
  state.alerts[unit_number] = { alert = alert, force_index = entity.force_index, sprite = sprite.id, text = text.id }
end

-- Shows a module's status on its entity, writing it only when it changed. Returns the module's hub
-- state (nil for a hub or an invalid entity).
local function refresh(state, kind, module, tick, work)
  local entity = module.entity
  if not entity.valid then return nil end
  local hub = kind.name ~= "hub" and hub_state(module) or nil
  local descriptor = kind.describe(module, hub, tick, work)
  local unit_number = entity.unit_number
  local shown = state.shown[unit_number]
  if shown == nil or not core.same(descriptor, shown or nil) then
    entity.custom_status = descriptor and { diode = DIODES[descriptor.diode], label = descriptor.label } or nil
    state.shown[unit_number] = descriptor or false
  end
  set_alert(state, entity, descriptor and descriptor.alert)
  return hub
end

--- on_init and on_configuration_changed, after every module's init: creates the state, lists every
--- building again (registries may have dropped some) and has every status written again.
function entity_status.init()
  local existed = storage.entity_status and storage.entity_status.index
  local state = state_of()
  if not existed then return end
  state.shown, state.pending, state.facts, state.cursor = {}, {}, {}, 1
  list_all(state)
end

--- on_nth_tick(PASS_TICKS): refreshes the next buildings of the list; past its end, a new cycle
--- starts and the module counts of the cycle that ended are shown.
function entity_status.on_pass_tick(event)
  local state = state_of()
  local work = { facts = state.facts, costly = 0 }
  for _ = 1, core.visits(#state.units, entity_status.PASSES, entity_status.MAX_VISITS) do
    if state.cursor > #state.units then
      state.cursor, state.counts, state.pending, state.facts = 1, state.pending, {}, {}
      state.members, state.joining = state.joining, {}
      work.facts = state.facts
    end
    local index = state.cursor
    local unit_number = state.units[index]
    if not unit_number then return end
    local kind = KIND_BY_NAME[state.kinds[index]]
    -- Each kind reserves the costly reads it may make, so that a pass never makes more than the cap.
    if work.costly + kind.costly > entity_status.MAX_COSTLY_READS then return end
    local module = kind.modules()[unit_number]
    if module then
      state.cursor = index + 1
      local hub = refresh(state, kind, module, event.tick, work)
      if hub and hub ~= "none" then
        state.pending[module.hub] = (state.pending[module.hub] or 0) + 1
        join(state, module, unit_number)
      end
    else
      remove(state, unit_number)
    end
  end
end

--- A building of the mod was built (and registered by its module): it joins the list and its status
--- is shown at once.
function entity_status.on_built(entity)
  local state = state_of()
  local unit_number = entity.unit_number
  for _, kind in ipairs(KINDS) do
    local module = kind.modules()[unit_number]
    if module then
      add(state, unit_number, kind.name)
      local hub = refresh(state, kind, module, game.tick, { facts = {}, costly = 0 })
      if hub and hub ~= "none" then join(state, module, unit_number) end
      return
    end
  end
end

--- on_object_destroyed: a destroyed building leaves the list, with its alert.
function entity_status.forget(unit_number)
  remove(state_of(), unit_number)
end

--- The status a building shows, as last written: a descriptor, false for the game's own, nil before
--- its first refresh (read only).
function entity_status.shown(unit_number)
  return state_of().shown[unit_number]
end

--- Calls `visit(unit_number, rank, entity, descriptor)` once for each building of force `force_index`
--- attached to a hub, for the Logistics tab (`rank`: its kind's order; `descriptor`: see `shown`), in no
--- order, making no table per building. Reads the modules the last and the current cycle found
--- attached to that hub (a module attached since shows once a pass or its construction refreshes it),
--- each checked again: listed, still attached to the hub, valid and of the force.
function entity_status.each_module_of(hub_unit_number, force_index, visit)
  local state = state_of()
  local members, joining = state.members[hub_unit_number], state.joining[hub_unit_number]
  for _, cycle in ipairs({ members or {}, joining or {} }) do
    for unit_number in pairs(cycle) do
      -- A building found by both cycles is visited from the last one only.
      if cycle == members or not (members and members[unit_number]) then
        local position = state.index[unit_number]
        local kind = position and KIND_BY_NAME[state.kinds[position]]
        local module = kind and kind.modules()[unit_number]
        local entity = module and module.entity
        if module and module.hub == hub_unit_number and entity.valid and entity.force_index == force_index then
          visit(unit_number, KIND_RANK[kind.name], entity, state.shown[unit_number])
        end
      end
    end
  end
end

return entity_status
