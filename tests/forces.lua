-- In-game tests of the per-force economy state (scripts/forces.lua, ADR-0001).

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

describe("storage.forces", function()
  test("holds one state per existing force", function()
    for _, force in pairs(game.forces) do
      assert.is_table(storage.forces[force.index])
    end
    assert.are.equal(count(game.forces), count(storage.forces))
  end)

  test("creates a state when a force is created", function()
    local force = game.create_force("gb-test-created")
    assert.is_table(storage.forces[force.index])
    game.merge_forces(force, "player")
  end)

  test("drops the source state when forces merge", function()
    local source = game.create_force("gb-test-merged")
    local source_index = source.index
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.is_nil(storage.forces[source_index])
      assert.is_table(storage.forces[game.forces.player.index])
    end)
  end)

  test("survives a save and reload", function()
    storage.forces[game.forces.player.index].gb_test_marker = true
  end).after_reload_mods(function()
    local state = storage.forces[game.forces.player.index]
    assert.is_true(state.gb_test_marker)
    state.gb_test_marker = nil
  end)
end)
