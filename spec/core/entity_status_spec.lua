local status = require("scripts.core.entity_status")

local GREEN, YELLOW, RED = status.GREEN, status.YELLOW, status.RED

describe("entity_status.module", function()
  local working = { diode = GREEN, label = { "gb-status.export-selling" } }

  it("reports a module without a hub of its force in red, with the no-hub alert", function()
    for _, needs_power in ipairs({ true, false }) do
      assert.are.same({ diode = RED, label = { "gb-status.no-hub" }, alert = status.NO_HUB },
        status.module("none", needs_power, working))
    end
  end)

  it("stops a module that trades through a hub without power, with the no-power alert", function()
    assert.are.same({ diode = RED, label = { "gb-status.stopped-no-power" }, alert = status.HUB_UNPOWERED },
      status.module("unpowered", true, working))
  end)

  it("warns a module that works without power that its hub has none, keeping its own status", function()
    assert.are.same({ diode = YELLOW, label = { "gb-status.hub-unpowered-then", working.label } },
      status.module("unpowered", false, working))
  end)

  it("gives the module's own status when its hub has power", function()
    assert.are.equal(working, status.module("powered", true, working))
  end)

  it("keeps the game's own status of a module that has none of its own, warning of an unpowered hub", function()
    assert.is_nil(status.module("powered", false, nil))
    assert.are.same({ diode = YELLOW, label = { "gb-status.hub-unpowered-only" } },
      status.module("unpowered", false, nil))
    assert.are.same({ diode = RED, label = { "gb-status.no-hub" }, alert = status.NO_HUB },
      status.module("none", false, nil))
  end)
end)

describe("entity_status.hub", function()
  it("counts its modules and shipments and names its delivery tier while powered", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.hub", 4, 2, { "gb-gui.tier-shuttle" } } },
      status.hub({ powered = true, modules = 4, queued = 2, tier = "shuttle" }))
  end)

  it("is red with the no-power alert without power", function()
    assert.are.same({ diode = RED, label = { "gb-status.hub-unpowered", 0, 3 }, alert = status.UNPOWERED },
      status.hub({ powered = false, modules = 0, queued = 3, tier = "capsule" }))
  end)
end)

