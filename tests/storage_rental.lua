-- In-game tests of storage rental (#119): vaults rented from NPCs (scripts/vaults.lua), filled by
-- vault uplinks and shipped back, and rental warehouses rented to NPCs (scripts/warehouses.lua).
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local entity_status = require("scripts.entity_status")
local insolvency = require("scripts.core.insolvency")
local market = require("scripts.market")
local freight = require("scripts.freight")
local storage_rental = require("scripts.core.storage_rental")
local vaults = require("scripts.vaults")
local warehouses = require("scripts.warehouses")

local player, created
local function place(name, dx, dy)
  local entity = player.surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + (dy or 0) }, force = "player",
    raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function force() return game.forces.player end
local function force_index() return force().index end
local function state() return storage.forces[force_index()] end
local function technology() return force().technologies[vaults.TECHNOLOGY] end
local function chest(entity) return entity.get_inventory(defines.inventory.chest) end

local function find(element, action, id)
  if element.tags.gb_action == action and (id == nil or element.tags.id == id) then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action, id)
    if found then return found end
  end
end

-- `count` names of plain items, sorted.
local function item_names(count)
  local names = {}
  for name, prototype in pairs(prototypes.item) do
    if prototype.type == "item" and not prototype.hidden and not prototype.parameter then names[#names + 1] = name end
  end
  table.sort(names)
  return { table.unpack(names, 1, count) }
end

-- Runs uplink passes until every uplink was visited once.
local function upload_all()
  for _ = 1, math.ceil(#storage.vaults.order / vaults.UPLINK_BATCH) do vaults.on_uplink_tick() end
end

-- Runs the period of contract `id` now.
local function run_period(id)
  contracts.get(force_index(), id).next_installment = game.tick
  contracts.on_settle_tick({ tick = game.tick })
end

describe("storage rental", function()
  local hub
  before_each(function()
    player = game.get_player(1)
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_storage = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
      researched = technology().researched,
      -- Renting and offers draw from the force's random state, which later test files rely on.
      rng = storage.incoming_contracts.rng[force_index()],
    }
    technology().researched = true
    test_helpers.set_balance(state(), 1e6)
    state().contracts.open = {}
    hub = place("gb-hub", 3)
    hub.energy = hub.electric_buffer_size
    place("gb-import-chest", 6)
  end)
  after_each(function()
    player = game.get_player(1)
    bazaar_gui.close(1)
    storage_rental.VAULT_SLOTS = 50
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    local saved = storage.gb_test_storage
    if saved then
      test_helpers.set_balance(state(), saved.balance)
      state().reputation = saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      technology().researched = saved.researched
      storage.incoming_contracts.rng[force_index()] = saved.rng
      storage.gb_test_storage = nil
    end
    state().contracts.open = {}
    storage.vaults.leases = {}
  end)

  test("both buildings are unlocked by Storage rental; the warehouse is closed to the player", function()
    local unlocked = {}
    for _, effect in pairs(prototypes.technology[vaults.TECHNOLOGY].effects) do
      if effect.type == "unlock-recipe" then unlocked[effect.recipe] = true end
    end
    assert.is_true(unlocked[vaults.UPLINK] and unlocked[warehouses.NAME])
    assert.is_false(place(warehouses.NAME, 3, 3).operable)
  end)

  test("a vault waits for its research and an import chest, then holds one period as guarantee", function()
    technology().researched = false
    assert.are.same({ nil, "not-researched" }, { vaults.rent(force_index(), hub.unit_number) })
    technology().researched = true
    local bare = place("gb-hub", 40)
    assert.are.same({ nil, "no-import-chest" }, { vaults.rent(force_index(), bare.unit_number) })
    local id = vaults.rent(force_index(), hub.unit_number)
    local contract = contracts.get(force_index(), id)
    assert.are.same({ "storage", core.ACTIVE }, { contract.kind, contract.state })
    assert.are.equal(storage_rental.vault_charge(storage_rental.VAULT_SLOTS), contract.deposit)
    assert.is_true(math.abs(1e6 - contract.deposit - state().balance) < 1e-6)
  end)

  test("an uplink sends plain goods into the vault up to its stacks, and keeps the rest", function()
    storage_rental.VAULT_SLOTS = 3
    local id = vaults.rent(force_index(), hub.unit_number)
    local uplink = place(vaults.UPLINK, 3, 3)
    chest(uplink).insert({ name = "iron-plate", count = 150 })
    chest(uplink).insert({ name = "copper-plate", count = 150 })
    chest(uplink).insert({ name = "iron-gear-wheel", count = 10 })
    upload_all()
    assert.are.same({ ["iron-plate"] = 150, ["copper-plate"] = 100 }, vaults.lease(id).goods)
    assert.are.equal(50, chest(uplink).get_item_count("copper-plate"))
    assert.are.equal(10, chest(uplink).get_item_count("iron-gear-wheel"))
    assert.are.equal(3, vaults.stacks(id))
    assert.is_true(storage.vaults.uplinks[uplink.unit_number].held)
  end)

  test("an uplink keeps damaged goods and feeds no vault rented at another hub", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    local far_hub = place("gb-hub", 40)
    local uplink = place(vaults.UPLINK, 40, 3)
    chest(uplink).insert({ name = "iron-plate", count = 10 })
    upload_all()
    assert.are.same({}, vaults.lease(id).goods)
    assert.are.equal(far_hub.unit_number, storage.vaults.uplinks[uplink.unit_number].hub)
    local near = place(vaults.UPLINK, 3, 3)
    chest(near).insert({ name = "stone-furnace", count = 1, health = 0.5 })
    upload_all()
    assert.are.same({}, vaults.lease(id).goods)
    assert.are.equal(1, chest(near).get_item_count("stone-furnace"))
  end)

  test("Retrieve ships the goods back to the hub by orbital capsule, the vault staying rented", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 300 }
    assert.is_true(vaults.retrieve(force_index(), id))
    assert.are.same({}, vaults.lease(id).goods)
    local capsule = freight.capsules(hub.unit_number)[1]
    assert.are.same({ "iron-plate", 300, 0 }, { capsule.name, capsule.count, capsule.unit_cost })
    assert.is_nil(capsule.contract)
    assert.are.equal(id, capsule.vault.id)
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
  end)

  test("Retrieve ships what the capsule queue takes and keeps the rest; an ended vault ships it all in turn",
    function()
      local id = vaults.rent(force_index(), hub.unit_number)
      local names = item_names(25)
      for _, name in ipairs(names) do vaults.lease(id).goods[name] = 1 end
      local queue = freight.TIERS.capsule.max_capsules
      assert.are.same({ true, 25 - queue }, { vaults.retrieve(force_index(), id) })
      assert.are.equal(queue, #freight.capsules(hub.unit_number))
      assert.are.same({ false, "queue-full" }, { vaults.retrieve(force_index(), id) })
      storage.freight.hubs[hub.unit_number] = nil
      for _, name in ipairs(names) do vaults.lease(id).goods[name] = 1 end
      contracts.abandon(force_index(), id)
      vaults.on_sweep_tick()
      assert.are.same({ 25 - queue, 1 }, { vaults.returning(force_index()) })
      storage.freight.hubs[hub.unit_number] = nil
      vaults.on_sweep_tick()
      assert.is_nil(vaults.lease(id))
      assert.are.same({ 0, 0 }, { vaults.returning(force_index()) })
    end)

  test("Retrieve goes only to the vault's own hub, which needs an import chest", function()
    local bare = place("gb-hub", 40)
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).hub = bare.unit_number
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    assert.are.same({ false, "no-import-chest" }, { vaults.retrieve(force_index(), id) })
    assert.are.equal(0, #freight.capsules(hub.unit_number))
  end)

  test("goods on their way back return to the vault when their hub is removed", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    vaults.retrieve(force_index(), id)
    local unit_number = hub.unit_number
    hub.destroy()
    freight.on_hub_removed(unit_number)
    assert.are.same({ ["iron-plate"] = 10 }, vaults.lease(id).goods)
    contracts.abandon(force_index(), id)
    vaults.on_sweep_tick()
    vaults.lease(id).goods = {}
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    freight.on_hub_removed(unit_number)
  end)

  test("a vault is charged even when its only hub is mined just before the charge", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    local charge = contracts.get(force_index(), id).charge
    local unit_number = hub.unit_number
    hub.destroy()
    local before = state().balance
    run_period(id)
    assert.is_true(math.abs(before - charge - state().balance) < 1e-6)
    assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
    freight.on_hub_removed(unit_number)
  end)

  test("a vault whose hub is gone takes over a hub built where it stood, and no other", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    local unit_number = hub.unit_number
    hub.destroy()
    local far = place("gb-hub", 40)
    place("gb-import-chest", 43)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id).hub)
    assert.are.same({ false, "no-hub" }, { vaults.retrieve(force_index(), id) })
    local before = state().balance
    run_period(id)
    assert.is_true(state().balance < before)
    local replacement = place("gb-hub", 5)
    vaults.on_sweep_tick()
    assert.are.equal(replacement.unit_number, vaults.lease(id).hub)
    assert.is_true(vaults.retrieve(force_index(), id))
    assert.are.equal(0, #freight.capsules(far.unit_number))
    freight.on_hub_removed(unit_number)
  end)

  test("an ended unattached vault returns its goods to any hub of its force on its surface", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    local unit_number = hub.unit_number
    hub.destroy()
    local far = place("gb-hub", 40)
    place("gb-import-chest", 43)
    vaults.on_sweep_tick()
    contracts.abandon(force_index(), id)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal(10, freight.capsules(far.unit_number)[1].count)
    freight.on_hub_removed(unit_number)
  end)

  test("a vault forgotten while its goods fly home is recreated when their hub is removed", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    contracts.abandon(force_index(), id)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    local unit_number = hub.unit_number
    hub.destroy()
    freight.on_hub_removed(unit_number)
    local lease = vaults.lease(id)
    assert.are.same({ force_index(), { ["iron-plate"] = 10 }, game.surfaces[1].name },
      { lease.force_index, lease.goods, lease.surface_name })
    assert.are.same({ 1, 1 }, { vaults.returning(force_index()) })
  end)

  test("goods flying home for a merged force come back to the destination when their hub is removed", function()
    local source = game.create_force("gb-test-vault-return")
    freight.ship(source.index, hub.unit_number, { { kind = "item", name = "iron-plate", count = 10 } }, nil, nil,
      { id = 999999, surface_index = hub.surface_index, surface_name = hub.surface.name })
    game.merge_forces(source, "player")
    after_ticks(1, function()
      local unit_number = hub.unit_number
      hub.destroy()
      freight.on_hub_removed(unit_number)
      local lease = vaults.lease(999999)
      assert.are.same({ force_index(), { ["iron-plate"] = 10 } }, { lease.force_index, lease.goods })
    end)
  end)

  test("goods of a vault whose surface was deleted go to a hub of the force on another surface", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    local lease = vaults.lease(id)
    lease.goods, lease.surface_index, lease.hub = { ["iron-plate"] = 10 }, 9999, nil
    contracts.abandon(force_index(), id)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal(10, freight.capsules(hub.unit_number)[1].count)
  end)

  test("a surface index reused by another surface counts as deleted for a vault", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    local lease = vaults.lease(id)
    lease.goods, lease.surface_name, lease.hub = { ["iron-plate"] = 10 }, "gb-deleted-surface", nil
    contracts.abandon(force_index(), id)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal(10, freight.capsules(hub.unit_number)[1].count)
  end)

  test("a bankruptcy ends a vault, and its goods still come back", function()
    local fields = { "balance", "arrears", "bankruptcies", "bankruptcy_debt", "credit_ban_until", "insolvent_since" }
    local saved = {}
    for _, field in ipairs(fields) do saved[field] = state()[field] end
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 10 }
    insolvency.bankrupt(state(), game.tick)
    for _, field in ipairs(fields) do state()[field] = saved[field] end
    vaults.on_sweep_tick()
    assert.is_nil(contracts.get(force_index(), id))
    assert.is_nil(vaults.lease(id))
    assert.are.equal(10, freight.capsules(hub.unit_number)[1].count)
  end)

  test("a merged force's vaults carry over to the destination", function()
    local source = game.create_force("gb-test-vaults")
    test_helpers.set_balance(storage.forces[source.index], 1e6)
    local id = contracts.offer(source.index, storage_rental.vault("Test", 10))
    contracts.accept(source.index, id)
    storage.vaults.leases[id] = {
      force_index = source.index, hub = hub.unit_number, surface_index = hub.surface_index, goods = {},
    }
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.are.equal(force_index(), vaults.lease(id).force_index)
      assert.are.equal(core.ACTIVE, contracts.get(force_index(), id).state)
    end)
  end)

  test("each period is charged; a charge the funds cannot cover fails it and its goods still come back", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 100 }
    local charge = contracts.get(force_index(), id).charge
    local before = state().balance
    run_period(id)
    assert.is_true(math.abs(before - charge - state().balance) < 1e-6)
    local reputation = state().reputation
    test_helpers.set_balance(state(), -1e9)
    run_period(id)
    assert.is_nil(contracts.get(force_index(), id))
    assert.are.equal(reputation - 1, state().reputation)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal("iron-plate", freight.capsules(hub.unit_number)[1].name)
  end)

  test("at the end of its term the guarantee comes back and the goods are shipped home", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 100 }
    local contract = contracts.get(force_index(), id)
    contract.due_tick = game.tick
    contract.next_installment = game.tick + 1
    local before = state().balance
    contracts.on_settle_tick({ tick = game.tick + 1 })
    assert.are.equal(core.FULFILLED, contract.state)
    assert.is_true(math.abs(before + contract.deposit - state().balance) < 1e-6)
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal(100, freight.capsules(hub.unit_number)[1].count)
  end)

  test("goods of an ended vault whose hub is gone go to another hub on its surface", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 100 }
    contracts.abandon(force_index(), id)
    local other = place("gb-hub", 40)
    place("gb-import-chest", 43)
    hub.destroy()
    vaults.on_sweep_tick()
    assert.is_nil(vaults.lease(id))
    assert.are.equal(100, freight.capsules(other.unit_number)[1].count)
  end)

  test("rent and retrieve from the Contracts tab", function()
    bazaar_gui.open(player, "contracts", hub)
    local window = player.gui.screen.gb_bazaar
    bazaar_gui.on_gui_input({ element = find(window, "vault-rent"), player_index = 1 })
    local vault = contracts.listed(force_index())[1]
    assert.are.equal("storage", vault.kind)
    vaults.lease(vault.id).goods = { ["iron-plate"] = 10 }
    bazaar_gui.refresh(player)
    local retrieve = find(window, "contract-retrieve", vault.id)
    assert.is_true(retrieve.enabled)
    bazaar_gui.on_gui_input({ element = retrieve, player_index = 1 })
    assert.are.same({}, vaults.lease(vault.id).goods)
    technology().researched = false
    bazaar_gui.refresh(player)
    assert.is_false(find(window, "vault-rent").enabled)
  end)

  test("an idle, empty warehouse is offered goods its force knows; acceptance stores them", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    technology().researched = false
    warehouses.on_offer_tick()
    assert.is_nil(storage.warehouses.chests[warehouse.unit_number].contract)
    technology().researched = true
    warehouses.on_offer_tick()
    local id = storage.warehouses.chests[warehouse.unit_number].contract
    local contract = contracts.get(force_index(), id)
    assert.are.same({ "warehouse", core.OFFERED }, { contract.kind, contract.state })
    assert.is_true(contract.reward > 0)
    assert.is_true(chest(warehouse).is_empty())
    assert.is_true(warehouses.accept(force_index(), id))
    local goods = contract.provides[1]
    assert.are.equal(goods.count, chest(warehouse).get_item_count(goods.name))
    assert.are.equal(core.ACTIVE, contract.state)
    assert.is_true(state().balance <= 1e6 - contract.deposit)
  end)

  -- Offers warehouse `entity` 200 iron plates, as an offer would, without the draw.
  local function offer_plates(entity)
    local id = contracts.offer(force_index(), {
      kind = "warehouse", counterparty = "Test", custody = true,
      provides = { { kind = "item", name = "iron-plate", count = 200 } },
      requires = { { kind = "item", name = "iron-plate", count = 200 } },
      reward = 48, deposit = 50, penalty = 300, duration_ticks = 36000, accept_ticks = 600,
    })
    storage.warehouses.chests[entity.unit_number].contract = id
    return id
  end

  test("a warehouse that is not empty is refused, changing nothing", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    chest(warehouse).insert({ name = "coal", count = 5 })
    assert.are.same({ false, "warehouse-not-empty" }, { warehouses.accept(force_index(), id) })
    assert.are.equal(1e6, state().balance)
    assert.are.equal(core.OFFERED, contracts.get(force_index(), id).state)
  end)

  test("the counterparty takes its goods back at maturity, and pays the rent with the guarantee, no reputation",
    function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    warehouses.accept(force_index(), id)
    local contract = contracts.get(force_index(), id)
    local before, reputation = state().balance, state().reputation
    warehouses.on_service_tick({ tick = game.tick })
    assert.are.equal(200, chest(warehouse).get_item_count("iron-plate"))
    contract.due_tick = game.tick + 30
    warehouses.on_service_tick({ tick = game.tick })
    assert.is_true(chest(warehouse).is_empty())
    contracts.on_settle_tick({ tick = game.tick })
    assert.are.equal(core.FULFILLED, contract.state)
    assert.is_true(math.abs(before + contract.reward + core.guarantee(contract) - state().balance) < 1e-6)
    assert.are.equal(reputation, state().reputation)
    warehouses.on_service_tick({ tick = game.tick })
    assert.is_nil(storage.warehouses.chests[warehouse.unit_number].contract)
  end)

  test("goods taken out fail the contract at its deadline, and the rest go back to the counterparty", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    warehouses.accept(force_index(), id)
    chest(warehouse).remove({ name = "iron-plate", count = 50 })
    local contract = contracts.get(force_index(), id)
    contract.due_tick = game.tick + 30
    warehouses.on_service_tick({ tick = game.tick })
    contracts.on_settle_tick({ tick = game.tick + 31 })
    assert.are.equal(core.FAILED, contract.state)
    chest(warehouse).insert({ name = "iron-plate", count = 7 })
    warehouses.on_service_tick({ tick = game.tick + 31 })
    assert.is_true(chest(warehouse).is_empty())
    assert.is_nil(storage.warehouses.chests[warehouse.unit_number].contract)
  end)

  test("acceptance holds the cost of buying the goods back, plus the margin", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    local cost = market.preview(force_index(), "item", "iron-plate", "buy", 200)
    warehouses.accept(force_index(), id)
    local contract = contracts.get(force_index(), id)
    assert.is_true(math.abs(storage_rental.warehouse_penalty(300, cost) - contract.penalty) < 1e-6)
    assert.is_true(contract.penalty >= cost)
  end)

  test("mining a rented warehouse hands its goods over and fails the contract at its deadline", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    warehouses.accept(force_index(), id)
    local unit_number = warehouse.unit_number
    local inventory = game.create_inventory(10)
    warehouse.mine({ inventory = inventory, force = true })
    assert.are.equal(200, inventory.get_item_count("iron-plate"))
    inventory.destroy()
    warehouses.forget(unit_number)
    local contract = contracts.get(force_index(), id)
    local reputation = state().reputation
    contracts.on_settle_tick({ tick = contract.due_tick + 1 })
    assert.are.same({ core.FAILED, reputation - 1 }, { contract.state, state().reputation })
  end)

  test("a destroyed warehouse leaves its contract to fail at the deadline", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    warehouses.accept(force_index(), id)
    local unit_number = warehouse.unit_number
    warehouse.destroy()
    warehouses.forget(unit_number)
    local contract = contracts.get(force_index(), id)
    contracts.on_settle_tick({ tick = contract.due_tick + 1 })
    assert.are.equal(core.FAILED, contract.state)
  end)

  test("both buildings show their status and are listed among their hub's modules", function()
    local uplink = place(vaults.UPLINK, 3, 3)
    local warehouse = place(warehouses.NAME, 4, 3)
    assert.are.equal("gb-status.uplink-no-vault", entity_status.shown(uplink.unit_number).label[1])
    assert.are.equal("gb-status.warehouse-idle", entity_status.shown(warehouse.unit_number).label[1])
    local listed = {}
    entity_status.each_module_of(hub.unit_number, force_index(), function(unit_number, _, entity, descriptor)
      listed[unit_number] = { entity.name, descriptor.label[1] }
    end)
    assert.are.same({ vaults.UPLINK, "gb-status.uplink-no-vault" }, listed[uplink.unit_number])
    assert.are.same({ warehouses.NAME, "gb-status.warehouse-idle" }, listed[warehouse.unit_number])
  end)

  -- Average time of `pass` over 10 runs, each after `setup` (not timed), logged with `label`.
  local function measure(label, setup, pass)
    local profiler = helpers.create_profiler(true)
    for _ = 1, 10 do
      setup()
      profiler.restart()
      pass()
      profiler.stop()
    end
    profiler.divide(10)
    log({ "", "[galactic-bazaar] storage rental: ", label, " (average of 10): ", profiler })
  end

  test("measures the uplink pass moving goods and with full vaults, and the warehouse pass", function()
    local ids = {}
    while #ids < contracts.MAX_LISTED do ids[#ids + 1] = vaults.rent(force_index(), hub.unit_number) end
    local names = item_names(20)
    local uplinks = {}
    for dx = -1, 7 do
      for dy = 3, 4 do uplinks[#uplinks + 1] = place(vaults.UPLINK, dx, dy) end
    end
    -- Each uplink: one full stack of 20 storable items, and 28 armours no vault takes (carrying data).
    local function fill(empty_vaults)
      for _, id in ipairs(ids) do
        vaults.lease(id).goods = empty_vaults and {} or { ["iron-plate"] = storage_rental.VAULT_SLOTS * 100 }
      end
      for _, uplink in ipairs(uplinks) do
        local inventory = chest(uplink)
        inventory.clear()
        for _, name in ipairs(names) do inventory.insert({ name = name, count = prototypes.item[name].stack_size }) end
        inventory.insert({ name = "modular-armor", count = 28 })
      end
    end
    local function second() for _ = 1, 60 / vaults.UPLINK_TICKS do vaults.on_uplink_tick() end end
    measure("10 uplink passes (one second) moving into 8 empty vaults, 18 uplinks of 48 stacks",
      function() fill(true) end, second)
    assert.are.equal(28, chest(uplinks[1]).get_item_count("modular-armor"))
    local stored = 0
    for _, id in ipairs(ids) do stored = stored + vaults.stacks(id) end
    assert.is_true(stored > 0 and stored <= 60 / vaults.UPLINK_TICKS * vaults.MAX_MOVES)
    measure("one uplink pass moving into empty vaults (" .. vaults.UPLINK_BATCH .. " uplinks, at most "
      .. vaults.MAX_MOVES .. " stacks)", function() fill(true) end, vaults.on_uplink_tick)
    measure("10 uplink passes (one second) with 8 full vaults, 18 uplinks of 48 stacks", function() fill(false) end,
      second)
    measure("one uplink pass with 8 full vaults", function() fill(false) end, vaults.on_uplink_tick)
    -- Vaults with room, uplinks holding only goods no vault takes: 48 armours each.
    local function armours()
      for _, id in ipairs(ids) do vaults.lease(id).goods = {} end
      for _, uplink in ipairs(uplinks) do
        chest(uplink).clear()
        chest(uplink).insert({ name = "modular-armor", count = 48 })
      end
    end
    measure("one uplink pass, vaults with room, uplinks holding only goods no vault takes", armours,
      vaults.on_uplink_tick)
    assert.are.equal(48, chest(uplinks[1]).get_item_count("modular-armor"))
    local rented = {}
    for dx = -1, 7 do
      local warehouse = place(warehouses.NAME, dx, -4)
      local id = offer_plates(warehouse)
      assert.is_true(warehouses.accept(force_index(), id))
      rented[#rented + 1] = { warehouse = warehouse, contract = contracts.get(force_index(), id) }
    end
    local function service() warehouses.on_service_tick({ tick = game.tick }) end
    measure("warehouse pass, 9 rented warehouses before maturity", function() end, service)
    measure("warehouse pass, 9 rented warehouses collected at maturity", function()
      for _, entry in ipairs(rented) do
        entry.contract.due_tick, entry.contract.delivered["item/iron-plate"] = game.tick + 30, 0
        chest(entry.warehouse).clear()
        chest(entry.warehouse).insert({ name = "iron-plate", count = 200 })
      end
    end, service)
    assert.is_true(chest(rented[1].warehouse).is_empty())
  end)

  test("keep a rented warehouse across a save and reload", function()
    local warehouse = place(warehouses.NAME, 3, 3)
    local id = offer_plates(warehouse)
    warehouses.accept(force_index(), id)
    storage.gb_test_warehouse = { id = id, unit_number = warehouse.unit_number, created = created }
  end).after_reload_mods(function()
    -- After a reload the file runs again and its locals start empty: this test cleans up itself.
    local saved = storage.gb_test_warehouse
    local module = storage.warehouses.chests[saved.unit_number]
    local kept = module ~= nil and module.contract == saved.id and module.stored[1] == "iron-plate"
      and module.entity.get_inventory(defines.inventory.chest).get_item_count("iron-plate") == 200
    for _, entity in ipairs(saved.created) do
      if entity.valid then entity.destroy() end
    end
    storage.gb_test_warehouse = nil
    assert.is_true(kept)
  end)

  test("keep a vault and its goods across a save and reload", function()
    local id = vaults.rent(force_index(), hub.unit_number)
    vaults.lease(id).goods = { ["iron-plate"] = 42 }
    storage.gb_test_vault = { id = id, created = created }
  end).after_reload_mods(function()
    -- After a reload the file runs again and its locals start empty: this test cleans up itself.
    local saved = storage.gb_test_vault
    local lease = storage.vaults.leases[saved.id]
    local kept = lease ~= nil and lease.goods["iron-plate"] == 42
      and contracts.get(game.forces.player.index, saved.id).state == core.ACTIVE
    for _, entity in ipairs(saved.created) do
      if entity.valid then entity.destroy() end
    end
    storage.gb_test_vault = nil
    assert.is_true(kept)
  end)
end)
