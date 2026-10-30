-- In-game tests of the manifold module (scripts/manifold.lua, #63): fluids sold from export
-- manifolds, bought into import manifolds by orbital capsule, and listed in the market window.
local freight = require("scripts.freight")
local manifold = require("scripts.manifold")

local surface, created
local function place(name, x, y)
  local entity = surface.create_entity({
    name = name, position = { x, y or 150 }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function player_state() return storage.forces[game.forces.player.index] end
local OIL = "crude-oil"

describe("manifold module", function()
  local saved_balance, hub
  before_each(function()
    surface = game.surfaces[1]
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 1e6
    player_state().markets["fluid/" .. OIL] = nil
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
    if saved_balance then player_state().balance = saved_balance end
    player_state().markets["fluid/" .. OIL] = nil
  end)

  test("is unlocked by the fluid trading technology", function()
    local unlocks = {}
    for _, effect in pairs(prototypes.technology["gb-fluid-trading"].effects) do
      if effect.type == "unlock-recipe" then unlocks[effect.recipe] = true end
    end
    assert.is_true(unlocks["gb-fluid-export"] and unlocks["gb-fluid-import"])
  end)

  test("sells the fluid of an export manifold, and credits the force", function()
    local tank = place("gb-fluid-export", 4)
    tank.insert_fluid({ name = OIL, amount = 1000 })
    manifold.on_sell_tick()
    assert.is_true(tank.get_fluid_count(OIL) < 1)
    assert.is_true(player_state().balance > 1e6)
  end)

  test("sells nothing without a powered hub", function()
    local tank = place("gb-fluid-export", 4)
    tank.insert_fluid({ name = OIL, amount = 1000 })
    hub.energy = 0
    manifold.on_sell_tick()
    assert.are.equal(1000, tank.get_fluid_count(OIL))
    assert.are.equal(1e6, player_state().balance)
  end)

  test("buys fluid into an import manifold by orbital capsule", function()
    local tank = place("gb-fluid-import", 4)
    local ok, _, _, arrival = freight.order(game.forces.player.index, hub.unit_number, OIL, 1000, nil, nil, "fluid")
    assert.is_true(ok)
    assert.are.equal("fluid", freight.capsules(hub.unit_number)[1].kind)
    freight.on_unload_tick({ tick = arrival })
    assert.are.near(1000, tank.get_fluid_count(OIL), 1e-6)
    assert.are.equal(0, freight.queued(hub.unit_number))
  end)

  test("refuses to buy fluid without an import manifold, changing nothing", function()
    local ok, reason = freight.order(game.forces.player.index, hub.unit_number, OIL, 1000, nil, nil, "fluid")
    assert.is_false(ok)
    assert.are.equal("no-import-manifold", reason)
    assert.are.equal(1e6, player_state().balance)
  end)

  test("keeps its manifolds across a save and reload", function()
    storage.gb_test_manifold = { tank = place("gb-fluid-import", 4).unit_number, hub = hub.unit_number }
  end).after_reload_mods(function()
    local saved = storage.gb_test_manifold
    local module = storage.manifold.modules[saved.tank]
    assert.are.equal("import", module.kind)
    assert.are.equal(saved.hub, module.hub)
    module.entity.destroy()
    storage.hubs[saved.hub].entity.destroy()
    storage.gb_test_manifold = nil
  end)
end)
