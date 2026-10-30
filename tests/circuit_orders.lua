-- In-game tests of order combinators (scripts/circuit_orders.lua, ADR-0011): buy orders from circuit
-- signals, one per item and period, within a budget the force shares.
local circuit_orders = require("scripts.circuit_orders")
local freight = require("scripts.freight")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 110 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local W = defines.wire_connector_id
local GEAR = "iron-gear-wheel"

-- A constant combinator wired (red) to each of `targets`, emitting `signals` ({name, count} items,
-- or {type, name, count}).
local function emit(targets, signals, x)
  local source = place("constant-combinator", x or -3, targets[1].position.y)
  local section = source.get_or_create_control_behavior().add_section()
  for i, signal in ipairs(signals) do
    section.set_slot(i, { value = { type = signal.type or "item", name = signal.name, quality = "normal",
      comparator = "=" }, min = signal.count })
  end
  for _, target in ipairs(targets) do
    source.get_wire_connector(W.circuit_red, true).connect_to(target.get_wire_connector(W.circuit_red, true))
  end
  return source
end

local function budget(count) return { type = "virtual", name = circuit_orders.BUDGET_SIGNAL, count = count } end

-- Runs every slot of the `n`-th order period after now.
local function run_period(n)
  local start = (math.floor(game.tick / circuit_orders.ORDER_TICKS) + n) * circuit_orders.ORDER_TICKS
  for slot = 0, circuit_orders.SLOTS - 1 do
    circuit_orders.on_pass_tick({ tick = start + slot * circuit_orders.PASS_TICKS })
  end
end

local function cost_of(units)
  local cost, fee = freight.preview(game.forces.player.index, GEAR, units)
  return cost + fee
end

describe("order combinator", function()
  local saved_balance, saved_journal, hub, chest
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    saved_journal = player_state().journal
    player_state().balance = 1e6
    player_state().journal = {}
    player_state().markets["item/" .. GEAR] = nil
    storage.circuit_orders.spent = {}
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
    chest = place("gb-import-chest", 0, 113)
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    if saved_balance then player_state().balance = saved_balance end
    if saved_journal then player_state().journal = saved_journal end
    player_state().markets["item/" .. GEAR] = nil
  end)

  test("is unlocked by the market orders technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-market-orders"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-order-combinator"])
  end)

  test("buys the units its input asks for, once per period, within its budget", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 50 }, budget(1e5) })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(1, freight.queued(hub.unit_number))
      assert.are.equal(50, freight.capsules(hub.unit_number)[1].count)
      assert.is_true(player_state().balance < 1e6)
    end)
  end)

  test("buys nothing without a positive budget signal", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 50 }, budget(-1) })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.are.equal(1e6, player_state().balance)
    end)
  end)

  test("refuses an input carrying a price combinator's balance signal", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 50 }, budget(1e5),
      { type = "virtual", name = circuit_orders.REFUSED_SIGNAL, count = 1e6 } })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(0, freight.queued(hub.unit_number))
    end)
  end)

  test("shares one budget between the force's combinators in a period", function()
    local first = place("gb-order-combinator", 3, 110)
    local second = place("gb-order-combinator", 3, 116)
    emit({ first, second }, { { name = GEAR, count = 50 }, budget(cost_of(50) * 1.5) })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(1, freight.queued(hub.unit_number))
    end)
  end)

  test("ignores negative and untradeable signals, and fluids without an import manifold", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = -50 }, { type = "fluid", name = "water", count = 100 },
      { name = "blueprint", count = 1 }, budget(1e5) })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.are.equal(1e6, player_state().balance)
    end)
  end)

  test("buys fluids into an import manifold", function()
    place("gb-fluid-import", 5, 110)
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { type = "fluid", name = "crude-oil", count = 1000 }, budget(1e5) })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(1, freight.queued(hub.unit_number))
      assert.are.equal("fluid", freight.capsules(hub.unit_number)[1].kind)
      player_state().markets["fluid/crude-oil"] = nil
    end)
  end)

  test("removes signals put on it, without reading them as orders", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { budget(1e5) })
    local behavior = combinator.get_control_behavior()
    behavior.enabled = true
    behavior.add_section().set_slot(1, { value = { type = "item", name = GEAR, quality = "normal",
      comparator = "=" }, min = 50 })
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.are.equal(0, behavior.sections_count)
      assert.is_false(behavior.enabled)
    end)
  end)

  test("orders nothing without a powered hub, and cannot be opened", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 50 }, budget(1e5) })
    hub.energy = 0
    after_ticks(2, function()
      run_period(1)
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.is_false(combinator.operable)
    end)
  end)

  test("merges a minute of recurring orders into one journal entry per kind", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 10 }, budget(1e5) })
    after_ticks(2, function()
      run_period(1)
      run_period(2)
      local kinds = {}
      for _, entry in ipairs(player_state().journal) do kinds[entry.kind] = (kinds[entry.kind] or 0) + 1 end
      assert.are.same({ buy = 1, freight = 1 }, kinds)
      assert.are.equal(2, freight.queued(hub.unit_number))
    end)
  end)

  test("measures a pass of 50 combinators asking for 5 items each", function()
    local combinators = {}
    for i = 0, 49 do
      combinators[#combinators + 1] = place("gb-order-combinator", -8 + (i % 10) * 2, 104 + math.floor(i / 10) * 3)
    end
    emit(combinators, { { name = GEAR, count = 1 }, { name = "iron-plate", count = 1 },
      { name = "copper-plate", count = 1 }, { name = "coal", count = 1 }, { name = "stone", count = 1 },
      budget(1e5) }, -12)
    after_ticks(2, function()
      local start = (math.floor(game.tick / circuit_orders.ORDER_TICKS) + 1) * circuit_orders.ORDER_TICKS
      local profiler = helpers.create_profiler()
      for slot = 0, circuit_orders.SLOTS - 1 do
        circuit_orders.on_pass_tick({ tick = start + slot * circuit_orders.PASS_TICKS })
      end
      profiler.stop()
      profiler.divide(circuit_orders.SLOTS)
      log({ "", "[galactic-bazaar] order pass (50 combinators, 5 items each), average: ", profiler })
    end)
  end)

  test("keeps ordering after a save and reload", function()
    local combinator = place("gb-order-combinator", 3)
    emit({ combinator }, { { name = GEAR, count = 50 }, budget(1e5) })
    storage.gb_test_orders = { hub = hub.unit_number, chest = chest.unit_number, combinator = combinator.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_orders
    run_period(1)
    local queued = freight.queued(saved.hub)
    storage.freight.hubs[saved.hub] = nil
    for _, entity in ipairs(game.surfaces[1].find_entities_filtered({ area = { { -10, 100 }, { 10, 120 } } })) do
      if entity.name ~= "character" then entity.destroy() end
    end
    storage.gb_test_orders = nil
    assert.are.equal(1, queued)
  end)
end)
