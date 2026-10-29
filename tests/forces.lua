-- In-game tests of the per-force economy state (scripts/forces.lua, ADR-0001).

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

describe("storage.forces", function()
  test("holds one state per existing force, each with an account", function()
    for _, force in pairs(game.forces) do
      local state = storage.forces[force.index]
      assert.is_table(state)
      assert.are.equal("number", type(state.balance))
      assert.is_table(state.journal)
    end
    assert.are.equal(count(game.forces), count(storage.forces))
  end)

  test("creates a state when a force is created", function()
    local force = game.create_force("gb-test-created")
    assert.is_table(storage.forces[force.index])
    game.merge_forces(force, "player")
  end)

  test("drops the source state and adds its balance when forces merge", function()
    local player_state = storage.forces[game.forces.player.index]
    local balance_before = player_state.balance
    local source = game.create_force("gb-test-merged")
    local source_index = source.index
    storage.forces[source_index].balance = 25
    game.merge_forces(source, "player")
    after_ticks(1, function()
      assert.is_nil(storage.forces[source_index])
      assert.are.equal(balance_before + 25, storage.forces[game.forces.player.index].balance)
      player_state.balance = balance_before
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
