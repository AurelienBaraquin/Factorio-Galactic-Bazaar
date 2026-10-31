-- In-game tests of the Market tab's item detail (scripts/item_detail_gui.lua, #110): the figures of
-- the selected item before and after trades, the price history with and without telecommunications
-- 2, the base value breakdown from the real prototypes, overrides, quality, a save from before the
-- breakdown existed, a reload, and the refresh cost.
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local hubs = require("scripts.hubs")
local item_detail_gui = require("scripts.item_detail_gui")
local market = require("scripts.market")
local pricing = require("scripts.pricing")
local telecom = require("scripts.telecom")
local valuation = require("scripts.core.valuation")
local value_overrides = require("scripts.value_overrides")

local GEAR, PLATE = "iron-gear-wheel", "iron-plate"
local KEYS = { "item/" .. GEAR, "item/" .. PLATE }

local player, hub

local function force() return game.forces.player end
local function state() return storage.forces[force().index] end
local function view() return bazaar_gui.view(player.index, "market") end
local function info() return view().elements.info end

local function research(level)
  for index, name in ipairs(telecom.TECHNOLOGIES) do
    force().technologies[name].researched = index <= level -- luacheck: ignore 122
  end
end

local function reset_markets()
  state().feed = {}
  for _, key in ipairs(KEYS) do state().markets[key] = nil end
end

-- Opens the Market tab on the hub with `key` selected and `quantity` typed, refreshed.
local function show(key, quantity)
  bazaar_gui.open(player, "market", hub)
  view().selected = key
  view().elements.quantity.text = tostring(quantity or 1)
  bazaar_gui.refresh(player)
end

local function near(expected, actual)
  return math.abs(expected - actual) <= 1e-9 * math.max(1, math.abs(expected))
end

