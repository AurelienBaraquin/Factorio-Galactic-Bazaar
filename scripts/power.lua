-- The power module (ADR-0009): substations that sell the network's surplus electricity to the
-- market and buy what it lacks. Each works through the nearest powered hub of its force in range
-- (ADR-0005). Every SETTLE_TICKS, the export substations' buffers are sold and the import
-- substations' buffers refilled, one trade per force and direction. The buffer size, set from the
-- force's research level, caps the throughput. State lives in storage.power.
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local power = {}

power.KINDS = { ["gb-power-export"] = "export", ["gb-power-import"] = "import" }
power.HUB_RANGE = 10
power.SETTLE_TICKS = 300
-- An export substation sells while electricity fetches at least this fraction of its base value.
power.MIN_PRICE_RATIO = 0.5
-- Throughput per substation in watts at each research level; level 1 comes with the substations.
power.LEVEL_WATTS = { 10e6, 40e6 }
power.LEVEL_TECHNOLOGIES = { "gb-power-trading", "gb-power-trading-2" }

local KIND, NAME = "energy", "electricity"
local JOULES_PER_UNIT = 1e6

--- on_init and on_configuration_changed: creates the state and drops substations that no longer exist.
function power.init()
  storage.power = storage.power or { modules = {} }
  local gone = {}
  for unit_number, module in pairs(storage.power.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do storage.power.modules[unit_number] = nil end
end

--- Registers a newly built substation; returns true when the entity was one.
function power.on_built(entity)
  local kind = power.KINDS[entity.name]
  if not kind then return false end
  storage.power.modules[entity.unit_number] = { entity = entity, kind = kind }
  script.register_on_object_destroyed(entity)
  return true
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

-- The substations that can trade now, grouped by force and direction, with their buffers sized
-- for the force's level.
local function trading_groups()
  local groups = {}
  local buffers = {}
  for _, module in pairs(storage.power.modules) do
    local entity = module.entity
    if entity.valid and hubs.nearest(entity, power.HUB_RANGE, true) then
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
  if joules <= 0 then return end
  local units = math.min(joules / JOULES_PER_UNIT, market.sellable(force_index, KIND, NAME, power.MIN_PRICE_RATIO))
  if units <= 0 or not market.sell(force_index, KIND, NAME, units) then return end
  local kept = 1 - units * JOULES_PER_UNIT / joules
  for _, entity in ipairs(entities) do entity.energy = entity.energy * kept end
end

-- Buys what refills the import substations of a force, as far as its credits and the market allow;
-- the energy bought is shared out in proportion to what each lacks.
local function settle_imports(force_index, entities)
  local missing = {}
  local joules = 0
  for i, entity in ipairs(entities) do
    missing[i] = math.max(0, entity.electric_buffer_size - entity.energy)
    joules = joules + missing[i]
  end
  local units = math.min(joules / JOULES_PER_UNIT, market.buyable(force_index, KIND, NAME))
  if units <= 0 then return end
  local cost = market.preview(force_index, KIND, NAME, "buy", units)
  local balance = storage.forces[force_index].balance
  -- The cost is convex in the units, so scaling them by balance / cost keeps the cost within it.
  if cost and cost > balance then units = units * balance / cost end
  if units <= 0 or not market.buy(force_index, KIND, NAME, units) then return end
  local share = units * JOULES_PER_UNIT / joules
  for i, entity in ipairs(entities) do entity.energy = entity.energy + missing[i] * share end
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
