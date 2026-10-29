-- In-game tests of the trading hub prototype and its registry (scripts/hubs.lua).
local hubs = require("scripts.hubs")

local function place_hub(position)
  return game.surfaces[1].create_entity({
    name = "gb-hub", position = position, force = "player", raise_built = true,
  })
end

describe("trading hub", function()
  test("is a powered building whose recipe is locked until researched", function()
    local prototype = prototypes.entity["gb-hub"]
    assert.are.equal("electric-energy-interface", prototype.type)
    assert.is_true(prototype.electric_energy_source_prototype ~= nil)
    assert.is_false(prototypes.recipe["gb-hub"].enabled)
    assert.are.equal("gb-hub", prototypes.item["gb-hub"].place_result.name)
  end)

  test("is registered when built and forgotten when destroyed", function()
    local entity = place_hub({ 0, 0 })
    local unit_number = entity.unit_number
    assert.are.equal(entity, hubs.get(unit_number))
    entity.destroy()
    after_ticks(1, function()
      assert.is_nil(storage.hubs[unit_number])
    end)
  end)

  test("stays registered across a save and reload", function()
    storage.gb_test_hub = place_hub({ 4, 0 }).unit_number
  end).after_reload_mods(function()
    local entity = hubs.get(storage.gb_test_hub)
    assert.is_true(entity ~= nil and entity.valid)
    entity.destroy()
    storage.gb_test_hub = nil
  end)
end)
