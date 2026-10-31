-- The cargo module (ADR-0005): export chests sold to the market and import chests that receive
-- purchases, each attached to the nearest trading hub of its force within range. State lives in
-- storage.cargo, with an index of each hub's import chests so that a delivery only visits those.
local hubs = require("scripts.hubs")
local market = require("scripts.market")

local cargo = {}

cargo.KINDS = { ["gb-export-chest"] = "export", ["gb-import-chest"] = "import" }
-- Tiles between a module's centre and its hub's centre.
cargo.HUB_RANGE = 10
-- An export chest sells while each unit fetches at least this fraction of its base value.
cargo.DEFAULT_MIN_PRICE_RATIO = 0.5
-- The Market tab sells while each unit fetches at least this fraction of its base value, so
-- nearly spoiled stock cannot be dumped to push a price down for almost nothing (ADR-0013).
cargo.WINDOW_MIN_PRICE_RATIO = 0.05
-- Ticks over which a force's automatic sales of one item share one journal entry.
cargo.JOURNAL_MERGE_TICKS = 3600
-- Ticks between two export batches, and export chests visited per batch: 20 chests a second,
-- spread thinly so that no single tick pays for many.
cargo.EXPORT_INTERVAL = 6
cargo.EXPORT_BATCH = 2

-- storage.cargo.imports[hub unit_number] = {[import chest unit_number] = true}.
local function index_import(hub_unit_number, unit_number, present)
  if not hub_unit_number then return end
  local imports = storage.cargo.imports
  imports[hub_unit_number] = imports[hub_unit_number] or {}
  imports[hub_unit_number][unit_number] = present or nil
  if next(imports[hub_unit_number]) == nil then imports[hub_unit_number] = nil end
end

local function set_hub(module, hub_unit_number)
  local previous = module.hub
  module.hub = hub_unit_number
  if module.kind == "import" and hub_unit_number ~= previous then
    index_import(previous, module.entity.unit_number, false)
    index_import(hub_unit_number, module.entity.unit_number, true)
  end
end

local function attach(module, powered_only)
  set_hub(module, hubs.nearest(module.entity, cargo.HUB_RANGE, powered_only))
end

local function attach_all()
  for _, module in pairs(storage.cargo.modules) do
    if module.entity.valid then attach(module) end
  end
end

