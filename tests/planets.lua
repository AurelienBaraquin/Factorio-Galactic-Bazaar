-- In-game tests of NPC planets (scripts/planets.lua, scripts/planets_gui.lua, #83): the catalog of
-- the loaded game, reservations per force, the planets window and persistence.
local freight = require("scripts.freight")
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

  test("the catalog keeps every abstract planet and specialty", function()
    local abstract, count = 0, 0
    for _, planet in ipairs(planets.catalog()) do
      if not planet.real then abstract, count = abstract + 1, count + #planet.specialties end
    end
    assert.are.equal(4, abstract)
    assert.are.equal(10, count)
  end)

  test("real planets join the catalog with Space Age, with their resources and signature category", function()
    local real = {}
    for _, planet in ipairs(planets.catalog()) do
      if planet.real then
        local names = {}
        for _, specialty in ipairs(planet.specialties) do
          names[#names + 1] = specialty.kind .. ":" .. specialty.name
        end
        real[planet.name] = table.concat(names, ",")
        assert.is_true(planet.distance >= 1)
      end
    end
    if not script.active_mods["space-age"] then return assert.is_nil(next(real)) end
    assert.are.equal("resource:calcite,resource:coal,resource:tungsten-ore,crafting:metallurgy", real.vulcanus)
    assert.are.equal("resource:scrap,crafting:electromagnetics", real.fulgora)
    assert.are.equal("resource:stone,crafting:organic", real.gleba)
    assert.are.equal("crafting:cryogenics", real.aquilo)
  end)

  test("a real planet keeps its category while it can still host it, and hosts only its recipes", function()
    if not script.active_mods["space-age"] then return end
    local function category_of(name)
      for _, planet in ipairs(planets.catalog()) do
        if planet.name == name then return planet.specialties[#planet.specialties].name end
      end
    end
    for _, planet in ipairs(planets.catalog()) do
      if planet.name == "vulcanus" then planet.specialties[#planet.specialties].name = "cryogenics" end
    end
    planets.init()
    local kept = category_of("vulcanus")
    for _, planet in ipairs(planets.catalog()) do
      if planet.name == "vulcanus" then planet.specialties[#planet.specialties].name = "chemistry-gone" end
    end
    planets.init()
    assert.are.equal("cryogenics", kept)
    assert.are.equal("metallurgy", category_of("vulcanus"))
    local magnetic = prototypes.recipe["electromagnetic-science-pack"]
    assert.is_false(planets.can_host("vulcanus", magnetic))
    assert.is_true(planets.can_host("fulgora", magnetic))
    assert.is_true(planets.can_host("fabrica-nova", magnetic))
    assert.are.equal("space-location-name.vulcanus", planets.caption("vulcanus")[1])
    assert.are.equal("gb-planets.name-carbo", planets.caption("carbo")[2][1])
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
    local specialties = 0
    for _, planet in ipairs(planets.catalog()) do specialties = specialties + #planet.specialties end
    assert.are.equal(specialties, #rows)
    assert.are.same({ "gb-planets.slots", 3, 4 },
      { coal.slots.caption[1], tonumber(coal.slots.caption[2]), tonumber(coal.slots.caption[3]) })
    assert.are.equal(player.gui.screen.gb_planets, player.opened)
    assert.is_nil(player.gui.screen.gb_market)
    planets_gui.on_gui_click({ element = find(player.gui.screen.gb_planets, "planets-close"), player_index = 1 })
    assert.is_nil(player.gui.screen.gb_planets)
    planets_gui.open(player)
    player.opened = nil
    assert.is_nil(player.gui.screen.gb_planets)
  end)

  test("reservations of a specialty gone from the catalog are dropped on configuration change", function()
    planets.reserve(force_index(), "carbo", "resource", "coal", 1, game.tick + 600, 41)
    table.insert(state().reservations, { planet = "gone", kind = "resource", name = "coal", slots = 1,
      until_tick = game.tick + 600, contract = 42 })
    local dropped = planets.init()[force_index()]
    assert.are.same({ 42 }, { dropped[1].contract })
    assert.are.equal(1, #state().reservations)
    planets.release(force_index(), 41)
    assert.are.equal(4, planets.free(force_index(), "carbo", "resource", "coal"))
  end)

  test("goods from a planet land after its transit delay, less a bounded loss", function()
    local surface = game.surfaces[1]
    local hub = surface.create_entity({ name = "gb-hub", position = { 0, 330 }, force = "player", raise_built = true })
    local chest = surface.create_entity({
      name = "gb-import-chest", position = { 3, 330 }, force = "player", raise_built = true,
    })
    local terms = planets.transit_terms("uranos-deep")
    local ok, arrival, arriving = planets.ship(force_index(), hub.unit_number, "uranos-deep",
      { { kind = "item", name = "uranium-ore", count = 1000 }, { kind = "item", name = "stone", count = 1000 } }, 77)
    local capsules = freight.capsules(hub.unit_number)
    local first, last = capsules[1].arrival, capsules[#capsules].arrival
    freight.on_unload_tick({ tick = first - 1 })
    local early = chest.get_item_count("uranium-ore")
    local _, _, again = planets.ship(force_index(), hub.unit_number, "uranos-deep",
      { { kind = "item", name = "uranium-ore", count = 1000 } }, 78)
    local lost_ok, lost_arrival, lost = planets.ship(force_index(), hub.unit_number, "uranos-deep",
      { { kind = "item", name = "stone", count = 1 } }, 79)
    local refused = { planets.ship(force_index(), hub.unit_number, "uranos-deep",
      { { kind = "item", name = "stone", count = 2.5 } }, 80) }
    storage.freight.hubs[hub.unit_number] = nil
    hub.destroy()
    chest.destroy()
    assert.is_true(ok)
    for _, goods in ipairs(arriving) do
      assert.is_true(goods.count < 1000 and goods.count >= 1000 * (1 - terms.max_loss))
    end
    assert.are_not.equal(arriving[1].count, again[1].count)
    assert.are.equal(game.tick + freight.TIERS.capsule.delay_ticks + terms.delay_ticks, first)
    assert.are.equal(last, arrival)
    assert.are.equal(0, early)
    assert.is_true(lost_ok)
    assert.are.same({}, lost)
    assert.is_true(lost_arrival > game.tick + terms.delay_ticks)
    assert.are.same({ false, "invalid-quantity" }, refused)
    assert.are.same({ false, "unknown-planet" }, { planets.ship(force_index(), 1, "nowhere", {}, 1) })
  end)

  test("keeps reservations across a save and reload", function()
    planets.reserve(force_index(), "uranos-deep", "crafting", "chemistry", 2, game.tick + 6000)
  end).after_reload_mods(function()
    assert.are.equal(0, planets.free(game.forces.player.index, "uranos-deep", "crafting", "chemistry"))
  end)
end)
