-- In-game tests of the buildings' status (scripts/entity_status.lua, #106): the custom status of each
-- kind of building in its main states, the alert drawn while one is stopped, the refresh cycle, its
-- cost, saves that predate the status, and a save and reload.
local test_helpers = require("tests.helpers")
local account = require("scripts.core.account")
local cargo = require("scripts.cargo")
local catapult = require("scripts.catapult")
local circuit_orders = require("scripts.circuit_orders")
local contracts = require("scripts.contracts")
local entity_status = require("scripts.entity_status")
local power = require("scripts.power")
local price_signals = require("scripts.price_signals")

local Y = 410
local MJ = 1e6
local W = defines.wire_connector_id
local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or Y }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end

-- The status a building shows after a refresh: its label's key, its parameters (read back, numbers
-- become strings) and its diode.
local function status_of(entity)
  entity_status.on_built(entity)
  local custom = entity.custom_status
  return custom.label[1], custom.label, custom.diode
end

local function alert_of(entity)
  return storage.entity_status.alerts[entity.unit_number]
end

-- Runs passes until every listed building was refreshed and a new cycle started.
local function run_cycle()
  local cycle = storage.entity_status
  cycle.cursor, cycle.pending = 1, {}
  local visits = math.min(entity_status.MAX_VISITS, math.ceil(#cycle.units / entity_status.PASSES))
  for _ = 1, math.ceil(#cycle.units / visits) + 1 do entity_status.on_pass_tick({ tick = game.tick }) end
end

-- A constant combinator wired (red) to `target`, emitting `signals` ({type, name, count}).
local function emit(target, signals)
  local source = place("constant-combinator", target.position.x - 3, target.position.y)
  local section = source.get_or_create_control_behavior().add_section()
  for i, signal in ipairs(signals) do
    section.set_slot(i, { value = { type = signal.type or "item", name = signal.name, quality = "normal",
      comparator = "=" }, min = signal.count })
  end
  source.get_wire_connector(W.circuit_red, true).connect_to(target.get_wire_connector(W.circuit_red, true))
end

-- The tick of an order combinator's reading in the next order period.
local function reading_tick(combinator)
  local period = math.floor(game.tick / circuit_orders.ORDER_TICKS) + 1
  local slot = combinator.unit_number % circuit_orders.SLOTS
  return period * circuit_orders.ORDER_TICKS + slot * circuit_orders.PASS_TICKS
end

local D = defines.entity_status_diode

describe("building status", function()
  local hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    storage.gb_test_status = { balance = state().balance, reputation = state().reputation }
    test_helpers.set_balance(state(), 1e6)
    storage.circuit_orders.spent = {}
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    local saved = storage.gb_test_status
    if saved then
      test_helpers.set_balance(state(), saved.balance)
      state().reputation = saved.reputation
      storage.gb_test_status = nil
    end
    for id, contract in pairs(state().contracts.open) do
      if contract.counterparty == "Status test" then state().contracts.open[id] = nil end
    end
    state().markets["energy/electricity"] = nil
    state().markets["item/iron-gear-wheel"] = nil
    storage.circuit_orders.spent = {}
  end)

  test("draws its alerts with sprites the game has", function()
    for _, sprite in pairs(entity_status.ALERT_SPRITES) do assert.is_true(helpers.is_valid_sprite_path(sprite)) end
  end)

  test("works in a save that predates it: every handler creates what it needs", function()
    local chest = place("gb-export-chest", 3)
    storage.entity_status = nil
    storage.power.last = nil
    entity_status.on_pass_tick({ tick = game.tick })
    assert.is_true(storage.entity_status.index[chest.unit_number] ~= nil)
    storage.entity_status = nil
    entity_status.on_built(chest)
    storage.entity_status = nil
    entity_status.forget(chest.unit_number + 1e6)
    storage.power.last = nil
    power.on_settle_tick()
    storage.power.last = nil
    power.on_forces_merged({ source_index = 999 })
    assert.is_true(storage.power.last ~= nil)
    entity_status.init()
  end)

  test("writes a status only when it changed", function()
    local chest = place("gb-import-chest", 3)
    entity_status.on_built(chest)
    chest.custom_status = { diode = D.red, label = { "gb-status.no-hub" } }
    assert.are.equal("gb-status.no-hub", (status_of(chest)))
    storage.entity_status.shown[chest.unit_number] = nil
    assert.are.equal("gb-status.import-ready", (status_of(chest)))
  end)

  test("a module without a hub in range is red, with a no-hub alert that goes once a hub is built", function()
    local chest = place("gb-export-chest", 40)
    local key, _, diode = status_of(chest)
    assert.are.same({ "gb-status.no-hub", D.red }, { key, diode })
    local drawn = alert_of(chest)
    assert.are.equal("no-hub", drawn.alert)
    assert.is_true(rendering.get_object_by_id(drawn.sprite).valid)
    assert.is_true(rendering.get_object_by_id(drawn.text).only_in_alt_mode)
    local near = place("gb-hub", 42)
    near.energy = near.electric_buffer_size
    assert.are.equal("gb-status.export-empty", (status_of(chest)))
    assert.is_nil(alert_of(chest))
    assert.is_nil(rendering.get_object_by_id(drawn.sprite))
  end)

  test("redraws an alert for the building's new force, and drops it with the building", function()
    local chest = place("gb-export-chest", 40)
    status_of(chest)
    local first = alert_of(chest)
    chest.force = "enemy"
    status_of(chest)
    local second = alert_of(chest)
    assert.are.equal(game.forces.enemy.index, second.force_index)
    assert.is_nil(rendering.get_object_by_id(first.sprite))
    local unit_number = chest.unit_number
    chest.destroy()
    after_ticks(1, function()
      assert.is_nil(storage.entity_status.alerts[unit_number])
      assert.is_nil(storage.entity_status.index[unit_number])
      assert.is_nil(rendering.get_object_by_id(second.sprite))
    end)
  end)

  test("a hub counts its modules of its force and shipments while powered, and is red without power", function()
    place("gb-import-chest", 3)
    place("gb-export-chest", 4)
    run_cycle()
    local key, label, diode = status_of(hub)
    assert.are.same({ "gb-status.hub", "2", "0", D.green }, { key, label[2], label[3], diode })
    assert.are.same({ "gb-gui.tier-capsule" }, label[4])
    hub.energy = 0
    key, label, diode = status_of(hub)
    assert.are.same({ "gb-status.hub-unpowered", "2", D.red }, { key, label[2], diode })
    assert.are.equal("unpowered", alert_of(hub).alert)
  end)

  test("a hub without power stops the modules that trade, and warns those that work on", function()
    local export = place("gb-export-chest", 3)
    local import = place("gb-import-chest", 4)
    hub.energy = 0
    local key, _, diode = status_of(export)
    assert.are.same({ "gb-status.stopped-no-power", D.red }, { key, diode })
    assert.are.equal("hub-unpowered", alert_of(export).alert)
    local label
    key, label, diode = status_of(import)
    assert.are.same({ "gb-status.hub-unpowered-then", D.yellow }, { key, diode })
    assert.are.same({ "gb-status.import-ready" }, label[2])
    assert.is_nil(alert_of(import))
  end)

  test("an export chest waits, sells, or holds goods it cannot sell", function()
    local chest = place("gb-export-chest", 3)
    assert.are.equal("gb-status.export-empty", (status_of(chest)))
    chest.insert({ name = "iron-chest", count = 1, health = 0.5 })
    assert.are.equal("gb-status.export-selling", (status_of(chest)))
    storage.cargo.cursor = storage.cargo.modules[chest.unit_number].export_index
    cargo.on_export_tick()
    local key, _, diode = status_of(chest)
    assert.are.same({ "gb-status.export-held", D.yellow }, { key, diode })
  end)

  test("an import chest says when shipments are on the way to its hub", function()
    local chest = place("gb-import-chest", 3)
    assert.are.equal("gb-status.import-ready", (status_of(chest)))
    storage.freight.hubs[hub.unit_number] = { launches = {}, capsules = {
      { force_index = force().index, kind = "item", name = "iron-plate", count = 1, unit_cost = 0, arrival = 1e9 },
    } }
    local key, label = status_of(chest)
    assert.are.same({ "gb-status.import-receiving", "1" }, { key, label[2] })
  end)

  test("manifolds name the fluid they sell or hold", function()
    local export = place("gb-fluid-export", 4)
    local import = place("gb-fluid-import", -4)
    assert.are.equal("gb-status.fluid-export-empty", (status_of(export)))
    assert.are.equal("gb-status.fluid-import-ready", (status_of(import)))
    export.insert_fluid({ name = "water", amount = 100 })
    import.insert_fluid({ name = "water", amount = 100 })
    local key, label = status_of(export)
    assert.are.same({ "gb-status.fluid-export-selling", "[fluid=water]" }, { key, label[2] })
    key, label = status_of(import)
    assert.are.same({ "gb-status.fluid-import-holds", "[fluid=water]" }, { key, label[2] })
  end)

  test("power substations wait, then report what their force's last settlement traded", function()
    local export = place("gb-power-export", 3)
    local import = place("gb-power-import", -3)
    power.settlements()[force().index] = nil
    assert.are.equal("gb-status.power-export-waiting", (status_of(export)))
    assert.are.equal("gb-status.power-import-waiting", (status_of(import)))
    export.energy = 20 * MJ
    import.energy = 0
    power.on_settle_tick()
    local key, label = status_of(export)
    assert.are.same({ "gb-status.power-export", "20.0" }, { key, label[2] })
    assert.are.equal("gb-status.power-import", (status_of(import)))
  end)

  test("a price combinator waits for its first snapshot, then tells how many prices it emits", function()
    local combinator = place("gb-sell-price-combinator", 3)
    local saved = storage.price_signals.snapshots[force().index]
    storage.price_signals.snapshots[force().index] = nil
    storage.price_signals.builders[force().index] = nil
    assert.are.equal("gb-status.price-waiting", (status_of(combinator)))
    for _ = 1, 40 do
      if storage.price_signals.snapshots[force().index] then break end
      price_signals.on_pass_tick()
    end
    local key, label, diode = status_of(combinator)
    assert.are.same({ "gb-status.price-emitting-sell", D.green }, { key, diode })
    assert.are.equal(tostring(#storage.price_signals.snapshots[force().index].sell), label[2])
    if saved then storage.price_signals.snapshots[force().index] = saved end
  end)

  describe("order combinator", function()
    local combinator
    before_each(function()
      place("gb-import-chest", 0, Y + 3)
      combinator = place("gb-order-combinator", 3)
    end)

    local function read()
      circuit_orders.on_pass_tick({ tick = reading_tick(combinator) })
      return status_of(combinator)
    end

    test("waits for its first reading, then needs a budget", function()
      assert.are.equal("gb-status.order-waiting", (status_of(combinator)))
      local key, _, diode = read()
      assert.are.same({ "gb-status.order-no-budget", D.yellow }, { key, diode })
    end)

    test("reports what it ordered and the budget left", function()
      emit(combinator, { { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = 1e6 },
        { name = "iron-gear-wheel", count = 10 } })
      after_ticks(2, function()
        local key, label, diode = read()
        assert.are.same({ "gb-status.order-placed", "1", D.green }, { key, label[2], diode })
      end)
    end)

    test("stops when the hub's queue is full", function()
      local capsules = {}
      for i = 1, 20 do
        capsules[i] = { force_index = force().index, kind = "item", name = "iron-plate", count = 1, unit_cost = 0,
          arrival = 1e9, tier = "capsule" }
      end
      storage.freight.hubs[hub.unit_number] = { launches = {}, capsules = capsules }
      emit(combinator, { { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = 1e6 },
        { name = "iron-gear-wheel", count = 10 } })
      after_ticks(2, function() assert.are.equal("gb-status.order-queue-full", (read())) end)
    end)

    test("tells a spent budget from missing funds", function()
      emit(combinator, { { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = 100 },
        { name = "iron-gear-wheel", count = 10 } })
      after_ticks(2, function()
        storage.circuit_orders.spent[force().index] = {
          period = math.floor(reading_tick(combinator) / circuit_orders.ORDER_TICKS), credits = 100,
        }
        assert.are.equal("gb-status.order-budget-spent", (read()))
        storage.circuit_orders.spent = {}
        test_helpers.set_balance(state(), state().balance - account.available(state()) - 1)
        assert.are.equal("gb-status.order-no-funds", (read()))
      end)
    end)

    test("tells an order larger than the budget left from one larger than the funds", function()
      emit(combinator, { { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = 1 },
        { name = "iron-gear-wheel", count = 100 } })
      after_ticks(2, function()
        local key, label = read()
        assert.are.same({ "gb-status.order-over-budget", "1.00" }, { key, label[2] })
        emit(combinator, { { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = 1e6 } })
      end)
      after_ticks(4, function()
        test_helpers.set_balance(state(), state().balance - account.available(state()) + 1)
        assert.are.equal("gb-status.order-over-funds", (read()))
      end)
    end)
  end)

  test("a docking bay tells its fuel and the tier its hub actually ships by", function()
    local bay = place("gb-docking-bay", 3)
    local key, label, diode = status_of(bay)
    assert.are.same({ "gb-status.bay-no-fuel", "0", D.yellow }, { key, label[2], diode })
    assert.are.same({ "gb-gui.tier-capsule" }, label[4])
    bay.insert({ name = "rocket-fuel", count = 2 })
    key, label, diode = status_of(bay)
    assert.are.same({ "gb-status.bay-fueled", "200", D.green }, { key, label[2], diode })
    assert.are.same({ "gb-gui.tier-shuttle" }, label[4])
    local machine = place("gb-teleporter", -4)
    machine.energy = machine.electric_buffer_size
    assert.are.same({ "gb-gui.tier-teleporter" }, select(2, status_of(bay))[4])
  end)

  test("a teleporter is red with its own no-power alert until powered", function()
    local machine = place("gb-teleporter", 4)
    machine.energy = 0
    local key, _, diode = status_of(machine)
    assert.are.same({ "gb-status.teleporter-unpowered", D.red }, { key, diode })
    assert.are.equal("unpowered", alert_of(machine).alert)
    machine.energy = machine.electric_buffer_size
    assert.are.equal("gb-status.teleporter-powered", (status_of(machine)))
    assert.is_nil(alert_of(machine))
  end)

  test("a catapult tells its charge, and goods it holds below the floor", function()
    local machine = place("gb-catapult", 3)
    local module = storage.catapults.modules[machine.unit_number]
    module.capacitor.energy = 0
    local key, label = status_of(machine)
    assert.are.same({ "gb-status.catapult-charging", "0", "50" }, { key, label[2], label[3] })
    module.capacitor.energy = module.capacitor.electric_buffer_size
    key, label = status_of(machine)
    assert.are.same({ "gb-status.catapult-empty", "100" }, { key, label[2] })
    machine.insert({ name = "iron-chest", count = 1, health = 0.5 })
    assert.are.equal("gb-status.catapult-ready", (status_of(machine)))
    module.next_shot = 0
    catapult.shoot(module, game.tick)
    local held, _, diode = status_of(machine)
    assert.are.same({ "gb-status.catapult-held", D.yellow }, { held, diode })
  end)

  test("a contract chest lists what active incoming contracts still need", function()
    local chest = place("gb-contract-chest", 3)
    assert.are.equal("gb-status.contract-chest-idle", (status_of(chest)))
    local id = contracts.offer(force().index, {
      kind = "incoming", counterparty = "Status test", provides = {},
      requires = { { kind = "item", name = "iron-gear-wheel", count = 12 } },
      reward = 10, deposit = 0, penalty = 0, duration_ticks = 36000, accept_ticks = 600,
    })
    assert.is_true(contracts.accept(force().index, id))
    local key, label = status_of(chest)
    assert.are.same({ "gb-status.contract-chest-needs", { "", "[item=iron-gear-wheel] 12" } }, { key, label[2] })
  end)

  test("a rental assembler is idle, offered, then keeps the game's own status while rented", function()
    local machine = place("gb-rental-assembler", 5)
    assert.are.equal("gb-status.rental-idle", (status_of(machine)))
    local id = contracts.offer(force().index, {
      kind = "rental", counterparty = "Status test",
      provides = { { kind = "item", name = "iron-plate", count = 20 } },
      requires = { { kind = "item", name = "iron-gear-wheel", count = 10 } },
      reward = 300, deposit = 50, penalty = 100, duration_ticks = 36000, accept_ticks = 600,
      installment_ticks = 600,
    })
    local module = storage.rentals.machines[machine.unit_number]
    module.contract, module.recipe, module.crafts, module.provided = id, "iron-gear-wheel", 10, {}
    local key, label, diode = status_of(machine)
    assert.are.same({ "gb-status.rental-offered", tostring(id), D.yellow }, { key, label[2], diode })
    assert.is_true(contracts.accept(force().index, id))
    entity_status.on_built(machine)
    assert.is_nil(machine.custom_status)
    assert.is_false(storage.entity_status.shown[machine.unit_number])
  end)

  test("measures and logs a refresh pass with 1000 buildings", function()
    -- 20 hubs with 49 modules each: 1000 buildings, MAX_VISITS refreshed per pass.
    local names = { "gb-export-chest", "gb-import-chest", "gb-fluid-export", "gb-power-export",
      "gb-sell-price-combinator", "gb-order-combinator", "gb-docking-bay", "gb-catapult", "gb-contract-chest",
      "gb-rental-assembler" }
    for h = 0, 19 do
      local x, y = -40 + (h % 5) * 20, Y + 30 + math.floor(h / 5) * 20
      place("gb-hub", x, y).energy = 1e5
      for i = 0, 48 do
        place(names[i % #names + 1], x - 6 + 2 * (i % 7), y - 6 + 2 * math.floor(i / 7))
      end
    end
    local cycle = storage.entity_status
    assert.is_true(#cycle.units >= 1000)
    local passes = math.ceil(#cycle.units / entity_status.MAX_VISITS)
    -- A first cycle reads every hub once; the measured one is the steady state.
    for _ = 1, passes do entity_status.on_pass_tick({ tick = game.tick }) end
    local profiler = helpers.create_profiler()
    for _ = 1, passes do entity_status.on_pass_tick({ tick = game.tick }) end
    profiler.stop()
    profiler.divide(passes)
    -- The costliest pass: MAX_VISITS - 1 price combinators in a row (the dearest refresh without a
    -- costly read), then a docking bay whose hub's tier and fuel are not read yet (its two costly reads).
    local first = #cycle.units + 1
    for i = 0, entity_status.MAX_VISITS - 2 do place("gb-sell-price-combinator", -46 + i, Y + 37) end
    place("gb-docking-bay", -46 + entity_status.MAX_VISITS, Y + 37)
    cycle.cursor = first
    entity_status.on_pass_tick({ tick = game.tick })
    cycle.cursor = first
    cycle.facts.tiers, cycle.facts.fueled = nil, nil
    local worst = helpers.create_profiler()
    entity_status.on_pass_tick({ tick = game.tick })
    worst.stop()
    assert.are.equal(first + entity_status.MAX_VISITS, cycle.cursor)
    log({ "", "[galactic-bazaar] status refresh pass (", entity_status.MAX_VISITS, " of ", #cycle.units,
      " buildings): average ", profiler, "; costliest ", worst })
  end)

  test("a building removed before the cursor does not make the last one miss the cycle", function()
    for i = 1, 4 do place("gb-import-chest", 2 + i) end
    local cycle = storage.entity_status
    local last = cycle.units[#cycle.units]
    cycle.cursor, cycle.pending = #cycle.units, {}
    entity_status.forget(cycle.units[1])
    assert.are.equal(last, cycle.units[cycle.cursor])
    entity_status.on_pass_tick({ tick = game.tick })
    assert.is_true(storage.entity_status.shown[last] ~= nil)
    local counted = (cycle.pending[hub.unit_number] or 0) + (cycle.counts[hub.unit_number] or 0)
    assert.is_true(counted >= 1)
  end)

  test("keeps its alerts and refreshes across a save and reload", function()
    storage.gb_test_status_units = { chest = place("gb-export-chest", 40).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local units = storage.gb_test_status_units
    storage.gb_test_status_units = nil
    local unit_number = units.chest
    local chest = storage.cargo.modules[unit_number].entity
    created = { chest, storage.hubs[units.hub].entity }
    local drawn = storage.entity_status.alerts[unit_number]
    assert.are.equal("no-hub", drawn.alert)
    assert.is_true(rendering.get_object_by_id(drawn.sprite).valid)
    assert.are.equal("gb-status.no-hub", chest.custom_status.label[1])
    entity_status.on_pass_tick({ tick = game.tick })
  end)
end)
