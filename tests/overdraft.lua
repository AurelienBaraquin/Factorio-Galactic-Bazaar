-- In-game tests of the overdraft (ADR-0020): purchases below zero down to the limit, and the
-- interest charged every INTEREST_TICKS by the handler control.lua registers.
local account = require("scripts.core.account")
local forces = require("scripts.forces")
local market = require("scripts.market")

local function player_state() return storage.forces[game.forces.player.index] end
local function interest_entries()
  local count = 0
  for _, entry in ipairs(player_state().journal) do
    if entry.kind == account.INTEREST_KIND then count = count + 1 end
  end
  return count
end

describe("overdraft", function()
  -- Kept in storage, since a reload re-runs this file and resets its locals.
  before_each(function()
    storage.gb_test_overdraft = { balance = player_state().balance, journal = player_state().journal }
    player_state().journal = {}
    player_state().markets["item/iron-gear-wheel"] = nil
  end)
  after_each(function()
    local saved = storage.gb_test_overdraft
    player_state().balance, player_state().journal = saved.balance, saved.journal
    player_state().markets["item/iron-gear-wheel"] = nil
    storage.gb_test_overdraft = nil
  end)

  test("lets a force with no credits buy on overdraft, down to the limit", function()
    player_state().balance = 0
    local ok, cost = market.buy(game.forces.player.index, "item", "iron-gear-wheel", 10)
    assert.is_true(ok)
    assert.is_true(math.abs(player_state().balance + cost) < 1e-6)
    player_state().balance = 5 - account.overdraft_limit(player_state())
    local before = player_state().balance
    assert.are.same({ false, "insufficient-funds" },
      { market.buy(game.forces.player.index, "item", "iron-gear-wheel", 1000) })
    assert.are.equal(before, player_state().balance)
  end)

  test("charges interest on a negative balance only, journaled with its own kind", function()
    player_state().balance = 100
    forces.on_interest_tick({ tick = game.tick })
    assert.are.equal(100, player_state().balance)
    player_state().balance = -2000
    forces.on_interest_tick({ tick = game.tick })
    assert.is_true(math.abs(player_state().balance + 2000 * (1 + account.INTEREST_RATE)) < 1e-6)
    assert.are.equal(1, interest_entries())
  end)

  test("charges interest from the registered handler, after a save and load", function()
    player_state().balance = -1000
  end).after_reload_mods(function()
    after_ticks(account.INTEREST_TICKS, function()
      assert.is_true(player_state().balance < -1000)
      assert.are.equal(1, interest_entries())
    end)
  end)
end)
