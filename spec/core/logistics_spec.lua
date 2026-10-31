local freight = require("scripts.core.freight")
local logistics = require("scripts.core.logistics")

local TIERS = freight.TIERS
local capsule_tier = TIERS.capsule

local function capsule(fields)
  local entry = { force_index = 1, kind = "item", name = "iron-plate", count = 100, unit_cost = 2, tier = "capsule" }
  for key, value in pairs(fields) do entry[key] = value end
  return entry
end

describe("logistics.page", function()
  it("slices a list and clamps the page to those that exist", function()
    local list = { "a", "b", "c", "d", "e" }
    assert.are.same({ items = { "c", "d" }, page = 2, pages = 3 }, logistics.page(list, 2, 2))
    assert.are.same({ items = { "e" }, page = 3, pages = 3 }, logistics.page(list, 9, 2))
    assert.are.same({ items = { "a", "b" }, page = 1, pages = 3 }, logistics.page(list, -1, 2))
  end)

  it("has one empty page for an empty list", function()
    assert.are.same({ items = {}, page = 1, pages = 1 }, logistics.page({}, 3, 4))
  end)
end)

describe("logistics.clock", function()
  it("shows a game tick as hours, minutes and seconds", function()
    assert.are.equal("0:00:00", logistics.clock(0))
    assert.are.equal("1:01:01", logistics.clock((3600 + 61) * 60 + 59))
    assert.are.equal("27:00:00", logistics.clock(27 * 216000))
  end)
end)

describe("logistics.hubs", function()
  it("orders the hubs by surface, then unit number", function()
    local hubs = {
      { unit_number = 9, surface_index = 2 }, { unit_number = 7, surface_index = 1 },
      { unit_number = 3, surface_index = 2 }, { unit_number = 8, surface_index = 1 },
    }
    local sorted = logistics.hubs(hubs)
    assert.are.same({ 7, 8, 3, 9 }, { sorted[1].unit_number, sorted[2].unit_number, sorted[3].unit_number,
      sorted[4].unit_number })
  end)
end)

describe("logistics.select", function()
  local hubs = { { unit_number = 4 }, { unit_number = 6 } }

  it("keeps the selected hub while it is listed", function()
    assert.are.equal(6, logistics.select(hubs, 6, 4))
  end)

  it("falls back to the preferred hub, then to the first one", function()
    assert.are.equal(4, logistics.select(hubs, 99, 4))
    assert.are.equal(4, logistics.select(hubs, nil, nil))
    assert.are.equal(6, logistics.select(hubs, nil, 6))
  end)

  it("selects nothing without a hub", function()
    assert.is_nil(logistics.select({}, 4, 4))
  end)
end)

describe("logistics.queue_use", function()
  it("counts the queued shipments of each tier against its bound, best tier first", function()
    local capsules = { capsule({}), capsule({ tier = "teleporter" }), capsule({ tier = nil }), capsule({}) }
    assert.are.same({
      { name = "teleporter", queued = 1, max = TIERS.teleporter.max_capsules },
      { name = "capsule", queued = 3, max = capsule_tier.max_capsules },
    }, logistics.queue_use(capsules, TIERS))
  end)

  it("always lists the hub's current tier, even with nothing queued", function()
    assert.are.same({ { name = "shuttle", queued = 0, max = TIERS.shuttle.max_capsules } },
      logistics.queue_use({}, TIERS, "shuttle"))
  end)
end)

