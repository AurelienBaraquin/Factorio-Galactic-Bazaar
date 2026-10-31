-- In-game tests of the Statement tab of the Galactic Bazaar window (scripts/statement_gui.lua, #108):
-- the journal newest first with labels, subjects and the balance after each entry, the category
-- filter, the totals over a period and whether the journal still holds it, pagination, the contract
-- kind recorded on contract entries, entries of an older save, the refresh cost and persistence.
local account = require("scripts.core.account")
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local contracts = require("scripts.contracts")
local finance = require("scripts.finance")
local loans = require("scripts.loans")
local statement = require("scripts.core.statement")
local test_helpers = require("tests.helpers")

local player

local function force_state() return storage.forces[player.force_index] end
local function view() return bazaar_gui.view(player.index, "statement") end
local function rows() return view().elements.rows end
local function totals() return view().elements.totals end

local function open()
  bazaar_gui.open(player, "statement")
  return view()
end

local function find(element, action)
  if element.tags.gb_action == action then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, action)
    if found then return found end
  end
end

local function click(action)
  bazaar_gui.on_gui_input({ element = find(player.gui.screen[bazaar_gui.WINDOW], action),
    player_index = player.index, name = defines.events.on_gui_click })
end

-- Picks entry `index` of one of the tab's drop-downs, as the player would.
local function choose(action, index)
  local element = find(player.gui.screen[bazaar_gui.WINDOW], action)
  element.selected_index = index
  bazaar_gui.on_gui_input({ element = element, player_index = player.index,
    name = defines.events.on_gui_selection_state_changed })
end

local function filter_index(category)
  for i, name in ipairs(statement.CATEGORIES) do
    if name == category then return i + 1 end
  end
end

local function period_index(name)
  for i, period in ipairs(statement.PERIODS) do
    if period.name == name then return i end
  end
end

local function entry(tick, kind, amount, key, extra)
  local result = { tick = tick, kind = kind, amount = amount, key = key, balance = 1000 + tick, quantity = 5 }
  for field, value in pairs(extra or {}) do result[field] = value end
  -- As account.lua records it.
  result.category = statement.category(result)
  return result
end

