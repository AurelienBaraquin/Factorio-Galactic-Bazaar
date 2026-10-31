-- In-game tests of the built-in explanations (#111): the Tips and tricks entries (Space Age and quality
-- ones only with them), the tooltips of the Market, Contracts, Planets and Logistics tabs, tooltips
-- that follow the force's state written only when what they show changed, and the tooltip caches
-- across a save and reload. That every key exists in both locales is checked outside the game, by
-- spec/locale_spec.lua: the headless game translates nothing (no client is connected).
local test_helpers = require("tests.helpers")
local bazaar_gui = require("scripts.bazaar_gui")
local concessions = require("scripts.concessions")
local contracts = require("scripts.contracts")
local finance = require("scripts.finance")
local loans = require("scripts.loans")

local TIPS = {
  "gb-galactic-bazaar", "gb-bazaar-window", "gb-trading-hub", "gb-prices", "gb-deliveries", "gb-account",
  "gb-insolvency", "gb-research", "gb-alerts", "gb-power-trading", "gb-circuits", "gb-contracts", "gb-reputation",
  "gb-rental", "gb-planets", "gb-outsourcing", "gb-loans",
}

local player, created

local function force_index() return game.forces.player.index end
local function state() return storage.forces[force_index()] end
local function technology(name) return game.forces.player.technologies[name] end
local function window() return player.gui.screen[bazaar_gui.WINDOW] end

local function place(name, dx, dy)
  local entity = player.surface.create_entity({
    name = name, position = { player.position.x + dx, player.position.y + dy }, force = "player", raise_built = true,
  })
  created[#created + 1] = entity
  return entity
end

local function find(element, action)
  if element.tags.gb_action == action then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action)
    if found then return found end
  end
end

-- The locale key of a tooltip, or nil when it has none.
local function key(element)
  local tooltip = element.tooltip
  return type(tooltip) == "table" and tooltip[1] or nil
end

local function tip_exists(name)
  return (pcall(prototypes.get_history, "tips-and-tricks-item", name))
end

-- The row of the Contracts tab that shows contract `id`.
local function contract_row(id)
  local list = contracts.listed(force_index())
  for i, contract in ipairs(list) do
    if contract.id == id then return bazaar_gui.view(player.index, "contracts").elements.rows[i] end
  end
end

local function incoming_spec()
  return {
    kind = "incoming", counterparty = "Test counterparty",
    provides = { { kind = "item", name = "iron-plate", quality = "normal", count = 10 } },
    requires = { { kind = "item", name = "iron-gear-wheel", quality = "normal", count = 5 } },
    reward = 10, deposit = 1, penalty = 1, duration_ticks = 36000, accept_ticks = 36000,
  }
end