describe("logistics.shipment", function()
  local facts = { unload_ticks = 60, held = {}, contracts = {} }

  it("waits for its launch while the tier's earlier shipments go first", function()
    local row = logistics.shipment(capsule({ arrival = 5000 }), 1000, TIERS, facts)
    assert.are.same({ "queued", 5000 - capsule_tier.delay_ticks, 4000 }, { row.state, row.launch, row.left })
  end)

  it("is in flight between its launch and its landing", function()
    local row = logistics.shipment(capsule({ arrival = 2000 }), 1000, TIERS, facts)
    assert.are.same({ "in-flight", 1000 }, { row.state, row.left })
  end)

  it("is unloading until an unloading pass has run since it landed, then waits for room", function()
    assert.are.equal("unloading", logistics.shipment(capsule({ arrival = 1021 }), 1030, TIERS, facts).state)
    assert.are.equal("unloading", logistics.shipment(capsule({ arrival = 1021 }), 1079, TIERS, facts).state)
    -- The pass at tick 1020 ran after it landed at 1000.
    local waiting = logistics.shipment(capsule({ arrival = 1000 }), 1030, TIERS, facts)
    assert.are.same({ "no-room", 0 }, { waiting.state, waiting.left })
    assert.are.equal("no-room", logistics.shipment(capsule({ arrival = 1021 }), 1080, TIERS, facts).state)
  end)

  it("is held when its tier cannot deliver at the hub", function()
    local held = { unload_ticks = 60, held = { teleporter = true }, contracts = {} }
    local row = logistics.shipment(capsule({ arrival = 1000, tier = "teleporter" }), 1100, TIERS, held)
    assert.are.equal("held", row.state)
  end)

  it("is a purchase without a contract, with the price paid per unit", function()
    local row = logistics.shipment(capsule({ arrival = 2000, unit_cost = 3.5 }), 0, TIERS, facts)
    assert.are.same({ "purchase", 3.5, "item", "iron-plate", 100, "capsule" },
      { row.origin, row.unit_cost, row.kind, row.name, row.count, row.tier })
  end)

  it("carries an incoming contract's ingredients, free", function()
    local row = logistics.shipment(capsule({ arrival = 2000, unit_cost = 0, contract = 12 }), 0, TIERS, facts)
    assert.are.same({ "incoming", 12, 0 }, { row.origin, row.contract, row.unit_cost })
  end)

  it("travels from a planet, with its contract's kind and the share lost on the way", function()
    local kinds = { unload_ticks = 60, held = {}, contracts = { [5] = { kind = "concession", counterparty = "carbo" },
      [6] = { kind = "outsourcing", counterparty = "carbo" } } }
    local ore = logistics.shipment(capsule({ arrival = 9000, contract = 5, planet = "carbo", loss = 0.04 }), 0,
      TIERS, kinds)
    local gears = logistics.shipment(capsule({ arrival = 9000, contract = 6, planet = "carbo", loss = 0 }), 0,
      TIERS, kinds)
    assert.are.same({ "concession", "carbo", 0.04, "in-transit" }, { ore.origin, ore.planet, ore.loss, ore.state })
    assert.are.equal("outsourcing", gears.origin)
  end)

  it("names a planet shipment whose contract is gone, or an older one without its planet", function()
    local gone = logistics.shipment(capsule({ arrival = 9000, contract = 5, planet = "carbo", loss = 0.1 }), 0,
      TIERS, facts)
    assert.are.equal("planet", gone.origin)
    local kinds = { unload_ticks = 60, held = {},
      contracts = { [5] = { kind = "concession", counterparty = "carbo" } } }
    local older = logistics.shipment(capsule({ arrival = 9000, contract = 5 }), 0, TIERS, kinds)
    assert.are.same({ "concession", "carbo" }, { older.origin, older.planet })
  end)

  it("reads a paid contract shipment queued before planets were recorded as from a planet", function()
    local row = logistics.shipment(capsule({ arrival = 9000, contract = 5, unit_cost = 2 }), 0, TIERS, facts)
    assert.are.same({ "planet", nil, "in-transit" }, { row.origin, row.planet, row.state })
  end)

  it("reads a capsule queued before tiers and kinds were recorded as an item by orbital capsule", function()
    local row = logistics.shipment({ force_index = 1, name = "stone", count = 5, unit_cost = 1, arrival = 10 }, 0,
      TIERS, facts)
    assert.are.same({ "item", "capsule" }, { row.kind, row.tier })
  end)
end)

describe("logistics.shipments", function()
  it("lists the force's shipments by landing time, in queue order on a tie", function()
    local capsules = {
      capsule({ arrival = 3000, name = "a" }), capsule({ arrival = 1000, name = "b" }),
      capsule({ arrival = 3000, name = "c" }), capsule({ arrival = 500, name = "d", force_index = 2 }),
    }
    local rows = logistics.shipments(capsules, 1, 0, TIERS, { unload_ticks = 60, held = {}, contracts = {} })
    assert.are.same({ "b", "a", "c" }, { rows[1].name, rows[2].name, rows[3].name })
    assert.are.equal(3, #rows)
  end)
end)

describe("logistics.modules", function()
  local green = { diode = "green", label = { "x" } }
  local red = { diode = "red", label = { "y" } }

  it("orders the modules by kind, building and unit number, and counts each building by diode", function()
    local modules = {
      { rank = 3, name = "gb-power-import", unit_number = 30, descriptor = green },
      { rank = 2, name = "gb-import-chest", unit_number = 12, descriptor = red },
      { rank = 2, name = "gb-export-chest", unit_number = 15, descriptor = green },
      { rank = 2, name = "gb-export-chest", unit_number = 11, descriptor = false },
      { rank = 2, name = "gb-import-chest", unit_number = 10 },
    }
    local listed = logistics.modules(modules)
    local order = {}
    for i, row in ipairs(listed.rows) do order[i] = row.unit_number end
    assert.are.same({ 11, 15, 10, 12, 30 }, order)
    assert.are.same({
      { name = "gb-export-chest", count = 2, green = 1, yellow = 0, red = 0 },
      { name = "gb-import-chest", count = 2, green = 0, yellow = 0, red = 1 },
      { name = "gb-power-import", count = 1, green = 1, yellow = 0, red = 0 },
    }, listed.groups)
    assert.are.same({ nil, "green", nil, "red" },
      { listed.rows[1].diode, listed.rows[2].diode, listed.rows[3].diode, listed.rows[4].diode })
  end)
end)