describe("Statement tab", function()
  before_each(function()
    player = game.get_player(1)
    -- In storage, so that it survives the reload of the last test.
    storage.gb_test_statement = {
      journal = force_state().journal, ledger = force_state().ledger, balance = force_state().balance,
    }
    force_state().journal, force_state().ledger = {}, nil
    test_helpers.set_balance(force_state(), 1e6)
  end)
  after_each(function()
    -- After a reload the file runs again and its locals start empty: fetch them again.
    player = game.get_player(1)
    bazaar_gui.close(player.index)
    local saved = storage.gb_test_statement
    if saved then
      force_state().journal, force_state().ledger = saved.journal, saved.ledger
      test_helpers.set_balance(force_state(), saved.balance)
      storage.gb_test_statement = nil
    end
    force_state().contracts.open = {}
  end)

  test("is a tab of the window, listing the journal newest first with the balance after each entry", function()
    local now = game.tick
    force_state().journal = {
      entry(now - 120, "sell", 40, "item/iron-plate"),
      entry(now - 60, "buy", -25, "fluid/water"),
      entry(now, "freight", -1.25, "item/iron-plate"),
    }
    open()
    assert.are.equal("statement", bazaar_gui.window(player.index).tab)
    local first, second, third = rows()[1], rows()[2], rows()[3]
    assert.are.same({ "gb-statement.kind-freight" }, first.kind.caption)
    assert.are.equal("gb-statement.kind-freight-tooltip", first.kind.tooltip[1])
    assert.are.equal(statement.format_signed(-1.25), first.amount.caption)
    assert.are.equal(catalog.format_credits(1000 + now), first.balance.caption)
    assert.are.equal(statement.format_time(now), first.time.caption)
    assert.are.equal(statement.format_time(now - 120), third.time.caption)
    assert.are.equal("[item=iron-plate] ", first.subject.caption[2])
    assert.are.equal("[fluid=water] ", second.subject.caption[2])
    assert.are.same({ "gb-statement.kind-sell" }, third.kind.caption)
    assert.are.equal("5", third.quantity.caption)
    -- Unused rows stay in the table, emptied rather than hidden (a hidden cell would shift columns).
    assert.are.same({ "", true }, { rows()[4].kind.caption, rows()[4].kind.visible })
    assert.are.same({ "gb-gui.page", "1", "1" }, view().elements.page.caption)
    -- A recurring transaction merged into the newest entry updates its row in place.
    local newest = force_state().journal[3]
    newest.amount, newest.first_tick, newest.tick = -4, now, now + 60
    bazaar_gui.refresh(player)
    assert.are.equal(statement.format_signed(-4), first.amount.caption)
    assert.are.same({ "gb-statement.merged", statement.format_time(now), statement.format_time(now + 60) },
      first.time.tooltip)
    -- The totals come from the ledger, which has recorded nothing here.
    assert.are.same({ "gb-statement.since-none" }, view().elements.since.caption)
    assert.are.equal("0", totals().all.count.caption)
  end)

  test("names electricity, contracts and goods whose prototype is gone, and labels unknown kinds", function()
    local now = game.tick
    force_state().journal = {
      entry(now, "sell", 3, "energy/electricity"),
      entry(now, "contract-charge", -9, "contract/7", { contract_kind = "loan" }),
      entry(now, "contract-guarantee", -9, "contract/8"),
      entry(now, "sell", 3, "item/gb-removed-item"),
      entry(now, "mystery", 1, "account/x"),
    }
    open()
    assert.are.same({ "gb-statement.kind-other" }, rows()[1].kind.caption)
    assert.are.same({ "gb-statement.kind-other-tooltip", "mystery" }, rows()[1].kind.tooltip)
    assert.are.equal("", rows()[1].subject.caption)
    assert.are.equal("item/gb-removed-item", rows()[2].subject.caption)
    assert.are.same({ "gb-statement.contract-unknown", "8" }, rows()[3].subject.caption)
    assert.are.same({ "gb-statement.contract", "7", { "gb-notify.kind-loan" } }, rows()[4].subject.caption)
    assert.are.same({ "gb-statement.kind-power-sell" }, rows()[5].kind.caption)
    assert.are.same({ "gb-statement.electricity" }, rows()[5].subject.caption)
  end)

  test("filters by category and starts the filtered list on its first page", function()
    local now = game.tick
    local journal = {}
    for i = 1, 40 do
      journal[i] = i % 4 == 0 and entry(now, "overdraft-interest", -1, "account/overdraft")
        or entry(now, "sell", 1, "item/iron-plate")
    end
    force_state().journal = journal
    open()
    click("statement-next")
    assert.are.equal(2, view().page)
    choose("statement-filter", filter_index("interest"))
    assert.are.same({ "interest", 1 }, { view().filter, view().page })
    for i = 1, 10 do assert.are.same({ "gb-statement.kind-overdraft-interest" }, rows()[i].kind.caption) end
    assert.are.equal("", rows()[11].kind.caption)
    assert.are.same({ "gb-gui.page", "1", "1" }, view().elements.page.caption)
    choose("statement-filter", 1)
    assert.are.equal(statement.ALL, view().filter)
    assert.are.same({ "gb-gui.page", "1", "4" }, view().elements.page.caption)
  end)

  test("pages through the journal, clamped to its first and last page", function()
    local now = game.tick
    local journal = {}
    for i = 1, statement.PAGE_SIZE * 2 + 1 do journal[i] = entry(now - 100 + i, "sell", i, "item/iron-plate") end
    force_state().journal = journal
    open()
    click("statement-previous")
    assert.are.equal(1, view().page)
    click("statement-next")
    click("statement-next")
    click("statement-next")
    assert.are.equal(3, view().page)
    assert.are.equal(statement.format_signed(1), rows()[1].amount.caption)
    assert.are.equal("", rows()[2].amount.caption)
    assert.are.same({ "gb-gui.page", "3", "3" }, view().elements.page.caption)
  end)

  test("totals each category over the chosen period from the ledger, which counts every transaction", function()
    local now = game.tick
    -- A sale from before the period, as the ledger keeps it in its totals since records began.
    force_state().ledger = { start_tick = 0, minutes = {},
      total = { sales = { income = 500, spending = 0, count = 1 } } }
    local function buy(amount)
      account.apply(force_state(), -amount,
        { tick = now, kind = "buy", key = "item/iron-plate", quantity = 1, merge_ticks = 3600 })
    end
    buy(2)
    buy(3)
    account.apply(force_state(), -1, { tick = now, kind = "freight", key = "item/iron-plate", quantity = 2 })
    assert.are.equal(2, #force_state().journal)
    open()
    choose("statement-period", period_index("ten-minutes"))
    assert.are.same({ catalog.format_credits(0), catalog.format_credits(5), "2" },
      { totals().purchases.income.caption, totals().purchases.spending.caption, totals().purchases.count.caption })
    assert.are.equal("0", totals().sales.count.caption)
    assert.are.equal(statement.format_signed(-1), totals().freight.net.caption)
    assert.are.equal(statement.format_signed(-6), totals().all.net.caption)
    local first_minute = math.floor(now / statement.MINUTE_TICKS) - 9
    assert.are.same({ "gb-statement.since", statement.format_time(math.max(0, first_minute * statement.MINUTE_TICKS)) },
      view().elements.since.caption)
    choose("statement-period", period_index("all"))
    assert.are.same({ "1", statement.format_signed(494) }, { totals().sales.count.caption, totals().all.net.caption })
    assert.are.same({ "gb-statement.covers", "2", statement.format_time(now), tostring(account.JOURNAL_SIZE) },
      view().elements.covers.caption)
  end)

  test("files a loan's contract entries under loans, with the contract's kind", function()
    local credit = player.force.technologies[finance.CREDIT_TECHNOLOGY]
    local researched = credit.researched
    credit.researched = true
    local id = loans.borrow(player.force_index, 1)
    credit.researched = researched
    assert.is_number(id)
    local journal = force_state().journal
    local advance = journal[#journal]
    assert.are.same({ "contract-advance", "contract/" .. id, "loan" },
      { advance.kind, advance.key, advance.contract_kind })
    assert.are.equal("loans", statement.category(advance))
    contracts.abandon(player.force_index, id)
    for _, listed in ipairs(force_state().journal) do
      if listed.key == "contract/" .. id then assert.are.equal("loans", statement.category(listed)) end
    end
    open()
    choose("statement-filter", filter_index("loans"))
    assert.are.same({ "gb-statement.contract", tostring(id), { "gb-notify.kind-loan" } }, rows()[1].subject.caption)
  end)

  test("opens on a save without the window's state, and reads entries without a balance", function()
    storage.bazaar_gui = nil
    -- An entry of an older version: no balance after it, no category, and no ledger yet.
    force_state().journal = { { tick = game.tick, kind = "sell", amount = 4, key = "item/iron-plate" } }
    open()
    assert.are.equal(statement.format_signed(4), rows()[1].amount.caption)
    assert.are.equal("", rows()[1].balance.caption)
    assert.are.equal("", rows()[1].quantity.caption)
    assert.are.same({ "gb-statement.since-none" }, view().elements.since.caption)
    choose("statement-filter", filter_index("sales"))
    assert.are.same({ "gb-statement.kind-sell" }, rows()[1].kind.caption)
    -- Its next transaction starts the ledger.
    account.apply(force_state(), 1, { tick = game.tick, kind = "sell", key = "item/iron-plate", quantity = 1 })
    bazaar_gui.refresh(player)
    assert.are.equal("1", totals().sales.count.caption)
  end)

  test("measures the refresh of a full journal and ledger, unchanged and after a transaction", function()
    local now = game.tick
    local journal = {}
    for i = 1, account.JOURNAL_SIZE do
      journal[i] = entry(now - account.JOURNAL_SIZE + i, i % 3 == 0 and "buy" or "sell", i % 3 == 0 and -i or i,
        "item/iron-plate", { first_tick = now - 2 * account.JOURNAL_SIZE + i, merge_ticks = 3600 })
    end
    force_state().journal = journal
    -- A ledger holding every category in every minute of the last hour.
    local kinds = { { "sell", "item/a" }, { "buy", "item/a" }, { "freight", "item/a" }, { "buy", "energy/electricity" },
      { "contract-charge", "contract/1" }, { "contract-advance", "contract/2" }, { "overdraft-interest", "a" },
      { "bankruptcy-debt", "b" }, { "mystery", "c" } }
    local first_minute = math.floor(now / statement.MINUTE_TICKS) - statement.LEDGER_MINUTES + 1
    for minute = first_minute, first_minute + statement.LEDGER_MINUTES - 1 do
      for _, kind in ipairs(kinds) do
        statement.record(force_state(), { tick = minute * statement.MINUTE_TICKS, kind = kind[1], key = kind[2] }, 1)
      end
    end
    open()
    -- The costliest view: the hour's 60 minutes of totals, and the filter walking the whole journal.
    choose("statement-period", period_index("hour"))
    choose("statement-filter", filter_index("sales"))
    local runs = 10
    for _, changing in ipairs({ false, true }) do
      local profiler = helpers.create_profiler()
      for run = 1, runs do
        if changing then
          account.apply(force_state(), run, { tick = now, kind = "sell", key = "item/iron-plate", quantity = 1 })
        end
        bazaar_gui.refresh(player)
      end
      profiler.stop()
      profiler.divide(runs)
      log({ "", "[galactic-bazaar] statement tab refresh, ", account.JOURNAL_SIZE, " journal entries, ",
        changing and "a transaction before each" or "unchanged", " (one player, average of ", runs, "): ", profiler })
    end
    assert.are.equal(tostring(statement.LEDGER_MINUTES * #kinds + runs), totals().all.count.caption)
    assert.are.equal(statement.format_signed(runs), rows()[1].amount.caption)
  end)

  test("keeps its filter, page and period across a save and reload", function()
    local now = game.tick
    local journal = {}
    for i = 1, 30 do journal[i] = entry(now, "sell", 1, "item/iron-plate") end
    force_state().journal = journal
    open()
    choose("statement-filter", filter_index("sales"))
    choose("statement-period", period_index("hour"))
    click("statement-next")
  end).after_reload_mods(function()
    player = game.get_player(1)
    local reloaded = bazaar_gui.view(1, "statement")
    assert.are.same({ "sales", "hour", 2 }, { reloaded.filter, reloaded.period, reloaded.page })
    bazaar_gui.on_refresh_tick({ tick = (1 % bazaar_gui.SLOTS) * bazaar_gui.SLOT_TICKS })
    assert.are.same({ "gb-gui.page", "2", "3" }, reloaded.elements.page.caption)
    assert.are.same({ "gb-statement.kind-sell" }, reloaded.elements.rows[1].kind.caption)
  end)
end)
