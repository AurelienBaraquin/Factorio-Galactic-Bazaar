local statement = require("scripts.core.statement")

local function entry(tick, kind, amount, extra)
  local result = { tick = tick, kind = kind, amount = amount, balance = 0 }
  for field, value in pairs(extra or {}) do result[field] = value end
  return result
end

describe("statement.label and statement.category", function()
  local cases = {
    { entry(1, "sell", 1, { key = "item/iron-plate" }), "sell", "sales" },
    { entry(1, "sell", 1, { key = "fluid/water" }), "sell", "sales" },
    { entry(1, "buy", -1, { key = "item/iron-plate@rare" }), "buy", "purchases" },
    { entry(1, "sell", 1, { key = "energy/electricity" }), "power-sell", "power" },
    { entry(1, "buy", -1, { key = "energy/electricity" }), "power-buy", "power" },
    { entry(1, "freight", -1, { key = "item/iron-plate" }), "freight", "freight" },
    { entry(1, "freight-refund", 1, { key = "item/iron-plate" }), "freight-refund", "freight" },
    { entry(1, "overdraft-interest", -1, { key = "account/overdraft" }), "overdraft-interest", "interest" },
    { entry(1, "contract-guarantee", -1, { key = "contract/3", contract_kind = "incoming" }), "contract-guarantee",
      "contracts" },
    { entry(1, "contract-installment", 1, { key = "contract/3" }), "contract-installment", "contracts" },
    { entry(1, "contract-charge", -1, { key = "contract/3", contract_kind = "rental" }), "contract-charge",
      "contracts" },
    { entry(1, "contract-fulfilled", 1, { key = "contract/3" }), "contract-fulfilled", "contracts" },
    { entry(1, "contract-failed", 0, { key = "contract/3" }), "contract-failed", "contracts" },
    { entry(1, "contract-voided", 1, { key = "contract/3" }), "contract-voided", "contracts" },
    { entry(1, "contract-charge", -1, { key = "contract/4", contract_kind = "loan" }), "contract-charge", "loans" },
    { entry(1, "contract-failed", 0, { key = "contract/4", contract_kind = "loan" }), "contract-failed", "loans" },
    { entry(1, "contract-advance", 1, { key = "contract/4" }), "contract-advance", "loans" },
    { entry(1, "contract-repaid", -1, { key = "contract/4" }), "contract-repaid", "loans" },
    { entry(1, "loan-arrears", -1, { key = "loans" }), "loan-arrears", "loans" },
    { entry(1, "bankruptcy-restructured", 1, { key = "account/bankruptcy" }), "bankruptcy-restructured",
      "bankruptcy" },
    { entry(1, "bankruptcy-debt", -1, { key = "account/bankruptcy" }), "bankruptcy-debt", "bankruptcy" },
    { entry(1, "something-new", 1), "other", "other" },
    { entry(1, nil, 1), "other", "other" },
  }
  for _, case in ipairs(cases) do
    it("files " .. tostring(case[1].kind) .. " " .. tostring(case[1].key) .. " as " .. case[3], function()
      assert.are.same({ case[2], case[3] }, { statement.label(case[1]), statement.category(case[1]) })
    end)
  end

  it("gives every label a category among CATEGORIES, and every category a label", function()
    local known, used = {}, {}
    for _, category in ipairs(statement.CATEGORIES) do known[category] = true end
    for _, label in ipairs(statement.LABELS) do
      local category = statement.LABEL_CATEGORY[label]
      assert.is_true(known[category], label)
      used[category] = true
    end
    for _, category in ipairs(statement.CATEGORIES) do assert.is_true(used[category], category) end
  end)
end)

describe("statement.subject", function()
  it("reads goods, quality, energy, contracts and account entries", function()
    assert.are.same({ type = "item", name = "iron-plate", quality = "normal" },
      statement.subject({ key = "item/iron-plate" }))
    assert.are.same({ type = "item", name = "iron-plate", quality = "rare" },
      statement.subject({ key = "item/iron-plate@rare" }))
    assert.are.same({ type = "fluid", name = "water", quality = "normal" }, statement.subject({ key = "fluid/water" }))
    assert.are.same({ type = "energy", name = "electricity", quality = "normal" },
      statement.subject({ key = "energy/electricity" }))
    assert.are.same({ type = "contract", id = 12, contract_kind = "loan" },
      statement.subject({ key = "contract/12", contract_kind = "loan" }))
    assert.are.same({ type = "contract", id = 12 }, statement.subject({ key = "contract/12" }))
    assert.is_nil(statement.subject({ key = "account/overdraft" }))
    assert.is_nil(statement.subject({ key = "loans" }))
    assert.is_nil(statement.subject({}))
  end)
end)

