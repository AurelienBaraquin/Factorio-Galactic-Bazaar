-- The manifold module (#63): storage tanks that trade fluids, each attached to the nearest hub of
-- its force in range (ADR-0005). Export manifolds sell their fluid while it fetches at least
-- MIN_PRICE_RATIO × its base value, EXPORT_BATCH of them every EXPORT_INTERVAL in turn; import
-- manifolds receive the fluids bought, delivered by orbital capsule (ADR-0006). Fluids are priced
-- by name; temperature does not change the price. State lives in storage.manifold, with an index of
-- each hub's import manifolds and the round-robin order of export manifolds.
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local manifold = {}

manifold.KINDS = { ["gb-fluid-export"] = "export", ["gb-fluid-import"] = "import" }
manifold.HUB_RANGE = 10
-- Ticks between two export batches, and export manifolds visited per batch: 20 a second.
manifold.EXPORT_INTERVAL = 6
manifold.EXPORT_BATCH = 2
manifold.MIN_PRICE_RATIO = 0.5
-- Ticks over which a force's recurring fluid sales share one journal entry per fluid.
manifold.JOURNAL_MERGE_TICKS = 3600

-- storage.manifold.imports[hub unit_number] = {[import manifold unit_number] = true}.
local function index_import(hub_unit_number, unit_number, present)
  if not hub_unit_number then return end
  local imports = storage.manifold.imports
  imports[hub_unit_number] = imports[hub_unit_number] or {}
  imports[hub_unit_number][unit_number] = present or nil
  if next(imports[hub_unit_number]) == nil then imports[hub_unit_number] = nil end
end

-- Attaches a manifold to the nearest hub of its force in range, keeping the import index in step.
local function attach(module)
  local previous = module.hub
  hubs.attach(module, manifold.HUB_RANGE)
  if module.kind == "import" and module.hub ~= previous then
    index_import(previous, module.entity.unit_number, false)
    index_import(module.hub, module.entity.unit_number, true)
  end
end

--- on_init and on_configuration_changed: creates the state, drops manifolds that no longer exist,
--- rebuilds the indexes and re-attaches the others.
function manifold.init()
  storage.manifold = storage.manifold or { modules = {} }
  local state = storage.manifold
  local gone = {}
  for unit_number, module in pairs(state.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do state.modules[unit_number] = nil end
  state.imports, state.exports, state.cursor = {}, {}, 1
  for unit_number, module in pairs(state.modules) do
    module.hub = nil
    attach(module)
    if module.kind == "export" then
      state.exports[#state.exports + 1] = unit_number
      module.export_index = #state.exports
    end
  end
end

--- Registers a newly built manifold; returns true when the entity was one.
function manifold.on_built(entity)
  local kind = manifold.KINDS[entity.name]
  if not kind then return false end
  local state = storage.manifold
  if state.modules[entity.unit_number] then return true end
  local module = { entity = entity, kind = kind }
  state.modules[entity.unit_number] = module
  attach(module)
  if kind == "export" then
    state.exports[#state.exports + 1] = entity.unit_number
    module.export_index = #state.exports
  end
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed manifold; returns true when the unit number was one. An export manifold
--- leaves the round-robin list in O(1): the last entry takes its place.
function manifold.forget(unit_number)
  local state = storage.manifold
  local module = state.modules[unit_number]
  if not module then return false end
  state.modules[unit_number] = nil
  if module.kind == "import" then index_import(module.hub, unit_number, false) end
  local index = module.export_index
  if index then
    local exports, last = state.exports, #state.exports
    if index ~= last then
      exports[index] = exports[last]
      state.modules[exports[index]].export_index = index
    end
    exports[last] = nil
    if state.cursor > last then state.cursor = 1 end
  end
  return true
end

--- A hub appeared: manifolds in its range move to it if it is now their nearest hub.
function manifold.on_hub_built(hub)
  local names = {}
  for name in pairs(manifold.KINDS) do names[#names + 1] = name end
  local nearby = hub.surface.find_entities_filtered({
    name = names, force = hub.force, position = hub.position, radius = manifold.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.manifold.modules[entity.unit_number]
    if module then attach(module) end
  end
end

--- A hub disappeared: its manifolds look for another hub in range.
function manifold.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.manifold.modules) do
    if module.hub == hub_unit_number and module.entity.valid then attach(module) end
  end
end

--- on_forces_merged: manifolds now belong to the merged force and may use its hubs.
function manifold.on_forces_merged()
  for _, module in pairs(storage.manifold.modules) do
    if module.entity.valid then attach(module) end
  end
end

-- The import manifolds of a hub that belong to its force.
local function import_manifolds(hub_unit_number)
  local hub = hubs.get(hub_unit_number)
  local entities = {}
  if not hub then return entities end
  for unit_number in pairs(storage.manifold.imports[hub_unit_number] or {}) do
    local entity = storage.manifold.modules[unit_number].entity
    if entity.valid and entity.force == hub.force then entities[#entities + 1] = entity end
  end
  return entities
end

--- Whether a hub has an import manifold of its force that can take `name`: empty or already
--- holding that fluid.
function manifold.can_receive(hub_unit_number, name)
  for _, entity in ipairs(import_manifolds(hub_unit_number)) do
    local fluid = entity.get_fluid(1)
    if not fluid or fluid.name == name then return true end
  end
  return false
end

--- Puts bought fluid into a hub's import manifolds, at the fluid's default temperature. Returns how
--- much was stored; the rest did not fit.
function manifold.deliver(hub_unit_number, name, amount)
  local temperature = prototypes.fluid[name].default_temperature
  local stored = 0
  for _, entity in ipairs(import_manifolds(hub_unit_number)) do
    if stored >= amount then break end
    stored = stored + entity.insert_fluid({ name = name, amount = amount - stored, temperature = temperature })
  end
  return stored
end

-- Sells what an export manifold holds, as far as its price floor allows: the fluid leaves the tank
-- first, the market pays for what actually left, and it goes back if the market refuses. Returns
-- whether it sold.
local function sell(module)
  local entity = module.entity
  local fluid = entity.get_fluid(1)
  local force_index = entity.force.index
  local units = math.min(fluid.amount, market.sellable(force_index, "fluid", fluid.name, manifold.MIN_PRICE_RATIO))
  if units <= 0 then return false end
  local removed = entity.remove_fluid(1, units)
  if not (removed and removed.amount > 0) then return false end
  if market.sell(force_index, "fluid", removed.name, removed.amount, nil, manifold.JOURNAL_MERGE_TICKS) then
    return true
  end
  entity.insert_fluid({ name = removed.name, amount = removed.amount, temperature = removed.temperature })
  return false
end

-- Sells from an export manifold with fluid and a powered hub; `held` records whether it kept its
-- fluid without selling any, for its status (scripts/entity_status.lua).
local function sell_from(module)
  local fluid = module.entity.get_fluid(1)
  if not (fluid and fluid.amount > 0 and hubs.trading_hub(module, manifold.HUB_RANGE)) then return end
  module.held = not sell(module)
end

--- on_nth_tick(EXPORT_INTERVAL): the next EXPORT_BATCH export manifolds sell their fluid.
function manifold.on_export_tick()
  local state = storage.manifold
  local exports = state.exports
  for _ = 1, math.min(manifold.EXPORT_BATCH, #exports) do
    if state.cursor > #exports then state.cursor = 1 end
    local module = state.modules[exports[state.cursor]]
    state.cursor = state.cursor + 1
    if module and module.entity.valid then sell_from(module) end
  end
end

return manifold