describe("built-in explanations", function()
  local hub
  before_each(function()
    player = game.get_player(1)
    created = {}
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_explanations = {
      balance = state().balance, reputation = state().reputation, history = #state().contracts.history,
      reservations = state().reservations,
      researched = {
        concession = technology(concessions.CONCESSION_TECHNOLOGY).researched,
        credit = technology(finance.CREDIT_TECHNOLOGY).researched,
        bazaar = technology(bazaar_gui.TECHNOLOGY).researched,
      },
    }
    technology(concessions.CONCESSION_TECHNOLOGY).researched = true
    technology(finance.CREDIT_TECHNOLOGY).researched = true
    technology(bazaar_gui.TECHNOLOGY).researched = true
    test_helpers.set_balance(state(), 1e6)
    state().reputation = 0
    state().contracts.open = {}
    state().reservations = {}
    hub = place("gb-hub", 3, 0)
    hub.energy = hub.electric_buffer_size
    local chest = place("gb-import-chest", 6, 0)
    -- Kept in storage too: the reload test empties `created`.
    storage.gb_test_explanations.entities = { hub, chest }
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    bazaar_gui.close(player.index)
    local saved = storage.gb_test_explanations
    for _, entity in ipairs(created or {}) do
      if entity.valid then
        storage.freight.hubs[entity.unit_number] = nil
        entity.destroy()
      end
    end
    if saved then
      for _, entity in ipairs(saved.entities or {}) do
        if entity.valid then
          storage.freight.hubs[entity.unit_number] = nil
          entity.destroy()
        end
      end
      test_helpers.set_balance(state(), saved.balance)
      state().reputation = saved.reputation
      local history = state().contracts.history
      while #history > saved.history do table.remove(history) end
      state().reservations = saved.reservations
      technology(concessions.CONCESSION_TECHNOLOGY).researched = saved.researched.concession
      technology(finance.CREDIT_TECHNOLOGY).researched = saved.researched.credit
      technology(bazaar_gui.TECHNOLOGY).researched = saved.researched.bazaar
      storage.gb_test_explanations = nil
    end
    state().contracts.open = {}
    storage.concessions = {}
  end)

  test("has a Tips and tricks entry per system, the Space Age and quality ones only with them", function()
    for _, name in ipairs(TIPS) do assert.is_true(tip_exists(name), name) end
    assert.are.equal(script.active_mods["space-age"] ~= nil, tip_exists("gb-space-age"))
    assert.are.equal(script.feature_flags.quality == true, tip_exists("gb-quality"))
  end)

  test("explains every figure, column and button of the Market tab", function()
    bazaar_gui.open(player, "market", hub)
    local view = bazaar_gui.view(player.index, "market")
    local elements = view.elements
    assert.are.same({ "gb-overview.balance-tooltip", "gb-gui.overdraft-terms", "gb-gui.reputation-effects",
      "gb-gui.hub-tooltip", "gb-logistics.tier-tooltip", "gb-gui.column-trend-tooltip", "gb-gui.quantity-tooltip",
      "gb-gui.preview-tooltip" },
      { key(elements.balance), key(elements.overdraft), key(elements.reputation), key(elements.power),
        key(elements.freight), key(elements.trend_header), key(elements.quantity), key(elements.preview) })
    local row = elements.rows[1]
    assert.are.same({ "gb-gui.column-item-tooltip", "gb-gui.column-buy-tooltip", "gb-gui.column-sell-tooltip",
      "gb-gui.column-trend-tooltip" }, { key(row.icon), key(row.buy), key(row.sell), key(row.trend) })
    assert.are.same({ "gb-gui.buy-tooltip", "gb-gui.sell-tooltip" },
      { key(find(window(), "buy")), key(find(window(), "sell")) })
    assert.are.same({ "gb-gui.search-tooltip", "gb-gui.page-tooltip", "1000000000" },
      { key(elements.search), key(elements.page), elements.quantity.tooltip[2] })
  end)

  test("rewrites the Market tab's reputation and delivery tooltips only when they change", function()
    bazaar_gui.open(player, "market", hub)
    local elements = bazaar_gui.view(player.index, "market").elements
    assert.are.equal("5", elements.freight.tooltip[6])
    elements.reputation.tooltip, elements.freight.tooltip = "unchanged", "unchanged"
    bazaar_gui.refresh(player)
    assert.are.same({ "unchanged", "unchanged" }, { elements.reputation.tooltip, elements.freight.tooltip })
    state().reputation = 20
    bazaar_gui.refresh(player)
    assert.are.same({ "50", "300" }, { elements.reputation.tooltip[2], elements.reputation.tooltip[3] })
    assert.are.equal("2.5", elements.freight.tooltip[6])
  end)

  test("explains each row of the Contracts tab for its kind and state, rewritten when they change", function()
    local offer = contracts.offer(force_index(), incoming_spec())
    local lease = concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    local loan = loans.borrow(force_index(), 1)
    bazaar_gui.open(player, "contracts", hub)
    test_helpers.select_tab(player, "contracts")
    local elements = bazaar_gui.view(player.index, "contracts").elements
    assert.are.same({ "gb-gui.reputation-effects", "gb-loans.debt-tooltip" },
      { key(elements.reputation), key(elements.debt) })
    local row = contract_row(offer)
    assert.are.same({ "gb-contracts.provides-incoming-tooltip", "gb-contracts.requires-incoming-tooltip",
      "gb-contracts.terms-tooltip", "gb-contracts.offer-ends-tooltip", "gb-contracts.accept-tooltip",
      "gb-contracts.decline-tooltip" },
      { key(row.provides), key(row.requires), key(row.terms), key(row.time), key(row.primary), key(row.secondary) })
    row = contract_row(lease)
    assert.are.same({ "gb-contracts.provides-lease-tooltip", "gb-contracts.charge-terms-tooltip",
      "gb-contracts.due-lease-tooltip", "gb-contracts.abandon-lease-tooltip" },
      { key(row.provides), key(row.terms), key(row.time), key(row.primary) })
    row = contract_row(loan)
    assert.are.same({ "gb-loans.borrowed-tooltip", "gb-loans.left-tooltip", "gb-loans.installment-tooltip",
      "gb-contracts.due-loan-tooltip", "gb-loans.repay-tooltip" },
      { key(row.provides), key(row.requires), key(row.terms), key(row.time), key(row.primary) })
    -- The same contract in the same state: its row's tooltips are not written again.
    row = contract_row(offer)
    row.terms.tooltip = "unchanged"
    bazaar_gui.refresh(player)
    assert.are.equal("unchanged", row.terms.tooltip)
    contracts.decline(force_index(), offer)
    bazaar_gui.refresh(player)
    assert.are.equal("gb-contracts.charge-terms-tooltip", key(row.terms))
  end)

  test("explains the columns of the Planets and Logistics tabs", function()
    bazaar_gui.open(player, "planets", hub)
    test_helpers.select_tab(player, "planets")
    local row = bazaar_gui.view(player.index, "planets").elements.rows[1]
    assert.are.equal("gb-planets.column-free-tooltip", key(row.slots))
    local headers = row.slots.parent.children
    for i, column in ipairs({ "planet", "distance", "transit", "specialty", "free", "lease" }) do
      assert.are.equal("gb-planets.column-" .. column .. "-tooltip", key(headers[i]))
    end
    assert.are.same({ "60", "2", "25" }, { headers[2].tooltip[2], headers[2].tooltip[3], headers[2].tooltip[4] })
    test_helpers.select_tab(player, "logistics")
    local elements = bazaar_gui.view(player.index, "logistics").elements
    assert.are.same({ "gb-logistics.power-tooltip", "gb-logistics.status-tooltip", "gb-logistics.power-tooltip" },
      { key(elements.hub_rows[1].power), key(elements.hub_rows[1].status), key(elements.power) })
    assert.are.same({ "gb-logistics.module-tooltip", "gb-logistics.status-tooltip" },
      { key(elements.module_rows[1].name), key(elements.module_rows[1].status) })
  end)


  test("measures the refresh of a full Contracts tab and of the Market tab", function()
    for _ = 1, 3 do contracts.offer(force_index(), incoming_spec()) end
    concessions.lease(force_index(), hub.unit_number, "ferrum-prime", "iron-ore")
    while #contracts.listed(force_index()) < contracts.MAX_LISTED do loans.borrow(force_index(), 1) end
    bazaar_gui.open(player, "contracts", hub)
    for _, tab in ipairs({ "contracts", "market" }) do
      test_helpers.select_tab(player, tab)
      bazaar_gui.refresh(player)
      local profiler = helpers.create_profiler()
      for _ = 1, 10 do bazaar_gui.refresh(player) end
      profiler.stop()
      profiler.divide(10)
      log({ "", "[galactic-bazaar] explanations: ", tab, " tab refresh, ", #contracts.listed(force_index()),
        " contracts (one player, average of 10): ", profiler })
    end
  end)

  test("keeps its tooltip caches across a save and reload", function()
    contracts.offer(force_index(), incoming_spec())
    bazaar_gui.open(player, "contracts", hub)
    test_helpers.select_tab(player, "contracts")
    bazaar_gui.open(player, "market", hub)
  end).after_reload_mods(function()
    player = game.get_player(1)
    bazaar_gui.refresh(player)
    test_helpers.select_tab(player, "contracts")
    local view = bazaar_gui.view(player.index, "contracts")
    assert.is_truthy(view.shown.rows[1])
    assert.are.equal("gb-contracts.accept-tooltip", key(view.elements.rows[1].primary))
    assert.are.equal(0, bazaar_gui.view(player.index, "market").tooltips.reputation)
  end)
end)
