-- In-game tests of the power module (scripts/power.lua, ADR-0009): the value of electricity, selling
-- a network's surplus, buying what it lacks, and the research levels.
local power = require("scripts.power")
local pricing = require("scripts.pricing")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({ name = name, position = { x, y or 60 }, force = "player", raise_built = true })
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
    player_state().balance = 1
    power.on_settle_tick()
    assert.is_true(player_state().balance >= 0)
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

  test("charges an export substation only from the network's surplus", function()
    local generator = place("electric-energy-interface", 8)
    generator.electric_interface_mode = defines.electric_interface_mode.primary_output
    generator.power_production = 5 * MJ / 60
    generator.electric_buffer_size = 10 * MJ
    place("medium-electric-pole", 5)
    local substation = place("gb-power-export", 3)
    after_ticks(30, function()
      assert.is_true(substation.energy > 0)
    end)
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
