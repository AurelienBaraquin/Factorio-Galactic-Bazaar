local catalog = require("scripts.core.catalog")

describe("catalog.search", function()
  local names = { "iron-plate", "iron-gear-wheel", "copper-plate", "steel-plate" }

  it("returns every name, sorted, for an empty filter", function()
    assert.are.same({ "copper-plate", "iron-gear-wheel", "iron-plate", "steel-plate" }, catalog.search(names, ""))
  end)

  it("keeps names containing every word, ignoring case and separators", function()
    assert.are.same({ "iron-plate" }, catalog.search(names, "Iron Plate"))
    assert.are.same({ "iron-gear-wheel" }, catalog.search(names, "gear_iron"))
    assert.are.same({}, catalog.search(names, "uranium"))
  end)

  it("treats the filter as plain text, not a pattern", function()
    assert.are.same({}, catalog.search(names, "%a+"))
  end)
end)

describe("catalog.page", function()
  local names = {}
  for i = 1, 2 * catalog.PAGE_SIZE + 3 do names[i] = string.format("item-%03d", i) end

  it("cuts pages of PAGE_SIZE and counts them", function()
    local first = catalog.page(names, 1)
    assert.are.equal(catalog.PAGE_SIZE, #first.names)
    assert.are.equal(3, first.pages)
    assert.are.equal(3, #catalog.page(names, 3).names)
  end)

  it("clamps the page to the existing ones", function()
    assert.are.equal(3, catalog.page(names, 99).page)
    assert.are.equal(1, catalog.page(names, -2).page)
    assert.are.same({ names = {}, page = 1, pages = 1 }, catalog.page({}, 4))
  end)
end)

describe("catalog.trend", function()
  it("compares the oldest and newest samples", function()
    assert.are.equal("up", catalog.trend({ 10, 9, 11 }))
    assert.are.equal("down", catalog.trend({ 10, 12, 9 }))
    assert.are.equal("flat", catalog.trend({ 10, 10.05 }))
    assert.are.equal("flat", catalog.trend({}))
  end)
end)

describe("catalog.format_credits", function()
  it("shows two decimals under a thousand and suffixes above", function()
    assert.are.equal("0.42", catalog.format_credits(0.4249))
    assert.are.equal("999.99", catalog.format_credits(999.99))
    assert.are.equal("1.23k", catalog.format_credits(1234))
    assert.are.equal("45.6M", catalog.format_credits(45.6e6))
    assert.are.equal("123G", catalog.format_credits(123.4e9))
    assert.are.equal("-2.50k", catalog.format_credits(-2500))
  end)
end)

describe("catalog.parse_quantity", function()
  it("accepts positive whole numbers and rejects the rest", function()
    assert.are.equal(12, catalog.parse_quantity("12"))
    assert.are.equal(3, catalog.parse_quantity("3.9"))
    for _, text in ipairs({ "", "abc", "0", "-5", "inf", "nan" }) do
      assert.is_nil(catalog.parse_quantity(text), text)
    end
  end)
end)
