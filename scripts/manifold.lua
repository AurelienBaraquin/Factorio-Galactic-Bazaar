-- The manifold module (#63): storage tanks that trade fluids, each attached to the nearest hub of
-- its force in range (ADR-0005). Export manifolds sell their fluid every SELL_TICKS while it fetches
-- at least MIN_PRICE_RATIO × its base value; import manifolds receive the fluids bought, delivered
-- by orbital capsule (ADR-0006). Fluids are priced by name; temperature does not change the price.
-- State lives in storage.manifold.
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local manifold = {}

manifold.KINDS = { ["gb-fluid-export"] = "export", ["gb-fluid-import"] = "import" }
manifold.HUB_RANGE = 10
manifold.SELL_TICKS = 60
manifold.MIN_PRICE_RATIO = 0.5
-- Ticks over which a force's recurring fluid sales share one journal entry per fluid.
manifold.JOURNAL_MERGE_TICKS = 3600

--- on_init and on_configuration_changed: creates the state, drops manifolds that no longer exist and
--- re-attaches the others.
function manifold.init()
  storage.manifold = storage.manifold or { modules = {} }
  local modules = storage.manifold.modules
  local gone = {}
  for unit_number, module in pairs(modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do modules[unit_number] = nil end
  for _, module in pairs(modules) do hubs.attach(module, manifold.HUB_RANGE) end
end

--- Registers a newly built manifold; returns true when the entity was one.
function manifold.on_built(entity)
  local kind = manifold.KINDS[entity.name]
  if not kind then return false end
  local modules = storage.manifold.modules
  if modules[entity.unit_number] then return true end
  local module = { entity = entity, kind = kind }
  hubs.attach(module, manifold.HUB_RANGE)
  modules[entity.unit_number] = module
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed manifold; returns true when the unit number was one.
function manifold.forget(unit_number)
  if not storage.manifold.modules[unit_number] then return false end
  storage.manifold.modules[unit_number] = nil
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
    if module then hubs.attach(module, manifold.HUB_RANGE) end
  end
end

--- A hub disappeared: its manifolds look for another hub in range.
function manifold.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.manifold.modules) do
    if module.hub == hub_unit_number then hubs.attach(module, manifold.HUB_RANGE) end
  end
end

--- on_forces_merged: manifolds now belong to the merged force and may use its hubs.
function manifold.on_forces_merged()
  for _, module in pairs(storage.manifold.modules) do hubs.attach(module, manifold.HUB_RANGE) end
end

-- The import manifolds of a hub that belong to its force.
local function import_manifolds(hub_unit_number)
  local hub = hubs.get(hub_unit_number)
  local entities = {}
  if not hub then return entities end
  for _, module in pairs(storage.manifold.modules) do
    if module.kind == "import" and module.hub == hub_unit_number and module.entity.valid
      and module.entity.force == hub.force then
      entities[#entities + 1] = module.entity
    end
  end
  return entities
end

--- Whether a hub has an import manifold of its force to receive fluids.
function manifold.has_import(hub_unit_number)
  return #import_manifolds(hub_unit_number) > 0
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

-- Sells what an export manifold holds, as far as its price floor allows. The sale goes first: the
-- fluid only leaves the tank for what the market paid.
local function sell_from(module)
  local entity = module.entity
  local fluid = entity.get_fluid(1)
  if not (fluid and fluid.amount > 0 and hubs.trading_hub(module, manifold.HUB_RANGE)) then return end
  local force_index = entity.force.index
  local units = math.min(fluid.amount, market.sellable(force_index, "fluid", fluid.name, manifold.MIN_PRICE_RATIO))
  if units <= 0 then return end
  if market.sell(force_index, "fluid", fluid.name, units, nil, manifold.JOURNAL_MERGE_TICKS) then
    entity.remove_fluid(1, units)
  end
end

--- on_nth_tick(SELL_TICKS): every export manifold sells its fluid.
function manifold.on_sell_tick()
  for _, module in pairs(storage.manifold.modules) do
    if module.kind == "export" and module.entity.valid then sell_from(module) end
  end
end

return manifold
