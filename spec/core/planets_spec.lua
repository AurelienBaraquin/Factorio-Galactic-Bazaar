local planets = require("scripts.core.planets")

local catalog = {
  { name = "a", distance = 1, specialties = {
    { kind = "resource", name = "iron-ore", slots = 4 },
    { kind = "crafting", name = "smelting", slots = 2 },
  } },
  { name = "b", distance = 3, specialties = { { kind = "crafting", name = "modded", slots = 1 } } },
}

describe("planets.available_catalog", function()
  it("keeps only specialties that exist, and drops planets left empty", function()
    local list = planets.available_catalog(catalog, function(_, name) return name ~= "modded" end)
    assert.are.equal(1, #list)
    assert.are.equal(2, #list[1].specialties)
    assert.are.equal(1, #catalog[2].specialties)
  end)

  it("keeps every planet of the default catalog in a vanilla game", function()
    local vanilla = { ["iron-ore"] = true, ["copper-ore"] = true, coal = true, stone = true, ["uranium-ore"] = true,
      smelting = true, crafting = true, ["advanced-crafting"] = true, chemistry = true }
    local list = planets.available_catalog(planets.CATALOG, function(_, name) return vanilla[name] end)
    assert.are.equal(#planets.CATALOG, #list)
  end)
end)

describe("planets.reserve", function()
  it("holds slots until the end tick, then frees them", function()
    local reservations = {}
    assert.is_truthy(planets.reserve(catalog, reservations, "a", "resource", "iron-ore", 3, 0, 100))
    assert.are.equal(1, planets.free(catalog, reservations, "a", "resource", "iron-ore", 50))
    assert.are.same({ nil, "no-capacity" },
      { planets.reserve(catalog, reservations, "a", "resource", "iron-ore", 2, 50, 200) })
    assert.are.equal(4, planets.free(catalog, reservations, "a", "resource", "iron-ore", 100))
    assert.is_truthy(planets.reserve(catalog, reservations, "a", "resource", "iron-ore", 4, 100, 200))
    assert.are.equal(1, #reservations)
  end)

  it("keeps specialties and planets apart", function()
    local reservations = {}
    planets.reserve(catalog, reservations, "a", "resource", "iron-ore", 4, 0, 100)
    assert.are.equal(2, planets.free(catalog, reservations, "a", "crafting", "smelting", 0))
    assert.is_nil(planets.free(catalog, reservations, "a", "crafting", "crafting", 0))
  end)

  it("refuses unknown places and bad amounts", function()
    local reservations = {}
    local function reason(...) return select(2, planets.reserve(catalog, reservations, ...)) end
    assert.are.equal("unknown-planet", reason("z", "resource", "iron-ore", 1, 0, 10))
    assert.are.equal("unknown-specialty", reason("a", "resource", "coal", 1, 0, 10))
    assert.are.equal("invalid-slots", reason("a", "resource", "iron-ore", 1.5, 0, 10))
    assert.are.equal("invalid-slots", reason("a", "resource", "iron-ore", 0, 0, 10))
    assert.are.equal("invalid-duration", reason("a", "resource", "iron-ore", 1, 10, 10))
    assert.are.equal("invalid-duration", reason("a", "resource", "iron-ore", 1, 0, math.huge))
    assert.are.same({}, reservations)
  end)
end)

describe("planets.merge", function()
  it("carries the source's reservations over", function()
    local destination, source = {}, { reservations = { { planet = "a", slots = 1, until_tick = 5 } } }
    planets.merge(destination, source)
    assert.are.same(source.reservations, destination.reservations)
  end)
end)
