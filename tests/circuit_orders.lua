-- In-game tests of order combinators (scripts/circuit_orders.lua, ADR-0011): buy orders from circuit
-- signals, one per item and period, within a budget.
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

-- A constant combinator wired to the order combinator, emitting `signals` ({name, count} items, or
-- {type, name, count}).
local function emit(orders_combinator, signals)
  local source = place("constant-combinator", orders_combinator.position.x - 2, orders_combinator.position.y)
  local section = source.get_or_create_control_behavior().add_section()
  for i, signal in ipairs(signals) do
    section.set_slot(i, { value = { type = signal.type or "item", name = signal.name, quality = "normal",
      comparator = "=" }, min = signal.count })
  end
  source.get_wire_connector(W.circuit_red, true).connect_to(orders_combinator.get_wire_connector(W.circuit_red, true))
  return source
end

describe("order combinator", function()
  local saved_balance, hub, chest
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
    player_state().markets["item/iron-gear-wheel"] = nil
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
    player_state().markets["item/iron-gear-wheel"] = nil
  end)

  test("is unlocked by the market orders technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-market-orders"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-order-combinator"])
  end)

  test("buys the units its input asks for, once per period", function()
    local combinator = place("gb-order-combinator", 3)
    emit(combinator, { { name = "iron-gear-wheel", count = 50 } })
    after_ticks(2, function()
      circuit_orders.on_order_tick()
      assert.are.equal(1, freight.queued(hub.unit_number))
      assert.are.equal(50, freight.capsules(hub.unit_number)[1].count)
      assert.is_true(player_state().balance < 1e6)
    end)
  end)

  test("stays within the budget signal, or a tenth of the balance without one", function()
    local combinator = place("gb-order-combinator", 3)
    emit(combinator, { { name = "iron-gear-wheel", count = 50 }, { type = "virtual", name = "gb-credits", count = 1 } })
    after_ticks(2, function()
      circuit_orders.on_order_tick()
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.are.equal(1e6, player_state().balance)
      player_state().balance = 100
      local fresh = place("gb-order-combinator", 3, 116)
      emit(fresh, { { name = "iron-gear-wheel", count = 50 } })
      after_ticks(2, function()
        circuit_orders.on_order_tick()
        assert.is_true(player_state().balance >= 90 - 1e-6)
      end)
    end)
  end)

  test("ignores negative, fluid and untradeable signals", function()
    local combinator = place("gb-order-combinator", 3)
    emit(combinator, { { name = "iron-gear-wheel", count = -50 }, { type = "fluid", name = "water", count = 100 },
      { name = "blueprint", count = 1 } })
    after_ticks(2, function()
      circuit_orders.on_order_tick()
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.are.equal(1e6, player_state().balance)
    end)
  end)

  test("orders nothing without a powered hub, and emits nothing itself", function()
    local combinator = place("gb-order-combinator", 3)
    emit(combinator, { { name = "iron-gear-wheel", count = 50 } })
    hub.energy = 0
    after_ticks(2, function()
      circuit_orders.on_order_tick()
      assert.are.equal(0, freight.queued(hub.unit_number))
      assert.is_false(combinator.operable)
      assert.are.equal(0, combinator.get_control_behavior().sections_count)
    end)
  end)

  test("keeps its combinators across a save and reload", function()
    storage.gb_test_orders = {
      combinator = place("gb-order-combinator", 3).unit_number, hub = hub.unit_number, chest = chest.unit_number,
    }
  end).after_reload_mods(function()
    local module = storage.circuit_orders.modules[storage.gb_test_orders.combinator]
    assert.are.equal(storage.gb_test_orders.hub, module.hub)
    module.entity.destroy()
    storage.hubs[storage.gb_test_orders.hub].entity.destroy()
    storage.cargo.modules[storage.gb_test_orders.chest].entity.destroy()
    storage.gb_test_orders = nil
  end)
end)
