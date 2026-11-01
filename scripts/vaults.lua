-- Vaults (#119, ADR-0024): storage space a force rents from a NPC. A vault is a service contract
-- (ADR-0019) taken at a hub from the Contracts tab, charged every period of its term whatever it
-- holds: it holds the goods whether its hub exists or not. Vault uplinks attached to its hub
-- (ADR-0005) send what is put in them into the force's vaults rented there, up to each vault's
-- stacks: every UPLINK_TICKS, the next UPLINK_BATCH uplinks in turn (20 a second, as export chests),
-- moving at most MAX_MOVES stacks, so that no pass does more however many uplinks and goods there
-- are. The goods stay the force's:
-- Retrieve ships them back to the vault's own hub by orbital capsule (freight.ship, the normal
-- delivery delay), as much as its capsule queue takes, the rest staying in the vault; when the
-- contract ends in any way (term over, default, abandon, bankruptcy) the vault ships what it holds
-- back the same way, every SWEEP_TICKS until nothing is left, to its hub or another hub of the force
-- on its surface; nothing is ever seized. An active vault whose hub is gone re-attaches only to a hub
-- of its force within REATTACH_RANGE of where its hub stood (a hub replaced in place); otherwise it
-- stays unattached until its term ends, still charged, and cannot be retrieved. A vault whose surface
-- was deleted is the only one whose goods may go to a hub on another surface. Capsules bringing a
-- vault's goods back carry it (`vault`): if their hub is removed, the goods return to the vault.
-- State lives in storage.vaults: `leases` {[contract id] = {force_index, hub, surface_index,
-- surface_name, position (where its hub stands or stood), goods = {[item name] = units}}}, kept
-- after the contract ends until its goods are shipped, `uplinks`
-- {[unit_number] = {entity, hub, held, order_index}}, and the round-robin `order` (unit numbers) and
-- `cursor`; all are created on first use, since an event handler may run before the configuration
-- change of a save that predates them.
local account = require("scripts.core.account")
local cargo = require("scripts.cargo")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local freight = require("scripts.freight")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local insolvency = require("scripts.core.insolvency")
local storage_rental = require("scripts.core.storage_rental")

local vaults = {}

vaults.UPLINK = "gb-vault-uplink"
vaults.TECHNOLOGY = "gb-storage-rental"
vaults.HUB_RANGE = 10
vaults.UPLINK_TICKS = 6
vaults.UPLINK_BATCH = 2
vaults.MAX_MOVES = 10
vaults.SWEEP_TICKS = 60
-- Tiles from where an active vault's hub stood within which a new hub of its force takes it over.
vaults.REATTACH_RANGE = 10

-- Prototype-derived facts, by item name, filled on first use: the same on every peer, and never
-- written to storage (prototypes do not change while the game runs).
local stack_sizes, storable_names = {}, {}

