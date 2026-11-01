-- The layout of the in-game check's scene (tests/ingame_check/plan.lua, docs/ingame-check.md).
local plan = require("tests.ingame_check.plan")

local function box(width, height) return { width = width, height = height } end

describe("in-game check plan", function()
  it("places buildings left to right, gap apart, and wraps before the width", function()
    local layout = plan.layout({ box(2, 2), box(3, 3), box(1, 1) }, 8, 2, 4)
    assert.are.same({ x = 1, y = 1 }, layout.positions[1])
    assert.are.same({ x = 5.5, y = 1.5 }, layout.positions[2])
    -- 2 + 2 + 3 + 2 = 9 > 8: the third starts a row below the tallest of the first (3) and a lane.
    assert.are.same({ x = 0.5, y = 7.5 }, layout.positions[3])
    assert.are.same(7, layout.width)
    assert.are.same(8, layout.height)
  end)

  it("keeps a building wider than the width on its own row instead of looping", function()
    local layout = plan.layout({ box(10, 2), box(10, 2) }, 8, 2, 4)
    assert.are.same({ x = 5, y = 1 }, layout.positions[1])
    assert.are.same({ x = 5, y = 7 }, layout.positions[2])
  end)

  it("puts a lane above each row and below the last", function()
    local layout = plan.layout({ box(2, 2), box(2, 3) }, 3, 1, 4)
    assert.are.same({ -2, 4, 11 }, layout.lanes)
  end)

  it("lines substations along every lane across the whole width", function()
    local layout = { lanes = { -2, 10 }, width = 30 }
    local list = plan.substations(layout, 14)
    assert.are.same({ { x = 0, y = -2 }, { x = 14, y = -2 }, { x = 28, y = -2 }, { x = 42, y = -2 },
      { x = 0, y = 10 }, { x = 14, y = 10 }, { x = 28, y = 10 }, { x = 42, y = 10 } }, list)
  end)

  it("puts hubs halfway between substations, within the width", function()
    local list = plan.hubs({ lanes = { -2 }, width = 30 }, 14)
    assert.are.same({ { x = 7, y = -2 }, { x = 21, y = -2 } }, list)
  end)

  it("keeps the first value of each key, in order", function()
    local list = plan.unique({ { k = "a", n = 1 }, { k = "b", n = 2 }, { k = "a", n = 3 } },
      function(value) return value.k end)
    assert.are.same({ { k = "a", n = 1 }, { k = "b", n = 2 } }, list)
  end)
end)
