-- In-game tests of quality values (ADR-0008): one value and one market per quality when a quality
-- mod is active (Space Age), and nothing different without one.
local cargo = require("scripts.cargo")
local market = require("scripts.market")
local pricing = require("scripts.pricing")
local quality = require("scripts.core.quality")

local function player_state() return storage.forces[game.forces.player.index] end
local GEAR = "iron-gear-wheel"

describe("quality", function()
  local created, saved_balance
  before_each(function()
    created = {}
    saved_balance = player_state().balance
    player_state().balance = 0
  end)
  after_each(function()
    for _, entity in ipairs(created or {}) do
      if entity.valid then entity.destroy() end
    end
    if saved_balance then player_state().balance = saved_balance end
    for key in pairs(player_state().markets) do
      if key:find(GEAR, 1, true) then player_state().markets[key] = nil end
    end
  end)

  test("changes nothing without a quality mod", function()
    if script.active_mods["quality"] then return end
    assert.are.same({ normal = 0 }, storage.quality_levels)
    assert.are.equal(pricing.base_value("item", GEAR), pricing.base_value("item", GEAR, "normal"))
    assert.are.equal("item/" .. GEAR, pricing.key("item", GEAR, "normal"))
    assert.is_nil(pricing.base_value("item", GEAR, "rare"))
  end)

  test("values each quality from the normal value and its level", function()
    if not script.active_mods["quality"] then return end
    local normal = pricing.base_value("item", GEAR)
    for name, prototype in pairs(prototypes.quality) do
      if not prototype.hidden then
        assert.are.equal(quality.value(normal, prototype.level), pricing.base_value("item", GEAR, name), name)
      end
    end
    assert.is_nil(pricing.base_value("fluid", "water", "rare"))
  end)

  test("trades each quality on its own market", function()
    if not script.active_mods["quality"] then return end
    local force_index = game.forces.player.index
    local normal = market.quote(force_index, "item", GEAR).mid
    assert.is_true(market.sell(force_index, "item", GEAR, 100, "rare"))
    assert.are.equal(normal, market.quote(force_index, "item", GEAR).mid)
    assert.is_truthy(player_state().markets["item/" .. GEAR .. "@rare"])
  end)

  test("export chests sell a quality stack at its quality's price", function()
    if not script.active_mods["quality"] then return end
    local surface = game.surfaces[1]
    local function place(name, x)
      return surface.create_entity({ name = name, position = { x, 0 }, force = "player", raise_built = true })
    end
    local hub = place("gb-hub", 0)
    local chest = place("gb-export-chest", 2)
    created = { hub, chest }
    hub.energy = hub.electric_buffer_size
    local inventory = chest.get_inventory(defines.inventory.chest)
    inventory.insert({ name = GEAR, count = 5, quality = "uncommon" })
    local expected = market.preview(game.forces.player.index, "item", GEAR, "sell", 5, "uncommon")
    for _ = 1, #storage.cargo.exports do cargo.on_export_tick() end
    assert.are.equal(0, inventory.get_item_count({ name = GEAR, quality = "uncommon" }))
    assert.is_true(math.abs(player_state().balance - expected) < 1e-6 * expected)
    assert.is_true(expected > market.preview(game.forces.player.index, "item", GEAR, "sell", 5))
  end)
end)