-- Lists the uplinks for the round robin, in unit number order.
local function list_uplinks(vault_state)
  vault_state.order, vault_state.cursor = {}, 1
  local units = {}
  for unit_number in pairs(vault_state.uplinks) do units[#units + 1] = unit_number end
  table.sort(units)
  for index, unit_number in ipairs(units) do
    vault_state.order[index] = unit_number
    vault_state.uplinks[unit_number].order_index = index
  end
end

local function state()
  local vault_state = storage.vaults
  if not vault_state then
    vault_state = { leases = {}, uplinks = {} }
    storage.vaults = vault_state
  end
  if not vault_state.order then list_uplinks(vault_state) end
  return vault_state
end

local function researched(force)
  local technology = force.technologies[vaults.TECHNOLOGY]
  return technology ~= nil and technology.researched
end

-- Whether the contract of vault `id` is still active.
local function active(lease, id)
  local contract = contracts.get(lease.force_index, id)
  return contract ~= nil and contract.state == core.ACTIVE
end

--- The vault of contract `id`, or nil.
function vaults.lease(id)
  return state().leases[id]
end

--- The goods a vault holds, sorted by name: {{kind = "item", name, count}...}.
function vaults.goods(id)
  local lease = state().leases[id]
  local list = {}
  for name, count in pairs(lease and lease.goods or {}) do
    list[#list + 1] = { kind = "item", name = name, count = count }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- Stacks that `goods` take.
local function stacks_of(goods)
  local sizes = {}
  for name in pairs(goods) do sizes[name] = prototypes.item[name].stack_size end
  return storage_rental.stacks(goods, sizes)
end

--- Stacks a vault holds.
function vaults.stacks(id)
  local lease = state().leases[id]
  return lease and stacks_of(lease.goods) or 0
end

--- What ended vaults of a force still have to ship back: the stacks, and how many vaults.
function vaults.returning(force_index)
  local stacks, count = 0, 0
  for id, lease in pairs(state().leases) do
    if lease.force_index == force_index and next(lease.goods) and not active(lease, id) then
      stacks, count = stacks + stacks_of(lease.goods), count + 1
    end
  end
  return stacks, count
end

--- Rents a vault of VAULT_SLOTS stacks for a force at a hub of its force: a contract offered and
--- accepted at once, its guarantee (one period's charge) held; or nothing changes. Returns the
--- contract id, or nil and a reason (not-researched, no-import-chest, too-many-contracts, insolvent,
--- insufficient-funds; not-offered and expired cannot happen, the offer being accepted in its tick).
function vaults.rent(force_index, hub_unit_number)
  local force = game.forces[force_index]
  if not researched(force) then return nil, "not-researched" end
  local hub = hubs.get(hub_unit_number)
  if not (hub and hub.force_index == force_index and cargo.has_import(hub_unit_number)) then
    return nil, "no-import-chest"
  end
  if #contracts.listed(force_index) >= contracts.MAX_LISTED then return nil, "too-many-contracts" end
  local force_state = storage.forces[force_index]
  -- Before the offer is filed, so that a refusal leaves no declined contract behind.
  if insolvency.insolvent(force_state) then return nil, "insolvent" end
  local spec = storage_rental.vault(storage_rental.vault_operator(incoming.draw(force_index)),
    storage_rental.VAULT_SLOTS)
  if account.available(force_state) < spec.deposit then return nil, "insufficient-funds" end
  local id = contracts.offer(force_index, spec)
  local accepted, reason = contracts.accept(force_index, id)
  if not accepted then
    contracts.decline(force_index, id)
    return nil, reason
  end
  state().leases[id] = {
    force_index = force_index, hub = hub_unit_number, surface_index = hub.surface_index,
    surface_name = hub.surface.name, position = { x = hub.position.x, y = hub.position.y }, goods = {},
  }
  return id
end

-- Whether a vault's surface was deleted: no surface under its index, or another one (indexes of
-- deleted surfaces can be reused).
local function surface_gone(lease)
  local surface = game.get_surface(lease.surface_index)
  return surface == nil or (lease.surface_name ~= nil and surface.name ~= lease.surface_name)
end

-- The hubs of a vault's force, by unit number, that `accept(unit_number)` accepts: on the vault's
-- surface, or on any surface once that surface was deleted.
local function hubs_for(lease, accept)
  local anywhere = surface_gone(lease)
  local units = {}
  for unit_number, hub in pairs(storage.hubs) do
    local entity = hub.entity
    if entity.valid and entity.force_index == lease.force_index
      and (anywhere or entity.surface_index == lease.surface_index) and accept(unit_number) then
      units[#units + 1] = unit_number
    end
  end
  table.sort(units)
  return units
end

-- An active vault's hub: its own while it exists, otherwise the nearest hub of its force within
-- REATTACH_RANGE of where that hub stood, on the same surface (then the lowest unit number); nil,
-- the vault unattached, when there is none.
local function attached_hub(lease)
  local hub = lease.hub and hubs.get(lease.hub)
  if hub and hub.force_index == lease.force_index then return lease.hub end
  lease.hub = nil
  if not lease.position or surface_gone(lease) then return nil end
  local best, best_distance
  for unit_number, entry in pairs(storage.hubs) do
    local entity = entry.entity
    if entity.valid and entity.force_index == lease.force_index and entity.surface_index == lease.surface_index then
      local dx, dy = entity.position.x - lease.position.x, entity.position.y - lease.position.y
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance <= vaults.REATTACH_RANGE and (not best or distance < best_distance
        or (distance == best_distance and unit_number < best)) then
        best, best_distance = unit_number, distance
      end
    end
  end
  if best then
    local entity = hubs.get(best)
    lease.hub, lease.position = best, { x = entity.position.x, y = entity.position.y }
  end
  return best
end

-- Where an ended vault's goods go: its hub when it still exists with an import chest, else the first
-- hub of its force on its surface (any surface once that surface was deleted) that has one; nil
-- when there is none yet.
local function return_hub(lease)
  local hub = lease.hub and hubs.get(lease.hub)
  if hub and hub.force_index == lease.force_index and cargo.has_import(lease.hub) then return lease.hub end
  return hubs_for(lease, cargo.has_import)[1]
end

-- Ships as much of a vault's goods to hub `hub_unit_number` as its capsule queue takes now, by
-- name; what is shipped leaves the vault. Returns the units shipped.
local function ship_some(id, lease, hub_unit_number)
  local shipped = 0
  for _, goods in ipairs(vaults.goods(id)) do
    local units = math.min(goods.count, freight.capsule_room(hub_unit_number, goods.name))
    if units >= 1 then
      local list = { { kind = "item", name = goods.name, count = units } }
      if freight.ship(lease.force_index, hub_unit_number, list, nil, nil,
        { id = id, surface_index = lease.surface_index, surface_name = lease.surface_name }) then
        lease.goods[goods.name] = goods.count - units > 0 and goods.count - units or nil
        shipped = shipped + units
      end
    end
  end
  return shipped
end

--- Retrieves what a force's active vault holds: shipped to the vault's own hub by orbital capsule,
--- as much as its capsule queue takes, the rest staying in the vault. Returns true and the stacks
--- left in the vault, or false and a reason (unknown, no-hub: the vault is unattached,
--- no-import-chest, queue-full).
function vaults.retrieve(force_index, id)
  local lease = state().leases[id]
  if not (lease and lease.force_index == force_index and active(lease, id)) then return false, "unknown" end
  local hub_unit_number = attached_hub(lease)
  if not hub_unit_number then return false, "no-hub" end
  if not cargo.has_import(hub_unit_number) then return false, "no-import-chest" end
  if next(lease.goods) and ship_some(id, lease, hub_unit_number) == 0 then return false, "queue-full" end
  return true, stacks_of(lease.goods)
end

-- A capsule bringing a vault's goods back lost its hub: the goods return to the vault (kept, or
-- recreated when it was already forgotten), to ship again.
freight.register_returner(function(capsule)
  local leases = state().leases
  local lease = leases[capsule.vault.id]
  if not lease then
    lease = {
      force_index = capsule.force_index, surface_index = capsule.vault.surface_index,
      surface_name = capsule.vault.surface_name, goods = {},
    }
    leases[capsule.vault.id] = lease
  end
  lease.goods[capsule.name] = (lease.goods[capsule.name] or 0) + capsule.count
end)

-- A vault serves every period while it exists: it holds the goods whether its hub exists or not.
local function can_serve(_, contract)
  return state().leases[contract.id] ~= nil
end
local function serve() return true end
contracts.register_service("storage", can_serve, serve)

--- on_nth_tick(SWEEP_TICKS): an active vault whose hub is gone re-attaches to a hub built where it
--- stood (`attached_hub`); an ended vault ships what it can of its goods back (`return_hub`), and is
--- forgotten once empty. What does not fit in a capsule queue waits for the next sweep.
function vaults.on_sweep_tick()
  local ids = {}
  for id in pairs(state().leases) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local lease = state().leases[id]
    if active(lease, id) then
      attached_hub(lease)
    else
      local hub_unit_number = return_hub(lease)
      if hub_unit_number then ship_some(id, lease, hub_unit_number) end
      if not next(lease.goods) then state().leases[id] = nil end
    end
  end
end

-- The force's vaults active at each hub: {[force_index] = {[hub] = {id...}}}, ids in order.
local function active_by_hub()
  local ids = {}
  for id in pairs(state().leases) do ids[#ids + 1] = id end
  table.sort(ids)
  local found = {}
  for _, id in ipairs(ids) do
    local lease = state().leases[id]
    if lease.hub and active(lease, id) then
      found[lease.force_index] = found[lease.force_index] or {}
      local list = found[lease.force_index][lease.hub] or {}
      found[lease.force_index][lease.hub] = list
      list[#list + 1] = id
    end
  end
  return found
end

--- Active vaults of force `force_index` rented at hub `hub_unit_number`.
function vaults.count_at(force_index, hub_unit_number)
  local at = active_by_hub()[force_index]
  return at and at[hub_unit_number] and #at[hub_unit_number] or 0
end

-- Whether items of `name` may go into a vault at all, read once per pass: a type whose stacks carry
-- no data (cargo.DATALESS_ITEM_TYPES) and not spoilable, so that what comes back is what went in.
local function storable_name(name)
  local known = storable_names[name]
  if known == nil then
    local prototype = prototypes.item[name]
    known = cargo.DATALESS_ITEM_TYPES[prototype.type] == true and prototype.get_spoil_ticks() == 0
    storable_names[name] = known
  end
  return known
end

-- The stack size of `name`.
local function size_of(name)
  local size = stack_sizes[name]
  if not size then
    size = prototypes.item[name].stack_size
    stack_sizes[name] = size
  end
  return size
end

-- Vault `id`'s stacks as the pass keeps them: {used (in all), own = {[name] = stacks}, part (some
-- item fills a stack only in part)}, counted once per pass, then kept up to date by `take`.
local function stacks_in(pass, id)
  local known = pass.vaults[id]
  if not known then
    known = { used = 0, own = {}, part = false }
    for name, units in pairs(pass.leases[id].goods) do
      local stacks = math.ceil(units / size_of(name))
      known.own[name], known.used = stacks, known.used + stacks
      known.part = known.part or units < stacks * size_of(name)
    end
    pass.vaults[id] = known
  end
  return known
end

-- Whether one of the vaults `ids` has room for anything: a stack free, or one filled in part. Kept
-- for the pass once it is no, since room only shrinks during a pass.
local function room_at(pass, ids)
  if pass.no_room[ids] then return false end
  for _, id in ipairs(ids) do
    local known = stacks_in(pass, id)
    if known.used < storage_rental.VAULT_SLOTS or known.part then return true end
  end
  pass.no_room[ids] = true
  return false
end

-- Units of `name` vault `id` can still take.
local function room_of(pass, id, name)
  local known = stacks_in(pass, id)
  return storage_rental.room_in(known.used, known.own[name] or 0, pass.leases[id].goods[name] or 0,
    size_of(name), storage_rental.VAULT_SLOTS)
end

-- Vault `id` takes `units` of `name`.
local function take(pass, id, name, units)
  local goods = pass.leases[id].goods
  local known = stacks_in(pass, id)
  goods[name] = (goods[name] or 0) + units
  local stacks = math.ceil(goods[name] / size_of(name))
  known.used = known.used + stacks - (known.own[name] or 0)
  known.own[name] = stacks
  known.part = known.part or goods[name] < stacks * size_of(name)
end

-- Moves the plain stacks of the `wanted` names an uplink's `inventory` holds into the vaults `ids`,
-- oldest first, while they have room and the pass may move more (`pass.moves`): one pass over its
-- slots.
local function upload_items(inventory, wanted, ids, pass)
  for slot = 1, #inventory do
    if pass.moves >= vaults.MAX_MOVES then return end
    local stack = inventory[slot]
    local name = stack.valid_for_read and stack.name
    if name and wanted[name] and stack.quality.name == "normal" and cargo.is_plain(stack) then
      for _, id in ipairs(ids) do
        local taken = math.min(stack.count, room_of(pass, id, name))
        if taken > 0 then
          take(pass, id, name, taken)
          pass.moves = pass.moves + 1
          stack.count = stack.count - taken
          if not stack.valid_for_read then break end
        end
      end
    end
  end
end

-- Whether one of the vaults `ids` has room for `name`; a no is kept for the rest of the pass
-- (`full`), since room only shrinks during a pass.
local function any_room(pass, full, ids, name)
  if full[name] then return false end
  for _, id in ipairs(ids) do
    -- A vault with every stack used has room only in a part stack of the item.
    local known = stacks_in(pass, id)
    if (known.used < storage_rental.VAULT_SLOTS or known.own[name]) and room_of(pass, id, name) > 0 then
      return true
    end
  end
  full[name] = true
  return false
end

-- Sends what an uplink holds into the vaults `ids`: its slots are read only when it holds items of
-- normal quality, of a storable kind, that some vault has room for, so that full vaults and goods no
-- vault takes cost one read of its contents. Records whether goods stayed in it.
local function upload(module, ids, pass)
  local inventory = module.entity.get_inventory(defines.inventory.chest)
  if not room_at(pass, ids) then
    module.held = not inventory.is_empty()
    return
  end
  local full = pass.full[ids]
  if not full then
    full = {}
    pass.full[ids] = full
  end
  local wanted
  for _, item in ipairs(inventory.get_contents()) do
    if item.quality == "normal" and storable_name(item.name) and any_room(pass, full, ids, item.name) then
      wanted = wanted or {}
      wanted[item.name] = true
    end
  end
  if wanted then upload_items(inventory, wanted, ids, pass) end
  module.held = not inventory.is_empty()
end

--- on_nth_tick(UPLINK_TICKS): the next UPLINK_BATCH uplinks in turn; each attached to a hub of its
--- force where the force rents a vault sends what it holds into those vaults, at most MAX_MOVES
--- stacks in all for the pass.
function vaults.on_uplink_tick()
  local vault_state = state()
  local order = vault_state.order
  if #order == 0 then return end
  local by_force = active_by_hub()
  local pass = { leases = vault_state.leases, vaults = {}, full = {}, no_room = {}, moves = 0 }
  for _ = 1, math.min(vaults.UPLINK_BATCH, #order) do
    if vault_state.cursor > #order then vault_state.cursor = 1 end
    local module = vault_state.uplinks[order[vault_state.cursor]]
    vault_state.cursor = vault_state.cursor + 1
    local entity = module.entity
    local at = entity.valid and module.hub and by_force[entity.force_index]
    local ids = at and at[module.hub]
    local hub = ids and hubs.get(module.hub)
    if hub and hub.force_index == entity.force_index then upload(module, ids, pass) end
  end
end

--- Registers a newly built vault uplink; returns true when the entity was one.
function vaults.on_built(entity)
  if entity.name ~= vaults.UPLINK then return false end
  local uplinks = state().uplinks
  if uplinks[entity.unit_number] then return true end
  local order = state().order
  local module = { entity = entity, order_index = #order + 1 }
  hubs.attach(module, vaults.HUB_RANGE)
  uplinks[entity.unit_number] = module
  order[module.order_index] = entity.unit_number
  script.register_on_object_destroyed(entity)
  return true
end

--- Forgets a destroyed vault uplink; returns true when the unit number was one. It leaves the round
--- robin in O(1): the last uplink takes its place.
function vaults.forget(unit_number)
  local vault_state = state()
  local module = vault_state.uplinks[unit_number]
  if not module then return false end
  vault_state.uplinks[unit_number] = nil
  local order, index = vault_state.order, module.order_index
  local last = #order
  if index ~= last then
    order[index] = order[last]
    vault_state.uplinks[order[index]].order_index = index
  end
  order[last] = nil
  if vault_state.cursor > last then vault_state.cursor = 1 end
  return true
end

--- The uplinks (read only), for the building status.
function vaults.uplinks()
  return state().uplinks
end

--- A hub appeared or disappeared, or forces merged: uplinks look for their nearest hub again.
function vaults.reattach()
  for _, module in pairs(state().uplinks) do hubs.attach(module, vaults.HUB_RANGE) end
end

--- on_forces_merged: the merged force's vaults now belong to the destination, with their contracts.
function vaults.on_forces_merged(event)
  for _, lease in pairs(state().leases) do
    if lease.force_index == event.source_index then lease.force_index = event.destination.index end
  end
  vaults.reattach()
end

--- on_init and on_configuration_changed: creates the state, drops goods whose item no longer exists
--- (a mod was removed: they cannot be shipped back), forgets uplinks that no longer exist and
--- re-attaches the others.
function vaults.init()
  local vault_state = state()
  for _, lease in pairs(vault_state.leases) do
    local gone = {}
    for name in pairs(lease.goods) do
      if not prototypes.item[name] then gone[#gone + 1] = name end
    end
    for _, name in ipairs(gone) do lease.goods[name] = nil end
  end
  local stale = {}
  for unit_number, module in pairs(vault_state.uplinks) do
    if not module.entity.valid then stale[#stale + 1] = unit_number end
  end
  for _, unit_number in ipairs(stale) do vault_state.uplinks[unit_number] = nil end
  list_uplinks(vault_state)
  vaults.reattach()
end

return vaults
