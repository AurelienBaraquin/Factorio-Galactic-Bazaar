-- The cargo module (ADR-0005): export chests sold to the market and import chests that receive
-- purchases, each attached to the nearest trading hub of its force within range. State lives in
-- storage.cargo.
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local cargo = {}

cargo.KINDS = { ["gb-export-chest"] = "export", ["gb-import-chest"] = "import" }
-- Tiles between a module's centre and its hub's centre.
cargo.HUB_RANGE = 10
-- An export chest sells while each unit fetches at least this fraction of its base value.
cargo.DEFAULT_MIN_PRICE_RATIO = 0.5
-- Ticks between two export batches, and export chests visited per batch.
cargo.EXPORT_INTERVAL = 60
cargo.EXPORT_BATCH = 20

local function nearest_hub(entity)
  local best, best_distance
  local candidates = entity.surface.find_entities_filtered({
    name = hubs.NAME, force = entity.force, position = entity.position, radius = cargo.HUB_RANGE,
  })
  for _, hub in ipairs(candidates) do
    if hubs.get(hub.unit_number) then
      local dx, dy = hub.position.x - entity.position.x, hub.position.y - entity.position.y
      local distance = dx * dx + dy * dy
      if not best or distance < best_distance or (distance == best_distance and hub.unit_number < best.unit_number) then
        best, best_distance = hub, distance
      end
    end
  end
  return best and best.unit_number or nil
end

local function attach(module)
  module.hub = nearest_hub(module.entity)
end

--- on_init and on_configuration_changed: creates the state and drops modules that no longer exist.
function cargo.init()
  storage.cargo = storage.cargo or { modules = {}, exports = {}, cursor = 1 }
  local gone = {}
  for unit_number, module in pairs(storage.cargo.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do cargo.forget(unit_number) end
end

function cargo.on_built(entity)
  local kind = cargo.KINDS[entity.name]
  if not kind then return end
  local module = { entity = entity, kind = kind, min_price_ratio = cargo.DEFAULT_MIN_PRICE_RATIO }
  attach(module)
  storage.cargo.modules[entity.unit_number] = module
  if kind == "export" then table.insert(storage.cargo.exports, entity.unit_number) end
  script.register_on_object_destroyed(entity)
end

--- Drops a module from the state (destroyed, or invalid after a configuration change).
function cargo.forget(unit_number)
  local state = storage.cargo
  if not state.modules[unit_number] then return end
  state.modules[unit_number] = nil
  for i, exported in ipairs(state.exports) do
    if exported == unit_number then
      table.remove(state.exports, i)
      if state.cursor > i then state.cursor = state.cursor - 1 end
      break
    end
  end
end

--- A hub appeared: modules in its range move to it if it is now their nearest hub.
function cargo.on_hub_built(hub)
  local names = {}
  for name in pairs(cargo.KINDS) do names[#names + 1] = name end
  local nearby = hub.surface.find_entities_filtered({
    name = names, force = hub.force, position = hub.position, radius = cargo.HUB_RANGE,
  })
  for _, entity in ipairs(nearby) do
    local module = storage.cargo.modules[entity.unit_number]
    if module then attach(module) end
  end
end

--- A hub disappeared: its modules look for another hub in range.
function cargo.on_hub_removed(hub_unit_number)
  for _, module in pairs(storage.cargo.modules) do
    if module.hub == hub_unit_number and module.entity.valid then attach(module) end
  end
end

--- The hub entity a module works for, when it exists and has power; nil otherwise.
function cargo.powered_hub(module)
  local hub = module.hub and hubs.get(module.hub)
  return hub and hub.energy > 0 and hub or nil
end

local function export_from(module)
  if not (module.entity.valid and cargo.powered_hub(module)) then return end
  local force_index = module.entity.force.index
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  for _, content in ipairs(inventory.get_contents()) do
    if content.quality == "normal" then
      local units = math.min(content.count,
        math.floor(market.sellable(force_index, "item", content.name, module.min_price_ratio)))
      if units > 0 then
        local stack = { name = content.name, count = units, quality = content.quality }
        local removed = inventory.remove(stack)
        if removed > 0 and not market.sell(force_index, "item", content.name, removed) then
          stack.count = removed
          inventory.insert(stack)
        end
      end
    end
  end
end

--- on_nth_tick(EXPORT_INTERVAL): sells the content of the next EXPORT_BATCH export chests.
function cargo.on_export_tick()
  local state = storage.cargo
  local exports = state.exports
  for _ = 1, math.min(cargo.EXPORT_BATCH, #exports) do
    if state.cursor > #exports then state.cursor = 1 end
    local module = state.modules[exports[state.cursor]]
    state.cursor = state.cursor + 1
    if module then export_from(module) end
  end
end

--- Puts purchased items into the import chests of a hub. Returns how many were stored; the rest
--- did not fit.
function cargo.deliver(hub_unit_number, name, count)
  local stored = 0
  for _, module in pairs(storage.cargo.modules) do
    if stored >= count then break end
    if module.kind == "import" and module.hub == hub_unit_number and module.entity.valid then
      stored = stored + module.entity.get_inventory(defines.inventory.chest).insert({
        name = name, count = count - stored, quality = "normal",
      })
    end
  end
  return stored
end

return cargo