--- on_init and on_configuration_changed: creates the state, drops modules that no longer exist,
--- rebuilds the import index and re-attaches the modules (hubs may have been dropped, or the range
--- changed).
function cargo.init()
  storage.cargo = storage.cargo or { modules = {}, exports = {}, cursor = 1 }
  storage.cargo.imports = storage.cargo.imports or {}
  local gone = {}
  for unit_number, module in pairs(storage.cargo.modules) do
    if not module.entity.valid then gone[#gone + 1] = unit_number end
  end
  for _, unit_number in ipairs(gone) do cargo.forget(unit_number) end
  storage.cargo.imports = {}
  for unit_number, module in pairs(storage.cargo.modules) do
    if module.kind == "import" then index_import(module.hub, unit_number, true) end
  end
  attach_all()
end

--- on_forces_merged: chests now belong to the merged force and may use its hubs.
cargo.on_forces_merged = attach_all

function cargo.on_built(entity)
  local kind = cargo.KINDS[entity.name]
  if not kind then return end
  local module = { entity = entity, kind = kind, min_price_ratio = cargo.DEFAULT_MIN_PRICE_RATIO }
  attach(module)
  storage.cargo.modules[entity.unit_number] = module
  if kind == "export" then
    local exports = storage.cargo.exports
    exports[#exports + 1] = entity.unit_number
    module.export_index = #exports
  end
  script.register_on_object_destroyed(entity)
end

--- Drops a module from the state (destroyed, or invalid after a configuration change). An export
--- chest leaves the round-robin list in O(1): the last entry takes its place.
function cargo.forget(unit_number)
  local state = storage.cargo
  local module = state.modules[unit_number]
  if not module then return end
  state.modules[unit_number] = nil
  if module.kind == "import" then index_import(module.hub, unit_number, false) end
  local index = module.export_index
  if not index then return end
  local exports = state.exports
  local last = #exports
  if index ~= last then
    exports[index] = exports[last]
    state.modules[exports[index]].export_index = index
  end
  exports[last] = nil
  if state.cursor > last then state.cursor = 1 end
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

--- The hub entity a module works for: its hub if it is valid, of the module's force and powered;
--- otherwise the nearest powered hub of its force in range, which it then attaches to; nil when
--- there is none, the module then staying attached to its nearest hub, powered or not.
function cargo.powered_hub(module)
  local hub = module.hub and hubs.get(module.hub)
  local own = hub and hub.force == module.entity.force
  if own and hubs.has_power(hub) then return hub end
  local powered = hubs.nearest(module.entity, cargo.HUB_RANGE, true)
  if powered then
    set_hub(module, powered)
    return hubs.get(powered)
  end
  -- No powered hub in range: keep an unpowered hub of its own force, or find the nearest one.
  if not own then attach(module) end
  return nil
end

-- Item types whose stacks carry no data of their own beyond spoilage (no equipment grid, inventory,
-- blueprint, label, tags or entity data). An allowlist: a type it does not name, from a later game
-- version or a mod, is treated as carrying data and is not sold.
local DATALESS_ITEM_TYPES = {
  ["item"] = true, ["tool"] = true, ["capsule"] = true, ["ammo"] = true, ["module"] = true, ["gun"] = true,
  ["rail-planner"] = true, ["repair-tool"] = true, ["space-platform-starter-pack"] = true,
}

-- Whether a stack's LuaItem holds only its spoilage: every stack of a spoilable item has one.
local function has_only_spoilage(stack)
  return DATALESS_ITEM_TYPES[stack.prototype.type] and stack.prototype.get_spoil_ticks(stack.quality) > 0
end

-- A stack worth its base value at its quality, scaled by its freshness: no extra data (equipment
-- grid, inventory, blueprint, tags), undamaged, and for tools and ammunition unused.
local function is_plain(stack)
  if (stack.item and not has_only_spoilage(stack)) or stack.health < 1 then return false end
  if stack.is_tool and stack.durability < stack.prototype.get_durability(stack.quality) then return false end
  if stack.is_ammo and stack.ammo < stack.prototype.magazine_size then return false end
  return true
end

--- Sells the plain stacks of `inventory` for a force, each unit at its quality's price times its
--- freshness (1 - spoil_percent, ADR-0013), while each unit fetches at least `min_price_ratio` × its
--- base value; only stacks of `name` (any quality) when given, at most `limit` units when given,
--- only of `quality_name` when given; `merge_ticks` (optional) merges the journal entries of recurring
--- sales. The sale goes first: a stack only shrinks for units the market has paid for. Returns the
--- units sold and the credits received.
function cargo.sell_stacks(inventory, force_index, min_price_ratio, name, limit, quality_name, merge_ticks)
  local sold, revenue = 0, 0
  for slot = 1, #inventory do
    if limit and sold >= limit then break end
    local stack = inventory[slot]
    if stack.valid_for_read and (not name or stack.name == name)
      and (not quality_name or stack.quality.name == quality_name) and is_plain(stack) then
      local stack_quality = stack.quality.name
      local freshness = 1 - stack.spoil_percent
      local units = freshness > 0 and math.min(stack.count, limit and limit - sold or math.huge,
        math.floor(market.sellable(force_index, "item", stack.name, min_price_ratio / freshness, stack_quality)))
      if units and units > 0 then
        local ok, credits = market.sell(force_index, "item", stack.name, units, stack_quality, merge_ticks, freshness)
        if ok then
          stack.count = stack.count - units
          sold, revenue = sold + units, revenue + credits
        end
      end
    end
  end
  return sold, revenue
end

--- Average freshness (1 - spoil_percent) of the first `limit` plain units of `name` and
--- `quality_name` in `inventory`, in the order `sell_stacks` sells them; 1 when there are none.
function cargo.sale_freshness(inventory, name, limit, quality_name)
  local units, fresh = 0, 0
  for slot = 1, #inventory do
    if units >= limit then break end
    local stack = inventory[slot]
    if stack.valid_for_read and stack.name == name and stack.quality.name == quality_name and is_plain(stack) then
      local taken = math.min(stack.count, limit - units)
      units, fresh = units + taken, fresh + taken * (1 - stack.spoil_percent)
    end
  end
  return units > 0 and fresh / units or 1
end

-- Sells what an export chest holds; `held` records whether it kept goods without selling any (below
-- its floor, or not plain), for its status (scripts/entity_status.lua).
local function export_from(module)
  if not (module.entity.valid and cargo.powered_hub(module)) then return end
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  local sold = cargo.sell_stacks(inventory, module.entity.force.index,
    module.min_price_ratio, nil, nil, nil, cargo.JOURNAL_MERGE_TICKS)
  module.held = sold == 0 and not inventory.is_empty()
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

-- The inventories of a hub's import chests that still belong to the hub's force.
local function import_inventories(hub_unit_number)
  local hub = hubs.get(hub_unit_number)
  local inventories = {}
  if not hub then return inventories end
  for unit_number in pairs(storage.cargo.imports[hub_unit_number] or {}) do
    local module = storage.cargo.modules[unit_number]
    if module.entity.valid and module.entity.force == hub.force then
      inventories[#inventories + 1] = module.entity.get_inventory(defines.inventory.chest)
    end
  end
  return inventories
end

--- Whether a hub has at least one import chest of its force to receive purchases.
function cargo.has_import(hub_unit_number)
  return #import_inventories(hub_unit_number) > 0
end

--- Puts purchased items into the import chests of a hub. Returns how many were stored; the rest
--- did not fit.
function cargo.deliver(hub_unit_number, name, count)
  local stored = 0
  for _, inventory in ipairs(import_inventories(hub_unit_number)) do
    if stored >= count then break end
    stored = stored + inventory.insert({ name = name, count = count - stored, quality = "normal" })
  end
  return stored
end

return cargo
