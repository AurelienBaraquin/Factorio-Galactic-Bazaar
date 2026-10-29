local force_registry = require("scripts.core.force_registry")

local function new_state() return { balance = 0, journal = {}, markets = {} } end

describe("force_registry.ensure", function()
  it("creates a missing state with its account", function()
    local forces = {}
    local state = force_registry.ensure(forces, 1)
    assert.are.same(new_state(), state)
    assert.are.equal(state, forces[1])
  end)

  it("returns the existing state, filling in fields it lacks", function()
    local existing = { marker = true }
    local forces = { [1] = existing }
    assert.are.equal(existing, force_registry.ensure(forces, 1))
    assert.is_true(existing.marker)
    assert.are.equal(0, existing.balance)
  end)
end)

describe("force_registry.sync", function()
  it("creates states for new forces and keeps existing ones", function()
    local existing = { marker = true, balance = 5, journal = {}, markets = {} }
    local forces = { [1] = existing }
    force_registry.sync(forces, { 1, 2, 3 })
    assert.are.equal(existing, forces[1])
    assert.are.same(new_state(), forces[2])
    assert.are.same(new_state(), forces[3])
  end)

  it("drops states of forces that no longer exist", function()
    local forces = { [1] = new_state(), [4] = new_state(), [7] = new_state() }
    force_registry.sync(forces, { 1 })
    assert.are.same({ [1] = new_state() }, forces)
  end)
end)

describe("force_registry.merge", function()
  it("removes the source and keeps the destination state", function()
    local destination = { marker = true, balance = 0, journal = {}, markets = {} }
    local forces = { [1] = destination, [2] = new_state() }
    force_registry.merge(forces, 2, 1)
    assert.is_nil(forces[2])
    assert.are.equal(destination, forces[1])
  end)

  it("adds the source balance to the destination", function()
    local forces = {
      [1] = { balance = 10, journal = {}, markets = {} },
      [2] = { balance = 32, journal = {}, markets = {} },
    }
    force_registry.merge(forces, 2, 1)
    assert.are.equal(42, forces[1].balance)
  end)

  it("creates the destination state when it is missing", function()
    local forces = { [2] = new_state() }
    force_registry.merge(forces, 2, 1)
    assert.are.same({ [1] = new_state() }, forces)
  end)
end)
