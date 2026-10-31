-- In-game tests of NPC planets (scripts/planets.lua, scripts/planets_gui.lua, #83): the catalog of
-- the loaded game, reservations per force, the planets window and persistence.
local market_gui = require("scripts.market_gui")
local planets = require("scripts.planets")
local planets_gui = require("scripts.planets_gui")

local function force_index() return game.forces.player.index end
local function state() return storage.forces[force_index()] end

local function find(element, action)
  if element.tags.gb_action == action then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action)
    if found then return found end
  end
end

describe("NPC planets", function()
  before_each(function()
    storage.gb_test_reservations = state().reservations
    state().reservations = {}
  end)
  after_each(function()
    planets_gui.close(1)
    market_gui.close(1)
    if storage.gb_test_reservations then
      state().reservations = storage.gb_test_reservations
      storage.gb_test_reservations = nil
    end
  end)

  test("the catalog keeps every abstract planet and specialty of a vanilla game", function()
    local count = 0
    for _, planet in ipairs(planets.catalog()) do count = count + #planet.specialties end
    assert.are.equal(4, #planets.catalog())
    assert.are.equal(10, count)
  end)

  test("a force reserves slots, which other forces do not lose", function()
    local other = game.create_force("gb-test-planets")
    assert.is_truthy(planets.reserve(force_index(), "ferrum-prime", "resource", "iron-ore", 3, game.tick + 600))
    assert.are.equal(1, planets.free(force_index(), "ferrum-prime", "resource", "iron-ore"))
    assert.are.equal(4, planets.free(other.index, "ferrum-prime", "resource", "iron-ore"))
    assert.are.same({ nil, "no-capacity" },
      { planets.reserve(force_index(), "ferrum-prime", "resource", "iron-ore", 2, game.tick + 600) })
    game.merge_forces(other, "player")
  end)

  test("the planets window opens from the market window and shows the free slots", function()
    local player = game.get_player(1)
    local hub = player.surface.create_entity({
      name = "gb-hub", position = { player.position.x + 3, player.position.y }, force = "player",
    })
    hub.energy = hub.electric_buffer_size
    planets.reserve(force_index(), "carbo", "resource", "coal", 1, game.tick + 600)
    market_gui.open(player, hub)
    market_gui.on_gui_click({ element = find(player.gui.screen.gb_market, "planets"), player_index = 1 })
    hub.destroy()
    local rows = storage.planets_gui[1].elements.rows
    local coal
    for _, row in ipairs(rows) do
      if row.planet == "carbo" and row.name == "coal" then coal = row end
    end
    assert.are.equal(10, #rows)
    assert.are.same({ "gb-planets.slots", 3, 4 },
      { coal.slots.caption[1], tonumber(coal.slots.caption[2]), tonumber(coal.slots.caption[3]) })
    planets_gui.on_gui_click({ element = find(player.gui.screen.gb_planets, "planets-close"), player_index = 1 })
    assert.is_nil(player.gui.screen.gb_planets)
  end)

  test("keeps reservations across a save and reload", function()
    planets.reserve(force_index(), "uranos-deep", "crafting", "chemistry", 2, game.tick + 6000)
  end).after_reload_mods(function()
    assert.are.equal(0, planets.free(game.forces.player.index, "uranos-deep", "crafting", "chemistry"))
  end)
end)
