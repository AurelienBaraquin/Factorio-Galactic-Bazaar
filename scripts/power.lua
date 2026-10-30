-- The power module (ADR-0009): substations that sell the network's surplus electricity to the
-- market and buy what it lacks. Each works through the nearest powered hub of its force in range
-- (ADR-0005): attached when built, when a hub appears or disappears and when forces merge, and
-- searched again at a settlement only when its hub can no longer trade. Every SETTLE_TICKS,
-- the export substations' buffers are sold and the import substations' buffers refilled, one trade
-- per force and direction, journaled as one entry per direction and minute. The buffer size, set
-- from the force's research level, caps the throughput. State lives in storage.power.
local hubs = require("scripts.hubs")
local market = require("scripts.market")
local settlement = require("scripts.core.power_settlement")

local power = {}

power.KINDS = { ["gb-power-export"] = "export", ["gb-power-import"] = "import" }
power.HUB_RANGE = 10
power.SETTLE_TICKS = 300
-- An export substation sells while electricity fetches at least this fraction of its base value.
power.MIN_PRICE_RATIO = 0.5
-- Throughput per substation in watts at each research level; level 1 comes with the substations.
power.LEVEL_WATTS = { 10e6, 40e6 }
power.LEVEL_TECHNOLOGIES = { "gb-power-trading", "gb-power-trading-2" }

-- Ticks over which a force's power trades share one journal entry per direction.
power.JOURNAL_MERGE_TICKS = 3600

local KIND, NAME = "energy", "electricity"
local JOULES_PER_UNIT = 1e6

-- An electric-energy-interface makes or destroys energy by itself when these are set (a blueprint
-- or another mod could set them): the substations' only energy is what the network exchanges.
local function neutralise(entity)
  if entity.power_production ~= 0 then entity.power_production = 0 end
  if entity.power_usage ~= 0 then entity.power_usage = 0 end
end

--- on_init and on_configuration_changed: creates the state, drops substations that no longer exist
--- and re-attaches the others (hubs may have been dropped, or the range changed).
function power.init()
  storage.power = storage.power or { modules = {} }
  local gone = {}
  for unit_number, module in pairs(storage.power.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do storage.power.modules[unit_number] = nil end
  for _, module in pairs(storage.power.modules) do
    module.hub = hubs.nearest(module.entity, power.HUB_RANGE)
  end
end

--- Registers a newly built substation; returns true when the entity was one.
function power.on_built(entity)
  local kind = power.KINDS[entity.name]
  if not kind then return false end
  neutralise(entity)
  -- A new substation starts empty; a clone would otherwise copy energy that could then be sold.
  entity.energy = 0
  storage.power.modules[entity.unit_number] = {
    entity = entity, kind = kind, hub = hubs.nearest(entity, power.HUB_RANGE),
  }
  script.register_on_object_destroyed(entity)
  return true
end

local function attach(module)
  hubs.attach(module, power.HUB_RANGE)
end

--- A hub appeared: substations in its range move to it if it is now their nearest hub.
function power.on_hub_built(hub)
  local names = {}
  for name in pairs(power.KINDS) do names[#names + 1] = name end
  local nearby = hub.surface.find_entities_filtered({
    name = names, force = hub.force, position = hub.position, radius = power.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.power.modules[entity.unit_number]
    if module then attach(module) end
  end
end

--- A hub disappeared: its substations look for another hub in range.
function power.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.power.modules) do
    if module.hub == hub_unit_number then attach(module) end
  end
end

--- on_forces_merged: substations now belong to the merged force and may use its hubs.
function power.on_forces_merged()
  for _, module in pairs(storage.power.modules) do attach(module) end
end

--- Forgets a destroyed substation; returns true when the unit number was one.
function power.forget(unit_number)
  if not storage.power.modules[unit_number] then return false end
  storage.power.modules[unit_number] = nil
  return true
end

--- Throughput in watts of a force's substations: the highest research level it has.
function power.watts(force)
  local watts = power.LEVEL_WATTS[1]
  for level, name in ipairs(power.LEVEL_TECHNOLOGIES) do
    local technology = force.technologies[name]
    if technology and technology.researched then watts = power.LEVEL_WATTS[level] end
  end
  return watts
end

-- The substations that can trade now, grouped by force and direction, neutralised and with their
-- buffers sized for the force's level.
local function trading_groups()
  local groups = {}
  local buffers = {}
  for _, module in pairs(storage.power.modules) do
    local entity = module.entity
    if entity.valid and hubs.trading_hub(module, power.HUB_RANGE) then
      neutralise(entity)
      local force = entity.force
      buffers[force.index] = buffers[force.index] or power.watts(force) * power.SETTLE_TICKS / 60
      if entity.electric_buffer_size ~= buffers[force.index] then
        entity.electric_buffer_size = buffers[force.index]
      end
      groups[force.index] = groups[force.index] or { export = {}, import = {} }
      table.insert(groups[force.index][module.kind], entity)
    end
  end
  return groups
end

-- Sells what the export substations of a force absorbed, as far as the price floor allows; each
-- keeps the unsold share of its energy.
local function settle_exports(force_index, entities)
  local joules = 0
  for _, entity in ipairs(entities) do joules = joules + entity.energy end
  local sellable = joules > 0 and market.sellable(force_index, KIND, NAME, power.MIN_PRICE_RATIO) or 0
  local units, kept = settlement.export(joules, sellable, JOULES_PER_UNIT)
  if units <= 0 or not market.sell(force_index, KIND, NAME, units, nil, power.JOURNAL_MERGE_TICKS) then return end
  for _, entity in ipairs(entities) do entity.energy = entity.energy * kept end
end

-- Buys what refills the import substations of a force, as far as its credits and the market allow;
-- the energy bought is shared out in proportion to what each lacks.
local function settle_imports(force_index, entities)
  local missing = {}
  for i, entity in ipairs(entities) do missing[i] = math.max(0, entity.electric_buffer_size - entity.energy) end
  local units, total_missing = settlement.wanted_units(missing, market.buyable(force_index, KIND, NAME),
    JOULES_PER_UNIT)
  if not units or units <= 0 then return end
  local cost = market.preview(force_index, KIND, NAME, "buy", units)
  if not cost then return end
  units = settlement.affordable(units, cost, storage.forces[force_index].balance)
  if units <= 0 or not market.buy(force_index, KIND, NAME, units, nil, power.JOURNAL_MERGE_TICKS) then return end
  for i, joules in ipairs(settlement.shares(missing, total_missing, units, JOULES_PER_UNIT)) do
    entities[i].energy = entities[i].energy + joules
  end
end

--- on_nth_tick(SETTLE_TICKS): settles every substation that has a powered hub in range.
function power.on_settle_tick()
  for force_index, group in pairs(trading_groups()) do
    if storage.forces[force_index] then
      settle_exports(force_index, group.export)
      settle_imports(force_index, group.import)
    end
  end
end

return power