describe("item detail", function()
  local saved_balance
  before_each(function()
    player = game.get_player(1)
    saved_balance = state().balance
    test_helpers.set_balance(state(), 1e7)
    reset_markets()
    hub = player.surface.create_entity({ name = "gb-hub", position = { player.position.x + 3, player.position.y },
      force = "player", raise_built = true })
    hub.energy = hub.electric_buffer_size
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    bazaar_gui.close(player.index)
    if hub and hub.valid then hub.destroy() end
    research(0)
    if saved_balance then test_helpers.set_balance(state(), saved_balance) end
    reset_markets()
  end)

  test("shows the prices, base value, liquidity and rules of a balanced market", function()
    show("item/" .. GEAR, 100)
    local detail = item_detail_gui.read(force(), "item", GEAR, nil, 100)
    local figures = detail.figures
    local cells = info().figures
    assert.are.equal(catalog.format_credits(figures.buy), cells.buy.caption)
    assert.are.equal(catalog.format_credits(pricing.base_value("item", GEAR)), cells.base.caption)
    assert.are.equal(catalog.format_units(market.buyable(force().index, "item", GEAR)), cells.liquidity.caption[2])
    assert.are.equal("gb-detail.gap-balanced", cells.gap.caption[3][1])
    for id, cell in pairs(cells) do
      assert.is_true(cell.tooltip ~= nil and cell.tooltip ~= "", id)
    end
    assert.are.equal(100, tonumber(info().impact_buy_label.caption[2]))
    assert.are.equal("gb-detail.impact-value", info().impact_buy.caption[1])
  end)

  test("shows the shortage and the higher prices a large purchase leaves, and the live order impact", function()
    show("item/" .. GEAR, 1000)
    local before = item_detail_gui.read(force(), "item", GEAR, nil, 1000)
    assert.is_true(market.buy(force().index, "item", GEAR, 20000))
    -- The impact is live at once; the market figures follow the force's feed (ADR-0012).
    local after = item_detail_gui.read(force(), "item", GEAR, nil, 1000)
    assert.is_true(near(market.preview(force().index, "item", GEAR, "buy", 1000) / 1000, after.impact.buy.average))
    assert.are.equal(before.figures.buy, after.figures.buy)
    state().feed = {}
    after = item_detail_gui.read(force(), "item", GEAR, nil, 1000)
    assert.is_true(after.figures.gap > 0 and after.figures.displacement < 0)
    assert.is_true(math.abs(after.figures.displacement + 20000) < 1e-6)
    assert.is_true(near(market.buyable(force().index, "item", GEAR), after.figures.max_buy))
    assert.is_true(after.figures.buy > before.figures.buy)
    bazaar_gui.refresh(player)
    assert.are.equal("gb-detail.gap-shortage", info().figures.gap.caption[3][1])
  end)

  test("explains what unlocks the price history below telecommunications 2, and draws it at level 2", function()
    market.quote(force().index, "item", GEAR)
    state().markets["item/" .. GEAR].history = { 1, 3, 2 }
    show("item/" .. GEAR)
    local locked = { view().elements.history.visible, info().history_note.visible, info().history_note.caption[1] }
    research(2)
    state().feed = {}
    bazaar_gui.refresh(player)
    local unlocked = { view().elements.history.visible, info().history_scale.visible, info().history_note.visible,
      info().history_scale.caption[1] }
    -- "Now" is the current mid price, not the last history point.
    local now = { info().history_scale.caption[4],
      catalog.format_credits(item_detail_gui.read(force(), "item", GEAR).figures.mid) }
    assert.are.same({ false, true, "gb-detail.history-locked" }, locked)
    assert.are.same({ true, true, false, "gb-detail.history-scale" }, unlocked)
    assert.are.equal(now[2], now[1])
  end)

  test("hides its figures, rather than leaving them stale, for an item without a market", function()
    show("item/" .. GEAR)
    local shown = info().body.visible
    -- The pistol has no base value (no reachable recipe), like an item that lost its value.
    view().selected = "item/pistol"
    bazaar_gui.refresh(player)
    assert.is_true(shown)
    assert.is_false(info().body.visible)
    assert.is_nil(info().key)
    view().selected = "item/" .. GEAR
    bazaar_gui.refresh(player)
    assert.is_true(info().body.visible)
    assert.are.equal(catalog.format_credits(pricing.base_value("item", GEAR)), info().figures.base.caption)
  end)

  test("breaks a crafted item's value down into its recipe, ingredients and crafting time", function()
    show("item/" .. GEAR)
    -- Space Age prices the gear by foundry casting, vanilla by its own recipe from two plates.
    local source = pricing.value_source("item/" .. GEAR)
    local breakdown = item_detail_gui.read(force(), "item", GEAR).breakdown
    assert.are.same({ "recipe", source.recipe }, { breakdown.kind, breakdown.name })
    assert.is_true(prototypes.recipe[source.recipe] ~= nil)
    if not script.active_mods["space-age"] then
      assert.are.same({ GEAR, "item/" .. PLATE, 2 }, { source.recipe, source.inputs[1].key, source.inputs[1].amount })
    end
    assert.are.equal(#source.inputs, #breakdown.inputs)
    for i, input in ipairs(source.inputs) do
      assert.are.same({ input.key, input.amount }, { breakdown.inputs[i].key, breakdown.inputs[i].amount })
    end
    assert.is_true(near(pricing.base_value("item", GEAR), breakdown.graph_value))
    assert.are.equal("gb-detail.source-recipe", info().source.caption[1])
    assert.is_true(info().inputs[#source.inputs].visible)
    assert.is_false(info().inputs[#source.inputs + 1].visible)
    assert.is_true(info().cost.visible)
    local ore = item_detail_gui.read(force(), "item", "iron-ore").breakdown
    local water = item_detail_gui.read(force(), "fluid", "water").breakdown
    assert.are.same({ "mine", "iron-ore", "pump", "water" }, { ore.kind, ore.name, water.kind, water.name })
  end)

  test("gives back every base value from the source the valuation kept", function()
    local multiplier = settings.startup[pricing.MULTIPLIER_SETTING].value
    local checked = 0
    for key, value in pairs(storage.base_values) do
      local source = pricing.value_source(key)
      assert.is_true(source ~= nil, key)
      local total = source.cost
      for _, input in ipairs(source.inputs) do total = total + input.amount * input.value end
      local expected = math.max(math.max(total / source.share / source.amount, valuation.MIN_VALUE) * multiplier,
        valuation.MIN_VALUE)
      assert.is_true(math.abs(expected - value) <= 1e-9 * value, key)
      checked = checked + 1
    end
    assert.is_true(checked > 150)
  end)

  test("shows a value fixed by a mod, and a factor, with the products following", function()
    remote.call("galactic-bazaar", "set_value", "item", PLATE, 10)
    remote.call("galactic-bazaar", "scale_value", "item", GEAR, 3)
    local plate = item_detail_gui.read(force(), "item", PLATE).breakdown
    local gear = item_detail_gui.read(force(), "item", GEAR).breakdown
    -- A product made from plates uses the fixed value.
    local from_plate
    for _, source in pairs(storage.value_sources) do
      for _, input in ipairs(source.inputs) do
        if input.key == "item/" .. PLATE then from_plate = input.value end
      end
    end
    show("item/" .. GEAR)
    local factor_line = { info().factor.visible, info().factor.caption[1] }
    view().selected = "item/" .. PLATE
    bazaar_gui.refresh(player)
    local fixed_line = { info().source.caption[1], info().inputs[1].visible, info().cost.visible }
    storage.value_overrides = {}
    value_overrides.rebuild()
    assert.are.same({ "fixed", 10, 10 }, { plate.kind, plate.fixed, plate.value })
    assert.are.same({ "recipe", 3 }, { gear.kind, gear.factor })
    assert.are.equal(10, from_plate)
    assert.is_true(near(gear.graph_value * 3, gear.value))
    assert.are.same({ true, "gb-detail.factor" }, factor_line)
    assert.are.same({ "gb-detail.source-fixed", false, false }, fixed_line)
  end)

  test("values a quality from the normal breakdown, and lists the quality ladder", function()
    local detail = item_detail_gui.read(force(), "item", GEAR)
    if not script.active_mods["quality"] then
      assert.are.same({}, detail.ladder)
      return
    end
    local rare = item_detail_gui.read(force(), "item", GEAR, "rare", 10)
    local normal = pricing.base_value("item", GEAR)
    assert.is_true(near(9 * normal, rare.figures.base_value))
    assert.is_true(near(9 * normal, rare.breakdown.value))
    assert.are.same({ 9, normal }, { rare.breakdown.ratio, rare.breakdown.normal_value })
    assert.is_nil(rare.seen_tick)
    assert.is_true(rare.impact.buy.average > rare.figures.buy * 0.99)
    assert.are.equal(storage.quality_levels.rare, detail.ladder[2].level)
    show("item/" .. GEAR)
    assert.is_true(info().ladder.visible)
    state().markets["item/" .. GEAR .. "@rare"] = nil
  end)

  test("works on a save whose base values were built before the breakdown existed", function()
    local recipe = pricing.value_source("item/" .. GEAR).recipe
    storage.value_sources = nil
    show("item/" .. GEAR)
    local caption = info().source.caption[1]
    local cost_visible = info().cost.visible
    value_overrides.rebuild()
    assert.are.equal("gb-detail.source-unknown", caption)
    assert.is_false(cost_visible)
    assert.are.equal(recipe, pricing.value_source("item/" .. GEAR).recipe)
  end)

  test("updates its elements in place and stays within the window's budget", function()
    show("item/" .. GEAR, 100)
    local first = info().figures.buy
    local profiler = helpers.create_profiler()
    for _ = 1, 10 do item_detail_gui.refresh(player, view().elements, "item", GEAR, 100) end
    profiler.stop()
    profiler.divide(10)
    log({ "", "[galactic-bazaar] item detail refresh (one item, nothing changed): ", profiler })
    profiler = helpers.create_profiler()
    for _ = 1, 10 do bazaar_gui.refresh(player) end
    profiler.stop()
    profiler.divide(10)
    log({ "", "[galactic-bazaar] market tab refresh with the item detail (nothing changed): ", profiler })
    -- The costliest periodic refresh for the detail: the price seen changed, so the figures and history
    -- are rewritten (only the selected item's price is renewed, as the list's prices are not the
    -- detail's cost).
    profiler = helpers.create_profiler(true)
    for _ = 1, 10 do
      market.sell(force().index, "item", GEAR, 1)
      state().feed["item/" .. GEAR] = nil
      profiler.restart()
      bazaar_gui.refresh(player)
      profiler.stop()
    end
    profiler.divide(10)
    log({ "", "[galactic-bazaar] market tab refresh with the item detail (price seen changed): ", profiler })
    assert.is_true(first.valid)
    assert.are.equal(first, info().figures.buy)
  end)

  test("keeps the breakdown and refreshes the detail across a save and reload", function()
    show("item/" .. GEAR)
    storage.gb_test_hub = hub.unit_number
    storage.gb_test_recipe = pricing.value_source("item/" .. GEAR).recipe
  end).after_reload_mods(function()
    local reloaded = game.get_player(1)
    local market_view = bazaar_gui.view(reloaded.index, "market")
    bazaar_gui.refresh(reloaded)
    local kept = { pricing.value_source("item/" .. GEAR).recipe, market_view.selected,
      market_view.elements.info.source.caption[1] }
    bazaar_gui.close(reloaded.index)
    -- The reload emptied the file's locals: the hub is removed here, or later windows would bind it.
    local leftover = hubs.get(storage.gb_test_hub)
    if leftover then leftover.destroy() end
    local expected = storage.gb_test_recipe
    storage.gb_test_hub, storage.gb_test_recipe = nil, nil
    assert.are.same({ expected, "item/" .. GEAR, "gb-detail.source-recipe" }, kept)
  end)
end)