describe("statement.page", function()
  local function journal(count)
    local list = {}
    for i = 1, count do
      list[i] = entry(i, i % 2 == 0 and "buy" or "sell", i % 2 == 0 and -i or i, { key = "item/iron-plate" })
    end
    return list
  end

  it("lists the newest entries first, PAGE_SIZE per page", function()
    local page = statement.page(journal(30), "all", 1)
    assert.are.same({ 1, 3, 30 }, { page.page, page.pages, page.count })
    assert.are.equal(statement.PAGE_SIZE, #page.entries)
    assert.are.same({ 30, 29 }, { page.entries[1].tick, page.entries[2].tick })
    local last = statement.page(journal(30), "all", 3)
    assert.are.equal(30 - 2 * statement.PAGE_SIZE, #last.entries)
    assert.are.equal(1, last.entries[#last.entries].tick)
  end)

  it("keeps only the entries of the filtered category", function()
    local page = statement.page(journal(30), "sales", 1)
    assert.are.same({ 15, 2 }, { page.count, page.pages })
    for _, listed in ipairs(page.entries) do assert.are.equal("sell", listed.kind) end
    assert.are.equal(29, page.entries[1].tick)
  end)

  it("files an entry by the category recorded on it, or computes it for an older entry", function()
    local list = { entry(1, "sell", 1, { key = "item/a", category = "sales" }), entry(2, "overdraft-interest", -1) }
    assert.are.equal(1, statement.page(list, "sales", 1).count)
    assert.are.equal(1, statement.page(list, "interest", 1).count)
  end)

  it("clamps the page into range, and gives one empty page for an empty list", function()
    assert.are.equal(3, statement.page(journal(30), "all", 9).page)
    assert.are.equal(1, statement.page(journal(30), "all", -2).page)
    local empty = statement.page({}, "interest", 4)
    assert.are.same({ 1, 1, 0, {} }, { empty.page, empty.pages, empty.count, empty.entries })
  end)

  it("treats an unknown filter as all", function()
    assert.are.equal(30, statement.page(journal(30), "nonsense", 1).count)
  end)
end)

describe("statement.record and statement.totals", function()
  local MINUTE = statement.MINUTE_TICKS

  local function record(state, tick, kind, amount, extra)
    return statement.record(state, entry(tick, kind, amount, extra), amount)
  end

  it("creates the ledger at the first transaction and returns its category", function()
    local state = {}
    assert.are.equal("sales", record(state, 125, "sell", 10, { key = "item/a" }))
    assert.are.equal("power", record(state, 130, "buy", -3, { key = "energy/electricity" }))
    assert.are.equal(125, state.ledger.start_tick)
    assert.are.same({ income = 10, spending = 0, count = 1 }, state.ledger.total.sales)
    assert.are.same({ income = 0, spending = 3, count = 1 }, state.ledger.minutes[0].power)
  end)

  it("sums income, spending, net and transactions per category and overall", function()
    local state = {}
    record(state, 10, "sell", 100, { key = "item/a" })
    record(state, 20, "buy", -40, { key = "item/a" })
    record(state, 30, "freight", -2, { key = "item/a" })
    record(state, 40, "freight-refund", 5, { key = "item/a" })
    record(state, 50, "contract-failed", 0, { key = "contract/1" })
    record(state, 60, "contract-charge", -7, { key = "contract/2", contract_kind = "loan" })
    local totals = statement.totals(state.ledger, "all", 60)
    assert.are.same({ income = 100, spending = 0, net = 100, count = 1 }, totals.categories.sales)
    assert.are.same({ income = 0, spending = 40, net = -40, count = 1 }, totals.categories.purchases)
    assert.are.same({ income = 5, spending = 2, net = 3, count = 2 }, totals.categories.freight)
    assert.are.same({ income = 0, spending = 0, net = 0, count = 1 }, totals.categories.contracts)
    assert.are.same({ income = 0, spending = 7, net = -7, count = 1 }, totals.categories.loans)
    assert.are.same({ income = 0, spending = 0, net = 0, count = 0 }, totals.categories.interest)
    assert.are.same({ income = 105, spending = 49, net = 56, count = 6 }, totals.all)
    assert.are.equal(10, totals.since_tick)
  end)

  it("counts a period by whole minutes: the current one and those before it", function()
    local state = {}
    record(state, 0, "sell", 1, { key = "item/a" })
    record(state, 4 * MINUTE + 10, "sell", 2, { key = "item/a" })
    record(state, 14 * MINUTE + 59, "sell", 4, { key = "item/a" })
    local now = 14 * MINUTE + 3000
    local ten = statement.totals(state.ledger, "ten-minutes", now)
    assert.are.same({ 4, 1, 5 * MINUTE }, { ten.categories.sales.income, ten.all.count, ten.since_tick })
    assert.are.equal(7, statement.totals(state.ledger, "hour", now).all.income)
    assert.are.equal(0, statement.totals(state.ledger, "hour", now).since_tick)
    assert.are.equal(7, statement.totals(state.ledger, "all", now).all.income)
    assert.are.equal(7, statement.totals(state.ledger, "unknown", now).all.income)
  end)

  it("drops minutes older than the ledger keeps, never the totals since records began", function()
    local state = {}
    record(state, 0, "sell", 1, { key = "item/a" })
    record(state, statement.LEDGER_MINUTES * MINUTE, "sell", 2, { key = "item/a" })
    assert.is_nil(state.ledger.minutes[0])
    assert.are.equal(2, statement.totals(state.ledger, "hour", statement.LEDGER_MINUTES * MINUTE).all.income)
    assert.are.equal(3, statement.totals(state.ledger, "all", statement.LEDGER_MINUTES * MINUTE).all.income)
  end)

  it("starts a period at the ledger's start when it began later", function()
    local state = {}
    record(state, 3 * MINUTE + 7, "sell", 1, { key = "item/a" })
    assert.are.equal(3 * MINUTE + 7, statement.totals(state.ledger, "hour", 3 * MINUTE + 9).since_tick)
  end)

  it("gives zero totals and no start without a ledger", function()
    local totals = statement.totals(nil, "hour", 100)
    assert.are.same({ income = 0, spending = 0, net = 0, count = 0 }, totals.all)
    assert.are.same({ income = 0, spending = 0, net = 0, count = 0 }, totals.categories.other)
    assert.is_nil(totals.since_tick)
  end)

  it("folds a merged force's ledger in, minute by minute", function()
    local destination, source, alone = {}, {}, {}
    record(destination, MINUTE + 1, "sell", 3, { key = "item/a" })
    record(source, 5, "sell", 4, { key = "item/a" })
    record(source, MINUTE + 2, "buy", -1, { key = "item/a" })
    statement.merge_ledger(destination, source)
    assert.are.same({ 5, 7, 2 }, { destination.ledger.start_tick, destination.ledger.total.sales.income,
      destination.ledger.total.sales.count })
    assert.are.same({ income = 3, spending = 0, count = 1 }, destination.ledger.minutes[1].sales)
    assert.are.same({ income = 0, spending = 1, count = 1 }, destination.ledger.minutes[1].purchases)
    statement.merge_ledger(alone, source)
    assert.are.equal(source.ledger, alone.ledger)
    statement.merge_ledger(alone, {})
    assert.are.equal(source.ledger, alone.ledger)
  end)
end)

describe("statement.format_time", function()
  it("writes a map tick as hours, minutes and seconds of game time", function()
    assert.are.same({ "0:00:00", "0:00:01", "1:02:03", "26:00:00", "0:00:00" },
      { statement.format_time(0), statement.format_time(119), statement.format_time((3723) * 60),
        statement.format_time(26 * 216000), statement.format_time(-500) })
  end)
end)

describe("statement.format_signed", function()
  it("writes credits in green when received, red when paid, plain when nothing moved", function()
    assert.are.same({ "[color=0.5,1,0.5]12.50[/color]", "[color=1,0.5,0.4]-1.00k[/color]", "0.00" },
      { statement.format_signed(12.5), statement.format_signed(-1000), statement.format_signed(0) })
  end)
end)

describe("statement.format_quantity", function()
  it("writes whole quantities in full below 1000, then short, and fractions with decimals", function()
    assert.are.same({ "0", "7", "999", "1.00k", "12.5k", "2.50", "" },
      { statement.format_quantity(0), statement.format_quantity(7), statement.format_quantity(999),
        statement.format_quantity(1000), statement.format_quantity(12500), statement.format_quantity(2.5),
        statement.format_quantity(nil) })
  end)
end)