describe("entity_status cargo and manifolds", function()
  it("tells an export chest that waits, sells or holds goods below its floor", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.export-empty" } }, status.export_chest({ empty = true }))
    assert.are.same({ diode = GREEN, label = { "gb-status.export-selling" } },
      status.export_chest({ empty = false, held = false }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.export-held" } },
      status.export_chest({ empty = false, held = true }))
  end)

  it("tells an import chest whether shipments are on the way", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.import-ready" } }, status.import_chest({ queued = 0 }))
    assert.are.same({ diode = GREEN, label = { "gb-status.import-receiving", 3 } },
      status.import_chest({ queued = 3 }))
  end)

  it("names the fluid an export manifold sells or holds", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.fluid-export-empty" } }, status.fluid_export({}))
    assert.are.same({ diode = GREEN, label = { "gb-status.fluid-export-selling", "[fluid=water]" } },
      status.fluid_export({ fluid = "water", held = false }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.fluid-export-held", "[fluid=crude-oil]" } },
      status.fluid_export({ fluid = "crude-oil", held = true }))
  end)

  it("says which fluid an import manifold can still receive", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.fluid-import-ready" } }, status.fluid_import({}))
    assert.are.same({ diode = GREEN, label = { "gb-status.fluid-import-holds", "[fluid=water]" } },
      status.fluid_import({ fluid = "water" }))
  end)
end)

describe("entity_status.power", function()
  it("reports what its force's substations traded at the last settlement", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.power-export", "12.5" } },
      status.power({ direction = "export", last = { units = 12.5, held = true } }))
    assert.are.same({ diode = GREEN, label = { "gb-status.power-import", "40.0" } },
      status.power({ direction = "import", last = { units = 40 } }))
  end)

  it("waits, or warns only from what the same settlement found", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.power-export-waiting" } },
      status.power({ direction = "export" }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.power-export-held" } },
      status.power({ direction = "export", last = { units = 0, held = true } }))
    assert.are.same({ diode = GREEN, label = { "gb-status.power-import-waiting" } },
      status.power({ direction = "import", last = { units = 0, short = false } }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.power-import-blocked" } },
      status.power({ direction = "import", last = { units = 0, short = true } }))
  end)
end)

describe("entity_status.price_combinator", function()
  it("waits for its force's first snapshot", function()
    assert.are.same({ diode = YELLOW, label = { "gb-status.price-waiting" } },
      status.price_combinator({ side = "buy", ready = false }))
  end)

  it("tells how many prices it emits and how often they are refreshed", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.price-emitting-sell", 196, 10 } },
      status.price_combinator({ side = "sell", ready = true, count = 196, period_seconds = 10 }))
  end)
end)

describe("entity_status.order_combinator", function()
  it("waits for its first reading", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.order-waiting" } }, status.order_combinator({}))
  end)

  it("reports what it ordered and the budget left", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.order-placed", 2, "1.50k" } },
      status.order_combinator({ last = { result = "placed", placed = 2, budget_left = 1500 } }))
  end)

  it("explains every refusal", function()
    local cases = {
      { "refused", RED, { "gb-status.order-refused" } },
      { "no-budget", YELLOW, { "gb-status.order-no-budget" } },
      { "no-orders", GREEN, { "gb-status.order-no-orders" } },
      { "queue-full", YELLOW, { "gb-status.order-queue-full" } },
      { "budget-spent", YELLOW, { "gb-status.order-budget-spent" } },
      { "no-funds", YELLOW, { "gb-status.order-no-funds" } },
    }
    for _, case in ipairs(cases) do
      assert.are.same({ diode = case[2], label = case[3] }, status.order_combinator({ last = { result = case[1] } }))
    end
  end)

  it("tells an order larger than the budget left from one larger than the funds", function()
    assert.are.same({ diode = YELLOW, label = { "gb-status.order-over-budget", "50.00" } },
      status.order_combinator({ last = { result = "placed", placed = 0, reason = "over-budget", budget_left = 50,
        allowance = 50 } }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.order-over-funds" } },
      status.order_combinator({ last = { result = "placed", placed = 0, reason = "over-budget", budget_left = 50,
        allowance = 20 } }))
  end)

  it("names the reason nothing was bought, with a known refusal text or a generic one", function()
    assert.are.same({ diode = YELLOW, label = { "gb-status.order-failed", { "gb-gui.refused-no-import-chest" } } },
      status.order_combinator({ last = { result = "placed", placed = 0, reason = "no-import-chest",
        budget_left = 0 } }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.order-failed", { "gb-status.order-failed-other" } } },
      status.order_combinator({ last = { result = "placed", placed = 0, reason = "something-new",
        budget_left = 0 } }))
  end)
end)

describe("entity_status delivery buildings", function()
  it("tells a docking bay's fuel and the tier its hub actually ships by", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.bay-fueled", "250", "100", { "gb-gui.tier-teleporter" } } },
      status.docking_bay({ fuel_mj = 250, shipment_mj = 100, fueled = true, tier = "teleporter" }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.bay-no-fuel", "40", "100", { "gb-gui.tier-capsule" } } },
      status.docking_bay({ fuel_mj = 40, shipment_mj = 100, fueled = false, tier = "capsule" }))
  end)

  it("tells whether a teleporter is powered, with its charge and its own alert when it is not", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.teleporter-powered" } },
      status.teleporter({ powered = true, charge = 0.9 }))
    assert.are.same({ diode = RED, label = { "gb-status.teleporter-unpowered", 12 }, alert = status.UNPOWERED },
      status.teleporter({ powered = false, charge = 0.125 }))
  end)

  it("tells a catapult's charge, and goods it holds below the floor", function()
    assert.are.same({ diode = YELLOW, label = { "gb-status.catapult-charging", 30, 50 } },
      status.catapult({ charge = 0.3, shot_share = 0.5, empty = false, shot_seconds = 2 }))
    assert.are.same({ diode = GREEN, label = { "gb-status.catapult-empty", 100 } },
      status.catapult({ charge = 1, shot_share = 0.5, empty = true, shot_seconds = 2 }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.catapult-held", 80 } },
      status.catapult({ charge = 0.8, shot_share = 0.5, empty = false, held = true, shot_seconds = 2 }))
    assert.are.same({ diode = GREEN, label = { "gb-status.catapult-ready", 80, 2 } },
      status.catapult({ charge = 0.8, shot_share = 0.5, empty = false, held = false, shot_seconds = 2 }))
  end)
end)

describe("entity_status.contract_chest", function()
  it("is idle when no active contract needs goods", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.contract-chest-idle" } },
      status.contract_chest({ needs = {} }))
  end)

  it("lists what active contracts still need, the rest counted", function()
    local needs = {}
    for i = 1, status.MAX_LISTED + 2 do needs[i] = { name = "item-" .. i, count = i } end
    local descriptor = status.contract_chest({ needs = { needs[1] } })
    assert.are.same({ diode = GREEN, label = { "gb-status.contract-chest-needs", { "", "[item=item-1] 1" } } },
      descriptor)
    local label = status.contract_chest({ needs = needs }).label
    assert.are.equal("gb-status.contract-chest-needs", label[1])
    assert.are.same({ "gb-status.contract-chest-more", label[2][2], 2 }, label[2])
    local list = label[2][2]
    assert.are.equal(2 * status.MAX_LISTED, #list)
    assert.are.equal("[item=item-1] 1", list[2])
    assert.are.equal(", ", list[3])
  end)
end)

describe("entity_status.rental", function()
  it("tells an idle or offered machine, and leaves a rented one to the game's own status", function()
    assert.are.same({ diode = GREEN, label = { "gb-status.rental-idle" } }, status.rental({ state = "idle" }))
    assert.are.same({ diode = YELLOW, label = { "gb-status.rental-offered", 7 } },
      status.rental({ state = "offered", id = 7 }))
    assert.is_nil(status.rental({ state = "rented", id = 7 }))
  end)
end)

describe("entity_status.visits", function()
  it("refreshes every building once per cycle, within a cap per pass", function()
    assert.are.equal(0, status.visits(0, 30, 20))
    assert.are.equal(1, status.visits(1, 30, 20))
    assert.are.equal(4, status.visits(100, 30, 20))
    assert.are.equal(20, status.visits(5000, 30, 20))
  end)
end)

describe("entity_status.same", function()
  it("compares descriptors by value, nested labels included", function()
    local a = { diode = GREEN, label = { "gb-status.hub", 2, 0, { "gb-gui.tier-capsule" } } }
    assert.is_true(status.same(a, { diode = GREEN, label = { "gb-status.hub", 2, 0, { "gb-gui.tier-capsule" } } }))
    assert.is_false(status.same(a, { diode = GREEN, label = { "gb-status.hub", 2, 1, { "gb-gui.tier-capsule" } } }))
    assert.is_false(status.same(a, { diode = GREEN, label = { "gb-status.hub", 2, 0, { "gb-gui.tier-shuttle" } } }))
    assert.is_false(status.same(a, { diode = RED, label = a.label }))
    assert.is_false(status.same(a, { diode = GREEN, label = a.label, alert = status.HUB_UNPOWERED }))
    assert.is_false(status.same(a, { diode = GREEN, label = { "gb-status.hub", 2, 0 } }))
    assert.is_false(status.same(a, nil))
    assert.is_false(status.same(nil, a))
    assert.is_true(status.same(nil, nil))
  end)
end)
