-- In-game tests of the power module (scripts/power.lua, ADR-0009): the value of electricity, selling
-- a network's surplus, buying what it lacks, and the research levels.
local account = require("scripts.core.account")
local power = require("scripts.power")
local pricing = require("scripts.pricing")

local surface, created
local function place(name, x, y, force)
  local entity = surface.create_entity({
    name = name, position = { x, y or 60 }, force = force or "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local function level_2() return game.forces.player.technologies["gb-power-trading-2"] end
local MJ = 1e6

describe("power module", function()
  local saved_balance, hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
    player_state().markets["energy/electricity"] = nil
    hub = place("gb-hub", 0)
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    if saved_balance then player_state().balance = saved_balance end
    player_state().markets["energy/electricity"] = nil
    level_2().researched = false
  end)

  test("values electricity per megajoule from the cheapest chemical fuel", function()
    local electricity = pricing.base_value("energy", "electricity")
    log("[galactic-bazaar] electricity: " .. electricity .. " credits per MJ")
    assert.is_true(electricity > 0)
    assert.is_true(electricity <= pricing.base_value("item", "coal") / 4 + 1e-12)
  end)

  test("substations are unlocked by the power trading technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-power-trading"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-power-export"] and unlocks["gb-power-import"])
  end)

  test("sells what an export substation absorbed, and credits the force", function()
    local substation = place("gb-power-export", 3)
    substation.energy = 20 * MJ
    power.on_settle_tick()
    assert.is_true(substation.energy < 1)
    assert.is_true(player_state().balance > 1e6)
    local journal = player_state().journal
    assert.are.equal("energy/electricity", journal[#journal].key)
    assert.is_true(math.abs(journal[#journal].quantity - 20) < 1e-6)
  end)

  test("refills an import substation and debits the force for what it bought", function()
    local substation = place("gb-power-import", 3)
    substation.energy = 0
    power.on_settle_tick()
    local buffer = power.LEVEL_WATTS[1] * power.SETTLE_TICKS / 60
    assert.are.equal(buffer, substation.electric_buffer_size)
    assert.is_true(math.abs(substation.energy - buffer) < 1)
    local cost = 1e6 - player_state().balance
    assert.is_true(cost > 0)
    assert.is_true(math.abs(cost - pricing.base_value("energy", "electricity") * buffer / MJ) < 0.1 * cost)
  end)

  test("buys only what the force can pay", function()
    local substation = place("gb-power-import", 3)
    substation.energy = 0
    local floor = -account.overdraft_limit(player_state())
    player_state().balance = floor + 0.01
    power.on_settle_tick()
    assert.is_true(player_state().balance >= floor)
    assert.is_true(substation.energy > 0 and substation.energy < substation.electric_buffer_size)
  end)

  test("trades nothing without a powered hub in range", function()
    local substation = place("gb-power-export", 3)
    local far = place("gb-power-import", 40)
    substation.energy = 20 * MJ
    far.energy = 0
    hub.energy = 0
    power.on_settle_tick()
    assert.are.equal(20 * MJ, substation.energy)
    assert.are.equal(0, far.energy)
    assert.are.equal(1e6, player_state().balance)
  end)

  test("raises the throughput with the second research level", function()
    local substation = place("gb-power-import", 3)
    level_2().researched = true
    power.on_settle_tick()
    assert.are.equal(power.LEVEL_WATTS[2] * power.SETTLE_TICKS / 60, substation.electric_buffer_size)
  end)

  local function generator(watts)
    local entity = place("electric-energy-interface", 8)
    entity.electric_interface_mode = defines.electric_interface_mode.primary_output
    entity.power_production = watts / 60
    entity.electric_buffer_size = watts / 60
    return entity
  end

  test("charges an export substation from the network's surplus", function()
    generator(5 * MJ)
    place("medium-electric-pole", 5)
    local substation = place("gb-power-export", 3)
    after_ticks(30, function()
      assert.is_true(substation.energy > 0)
    end)
  end)

  test("does not charge an export substation while the network lacks power", function()
    generator(0.05 * MJ)
    place("medium-electric-pole", 5)
    place("radar", 11)
    place("medium-electric-pole", 9)
    local substation = place("gb-power-export", 3)
    after_ticks(30, function()
      assert.are.equal(0, substation.energy)
    end)
  end)

  test("does not let an import substation feed an export substation", function()
    place("medium-electric-pole", 5)
    local import = place("gb-power-import", 7)
    local export = place("gb-power-export", 3)
    import.energy = import.electric_buffer_size
    after_ticks(30, function()
      assert.are.equal(0, export.energy)
      assert.are.equal(import.electric_buffer_size, import.energy)
    end)
  end)

  test("neutralises energy made by the substation itself, and starts clones empty", function()
    local substation = place("gb-power-export", 3)
    substation.power_production = 10 * MJ / 60
    substation.energy = 5 * MJ
    local clone = substation.clone({ position = { 3, 70 } })
    created[#created + 1] = clone
    assert.are.equal(0, clone.energy)
    power.on_settle_tick()
    assert.are.equal(0, substation.power_production)
  end)

  test("ignores the hubs of another force", function()
    hub.destroy()
    local foreign = place("gb-hub", 0, 60, "enemy")
    foreign.energy = foreign.electric_buffer_size
    local substation = place("gb-power-export", 3)
    substation.energy = 20 * MJ
    power.on_settle_tick()
    assert.are.equal(20 * MJ, substation.energy)
  end)

  test("trades for the destination force after a force merge", function()
    local source = game.create_force("gb-test-power")
    local substation = place("gb-power-export", 3, 60, source)
    substation.energy = 20 * MJ
    game.merge_forces(source, "player")
    after_ticks(1, function()
      power.on_settle_tick()
      assert.is_true(substation.energy < 1)
      assert.is_true(player_state().balance > 1e6)
    end)
  end)

  test("journals a minute of settlements as one entry per direction", function()
    local substation = place("gb-power-export", 3)
    local saved_journal = player_state().journal
    player_state().journal = {}
    substation.energy = 20 * MJ
    power.on_settle_tick()
    substation.energy = 20 * MJ
    power.on_settle_tick()
    local journal = player_state().journal
    player_state().journal = saved_journal
    assert.are.equal(1, #journal)
    assert.is_true(math.abs(journal[1].quantity - 40) < 1e-6)
  end)

  test("measures a settlement of 200 substations around one hub", function()
    for i = 0, 199 do
      local x, y = -6 + (i % 7) * 2, 50 + math.floor(i / 7) * 2
      if not (x >= -1 and x <= 1 and y >= 59 and y <= 61) then
        place(i % 2 == 0 and "gb-power-export" or "gb-power-import", x, y).energy = MJ
      end
    end
    power.on_settle_tick()
    local profiler = helpers.create_profiler()
    power.on_settle_tick()
    profiler.stop()
    log({ "", "[galactic-bazaar] power settlement of ", table_size(storage.power.modules), " substations: ", profiler })
  end)

  test("keeps its substations across a save and reload", function()
    storage.gb_test_power = { substation = place("gb-power-export", 3).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local module = storage.power.modules[storage.gb_test_power.substation]
    assert.are.equal("export", module.kind)
    module.entity.destroy()
    storage.hubs[storage.gb_test_power.hub].entity.destroy()
    storage.gb_test_power = nil
  end)
end)
